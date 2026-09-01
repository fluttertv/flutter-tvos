// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A self-contained LLDB driver for attaching to a Flutter app running on a
/// physical Apple TV.
///
/// Flutter 3.32.8's `flutter_tools` has no `src/ios/lldb.dart` — that landed
/// upstream after this version — so the 3.32.8 line of flutter-tvos had no way
/// to attach a debugger and fell straight through to the Xcode-automation
/// fallback, which does not reliably hold a session on a wirelessly-paired
/// Apple TV. Debug mode on a physical Apple TV *requires* a persistent tracer:
/// the engine's ptrace check refuses to create a FlutterEngine in debug mode
/// unless the process is traced, so without one the app publishes its
/// `_dartVmService._tcp` record and dies a second or two later — which is
/// exactly the "connection to device ended too early" failure this file fixes.
///
/// This is a port of upstream `flutter_tools/lib/src/ios/lldb.dart` (BSD-3,
/// The Flutter Authors), reduced to the 3.32.8 `flutter_tools` surface:
///
///  * `utf8LineDecoder` does not exist at 3.32.8 — decode with
///    `utf8.decoder` + `LineSplitter`, the idiom `ios_deploy.dart` itself uses
///    at this version.
///  * `XcodeProjectInterpreter` is not injected; the `xcrun` prefix is passed
///    in as a plain argument list so the caller can source it from
///    `globals.xcode`.
///  * Upstream's NOTIFY_DEBUGGER_ABOUT_RX_PAGES breakpoint is off by default
///    here, because the tvOS engine never calls that hook — see
///    [TvosLLDB._useRxPageBreakpoint] for why keeping it is a net loss on this
///    platform, and what LLDB does instead.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';

/// LLDB is the default debugger in Xcode on macOS. Once the application has
/// launched on a physical tvOS device, you can attach to it using LLDB.
///
/// See `xcrun devicectl device process launch --help` for more information.
class TvosLLDB {
  TvosLLDB({
    required Logger logger,
    required ProcessUtils processUtils,
    List<String> xcrunCommand = const <String>['xcrun'],
    bool useRxPageBreakpoint = false,
  }) : _logger = logger,
       _processUtils = processUtils,
       _xcrunCommand = xcrunCommand,
       _useRxPageBreakpoint = useRxPageBreakpoint;

  final Logger _logger;
  final ProcessUtils _processUtils;
  final List<String> _xcrunCommand;

  /// Whether to install upstream's NOTIFY_DEBUGGER_ABOUT_RX_PAGES breakpoint
  /// and run LLDB synchronously.
  ///
  /// Off by default, and that is the tvOS-specific part of this port. Upstream
  /// needs the breakpoint because on iOS >= 18.4 the Dart VM asks the debugger
  /// to touch its RX pages; our tvOS engine takes the other route entirely —
  /// it disables `--write-protect-code`, so JIT pages are RWX from the start
  /// and that hook is never called. Keeping the breakpoint anyway costs two
  /// things that measurably hurt on a wireless CoreDevice tunnel:
  ///
  ///  * `breakpoint set --func-regex` makes LLDB scan every symbol of every
  ///    module as it loads — including the ~100 MB unstripped debug
  ///    Flutter.framework, read over the tunnel.
  ///  * With `SetAsync(False)`, `process continue` blocks until the process
  ///    stops again, so the only proof the app resumed is the breakpoint
  ///    resolving. On an engine that never calls the hook that proof can be
  ///    slow, and on one where the symbol is absent it never arrives at all.
  ///
  /// With it off, LLDB stays in async mode: `process continue` returns at once
  /// and prints "Process N resuming". The debugger remains attached, which is
  /// the only thing tvOS debug mode actually requires (the engine's ptrace
  /// check wants a tracer, not a breakpoint).
  final bool _useRxPageBreakpoint;

  _LLDBProcess? _lldbProcess;

  /// Whether or not an LLDB process is running.
  bool get isRunning => _lldbProcess != null;

  /// Whether or not the LLDB process has attached and resumed the application
  /// process.
  bool _isAttached = false;

  /// The process id of the application running on the tvOS device.
  int? get appProcessId => _lldbProcess?.appProcessId;

  _LLDBLogPatternCompleter? _logCompleter;

  /// Pattern of lldb log when the process is stopped.
  ///
  /// Example: (lldb) Process 6152 stopped
  static final RegExp _lldbProcessStopped = RegExp(r'Process \d* stopped');

  /// Pattern of lldb log when the process is resuming.
  ///
  /// Example: (lldb) Process 6152 resuming
  static final RegExp _lldbProcessResuming = RegExp(r'Process \d+ resuming');

  /// Pattern of lldb log when the process has started and the breakpoint is
  /// added, or when it simply resumes.
  ///
  /// Example: (lldb) 1 location added to breakpoint 1
  static final RegExp _lldbResumedInDebug = RegExp(
    r'(location added to breakpoint|Process \d+ resuming)',
  );

  /// Pattern of lldb log when the breakpoint is added.
  ///
  /// Example: Breakpoint 1: no locations (pending).
  static final RegExp _breakpointPattern = RegExp(r'Breakpoint (\d+)*:');

  /// Pattern of lldb log when a stop hook is added.
  ///
  /// Example: Stop hook #1 added.
  static final RegExp _stopHookAddedPattern = RegExp(r'Stop hook #\d+ added');

  /// Pattern of lldb log when a stop hook is processed.
  ///
  /// Example: "- Hook 1 (thread backtrace all)"
  static final RegExp _stopHookProcessedPattern = RegExp(r'- Hook \d+');

  /// A list of log patterns to ignore.
  static final List<Pattern> _ignorePatterns = <Pattern>[
    RegExp(r'\d+ location added to breakpoint \d+'),
    _stopHookProcessedPattern,
  ];

  /// Breakpoint script required for JIT on iOS.
  ///
  /// Retained for parity with upstream. The tvOS engine disables Dart's code
  /// write-protection outright (JIT pages are mapped RWX up front), so
  /// NOTIFY_DEBUGGER_ABOUT_RX_PAGES is never called there and this script
  /// never runs — but the symbol is still compiled into the framework, and
  /// leaving the handler in place costs nothing and keeps this file a
  /// recognisable port of upstream.
  static const String _pythonScript = '''
"""Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages."""
base = frame.register["x0"].GetValueAsAddress()
page_len = frame.register["x1"].GetValueAsUnsigned()

# Note: NOTIFY_DEBUGGER_ABOUT_RX_PAGES will check contents of the
# first page to see if handled it correctly. This makes diagnosing
# misconfiguration (e.g. missing breakpoint) easier.
data = bytearray(page_len)
data[0:8] = b'IHELPED!'

error = lldb.SBError()
frame.GetThread().GetProcess().WriteMemory(base, data, error)
if not error.Success():
    print(f'Failed to write into {base}[+{page_len}]', error)
    return

# If the returned value is False, that tells LLDB not to stop at the breakpoint
return False
''';

  /// Starts an LLDB process and inputs commands to start debugging the
  /// [appProcessId]. This starts a debugserver on the device, which is what
  /// makes the process traced — the precondition tvOS debug mode has.
  ///
  /// After attaching and starting the app process, forwards logs to
  /// [lldbLogForwarder]. This may include crash logs.
  Future<bool> attachAndStart({
    required String deviceId,
    required int appProcessId,
    required TvosLLDBLogForwarder lldbLogForwarder,
    required BuildMode mode,
  }) async {
    Timer? timer;
    try {
      timer = Timer(const Duration(minutes: 1), () {
        _logger.printStatus(
          'LLDB is taking longer than expected to start debugging the app on '
          'the Apple TV. Debugging is wireless-only on tvOS, so a cold or busy '
          'CoreDevice tunnel can make the attach slow.',
        );
      });

      final bool start = await _startLLDB(
        appProcessId: appProcessId,
        lldbLogForwarder: lldbLogForwarder,
      );
      if (!start) {
        return false;
      }
      await _selectDevice(deviceId);
      if (mode == BuildMode.debug && _useRxPageBreakpoint) {
        await _setBreakpoint();
      }
      await _attachToAppProcess(appProcessId);
      await _setupStopHooks();
      await _resumeProcess(mode);
      _isAttached = true;
    } on _LLDBError catch (e) {
      _logger.printTrace('lldb failed with error: ${e.message}');
      exit();
      return false;
    } finally {
      timer?.cancel();
    }
    return true;
  }

  /// Starts the LLDB process and leaves it running.
  ///
  /// Streams `stdout` and `stderr`. When receiving a log from `stdout`, check
  /// if it matches the pattern [_logCompleter] is waiting for. If a log is sent
  /// to `stderr`, complete with an error and stop the process.
  Future<bool> _startLLDB({
    required int appProcessId,
    required TvosLLDBLogForwarder lldbLogForwarder,
  }) async {
    if (_lldbProcess != null) {
      _logger.printTrace(
        'An LLDB process is already running. It must be stopped before starting a new one.',
      );
      return false;
    }
    try {
      _lldbProcess = _LLDBProcess(
        process: await _processUtils.start(<String>[..._xcrunCommand, 'lldb']),
        appProcessId: appProcessId,
        logger: _logger,
      );
      final StreamSubscription<String> stdoutSubscription = _lldbProcess!.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
            if (_isAttached && !_ignoreLog(line)) {
              // Only forwards logs after LLDB is attached. All logs before then
              // are part of the attach process.
              lldbLogForwarder.addLog(line);
            } else {
              _logger.printTrace('[lldb]: $line');
              _logCompleter?.checkForMatch(line);
            }
          });

      final StreamSubscription<String> stderrSubscription = _lldbProcess!.stderr
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
            _monitorError(line);
            if (_isAttached && !_ignoreLog(line)) {
              lldbLogForwarder.addLog(line);
            } else {
              _logger.printTrace('[lldb]: $line');
            }
          });

      unawaited(
        _lldbProcess!.exitCode
            .then((int status) async {
              _logger.printTrace('lldb exited with code $status');
              await stdoutSubscription.cancel();
              await stderrSubscription.cancel();
            })
            .whenComplete(() async {
              _lldbProcess = null;
            }),
      );
    } on ProcessException catch (exception) {
      _logger.printTrace('Process exception running lldb:\n$exception');
      return false;
    }
    return true;
  }

  /// Kill [_lldbProcess] if available and set it to null.
  bool exit() {
    final bool success = (_lldbProcess == null) || _lldbProcess!.kill();
    _lldbProcess = null;
    if (_logCompleter != null) {
      _logCompleter!.completeError(_LLDBError('LLDB process exited'));
    }
    _logCompleter = null;
    _isAttached = false;
    return success;
  }

  /// Selects a device for LLDB to interact with.
  Future<void> _selectDevice(String deviceId) async {
    await _lldbProcess?.stdinWriteln('device select $deviceId');
  }

  /// Attaches LLDB to the [appProcessId] running on the device.
  Future<void> _attachToAppProcess(int appProcessId) async {
    // Since the app starts stopped (--start-stopped), we expect a stopped state
    // after attaching.
    final Future<String> futureLog = _startWaitingForLog(
      _lldbProcessStopped,
    ).then((String value) => value, onError: _handleAsyncError);

    await _lldbProcess?.stdinWriteln('device process attach --pid $appProcessId');
    await futureLog;
  }

  /// Sets a breakpoint, waits for it to print the breakpoint id, and adds a
  /// python script command to be executed whenever the breakpoint is hit.
  Future<void> _setBreakpoint() async {
    final Future<String> futureLog = _startWaitingForLog(
      _breakpointPattern,
    ).then((String value) => value, onError: _handleAsyncError);

    await _lldbProcess?.stdinWriteln(
      r"breakpoint set --func-regex '^NOTIFY_DEBUGGER_ABOUT_RX_PAGES$'",
    );
    final String log = await futureLog;
    final Match? match = _breakpointPattern.firstMatch(log);
    final String? breakpointId = match?.group(1);
    if (breakpointId == null) {
      throw _LLDBError('LLDB failed to get breakpoint from log: $log');
    }

    // Once it has the breakpoint id, set the python script.
    // For more information, see: lldb > help break command add
    await _lldbProcess?.stdinWriteln('breakpoint command add --script-type python $breakpointId');
    await _lldbProcess?.stdinWriteln(_pythonScript);
    await _lldbProcess?.stdinWriteln('DONE');

    // Disable asynchronous mode to work around issues with rearming of
    // breakpoints. See https://github.com/flutter/flutter/issues/184254 and
    // https://github.com/llvm/llvm-project/issues/190956.
    await _lldbProcess?.stdinWriteln('script lldb.debugger.SetAsync(False)');
  }

  /// Resume the stopped process.
  Future<void> _resumeProcess(BuildMode mode) async {
    final bool breakpointInstalled = mode == BuildMode.debug && _useRxPageBreakpoint;
    final Future<String> futureLog = _startWaitingForLog(
      // With the breakpoint installed LLDB is synchronous, so `process
      // continue` prints nothing until the process stops again and the only
      // signal is the breakpoint resolving — accept the resume log as well, in
      // case the hook is never reached. Without it LLDB is asynchronous and
      // always prints "Process N resuming".
      breakpointInstalled ? _lldbResumedInDebug : _lldbProcessResuming,
    ).then((String value) => value, onError: _handleAsyncError);

    await _lldbProcess?.stdinWriteln('process continue');
    await futureLog;
  }

  /// Adds a stop hook to print the backtrace of all threads and then detach the
  /// debugger from the process once it stops, such as when it crashes.
  ///
  /// Without this, the debugger would remain attached to the process and the
  /// app will hang on crash.
  Future<void> _setupStopHooks() async {
    final Future<String> futureLog = _startWaitingForLog(
      _stopHookAddedPattern,
    ).then((String value) => value, onError: _handleAsyncError);
    await _lldbProcess?.stdinWriteln('target stop-hook add -o "thread backtrace all" -o "detach"');
    await futureLog;
  }

  /// Creates a completer and returns its future. Methods that utilize this
  /// should start waiting for the log before writing to stdin to avoid race
  /// conditions.
  ///
  /// When the [_lldbProcess]'s `stdout` receives a log that matches the
  /// [pattern], the future will complete.
  Future<String> _startWaitingForLog(RegExp pattern) async {
    if (_lldbProcess == null) {
      throw _LLDBError('LLDB is not running.');
    }
    _logCompleter = _LLDBLogPatternCompleter(pattern);
    return _logCompleter!.future;
  }

  Future<String> _handleAsyncError(Object error) async {
    if (error is _LLDBError) {
      throw error;
    }
    throw _LLDBError('Unexpected error when waiting for lldb.');
  }

  /// Checks if [error] is a fatal error and stops the process if so.
  void _monitorError(String error) {
    // The LLDB process does not stop when it receives these errors but is no
    // longer debugging the application. When one of these errors is received,
    // stop the LLDB process.
    const List<String> fatalErrors = <String>[
      "error: 'device' is not a valid command.",
      "no device selected: use 'device select <identifier>' to select a device.",
      'The specified device was not found.',
      'Timeout while connecting to remote device.',
      'Internal logic error: Connection was invalidated',
    ];

    if (fatalErrors.contains(error)) {
      _logCompleter?.completeError(_LLDBError(error));
      exit();
    }
  }

  bool _ignoreLog(String log) {
    return _ignorePatterns.any((Pattern pattern) => log.contains(pattern));
  }
}

class _LLDBError implements Exception {
  _LLDBError(this.message);

  final String message;
}

/// A completer that waits for a log line to match a pattern.
class _LLDBLogPatternCompleter {
  _LLDBLogPatternCompleter(this._pattern);

  final RegExp _pattern;
  final Completer<String> _completer = Completer<String>();

  Future<String> get future => _completer.future;

  void checkForMatch(String line) {
    if (_completer.isCompleted) {
      return;
    }
    if (_pattern.hasMatch(line)) {
      _completer.complete(line);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}

/// A container class for associating a [Process] that is running LLDB with
/// the tvOS device process of an application.
class _LLDBProcess {
  _LLDBProcess({required Process process, required this.appProcessId, required Logger logger})
    : _lldbProcess = process,
      _logger = logger;

  final Process _lldbProcess;
  final int appProcessId;

  final Logger _logger;

  Stream<List<int>> get stdout => _lldbProcess.stdout;

  Stream<List<int>> get stderr => _lldbProcess.stderr;

  Future<int> get exitCode => _lldbProcess.exitCode;

  Future<void>? _stdinWriteFuture;

  bool kill() {
    return _lldbProcess.kill();
  }

  /// Writes [line] to [_lldbProcess]'s `stdin` and catches exceptions
  /// (see https://github.com/flutter/flutter/pull/139784).
  Future<void> stdinWriteln(String line, {void Function(Object, StackTrace)? onError}) async {
    Future<void> writeln() {
      return ProcessUtils.writelnToStdinGuarded(
        stdin: _lldbProcess.stdin,
        line: line,
        onError:
            onError ??
            (Object error, _) {
              _logger.printTrace('Could not write "$line" to stdin: $error');
            },
      );
    }

    _stdinWriteFuture = _stdinWriteFuture?.then<void>((_) => writeln()) ?? writeln();
    return _stdinWriteFuture;
  }
}

/// This class is used to forward logs from LLDB to any active listeners.
class TvosLLDBLogForwarder {
  final StreamController<String> _streamController = StreamController<String>.broadcast();

  Stream<String> get logLines => _streamController.stream;

  void addLog(String log) {
    if (!_streamController.isClosed) {
      _streamController.add(log);
    }
  }

  Future<bool> exit() async {
    if (_streamController.hasListener) {
      // Tell listeners the process died.
      await _streamController.close();
    }
    return true;
  }
}
