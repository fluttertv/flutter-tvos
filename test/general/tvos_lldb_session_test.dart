// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// What an Apple TV's debug session actually sends lldb, end to end: the
// tvOS version read from devicectl, through TvosDevice's LLDB factory and
// `attachLldb`, the two calls `startApp` makes, into a real LLDB attaching to
// a fake lldb process.
//
// Flutter 3.47.5's LLDB decides from that version whether to set the JIT
// breakpoint with `--auto-continue` and a `detach` stop hook (below 27), or
// without either, driving stops by hand (27 and later). Asserting the version
// handed to a replaced factory stops one call short: a factory that dropped it
// would pass. This asserts the commands.
//
// The fake answers as lldb does over an iOS device tunnel; how lldb words its
// stops over a tvOS one is what a tvOS 27 Apple TV has yet to show (#84).

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/ios/lldb.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tvos/tvos_device.dart';
import 'package:flutter_tvos/tvos_emulator.dart';
import 'package:test/fake.dart';

import '../src/common.dart';
import '../src/context.dart';

const _autoContinueBreakpoint =
    r"breakpoint set --auto-continue true --func-regex '^NOTIFY_DEBUGGER_ABOUT_RX_PAGES$'";
const _manualBreakpoint = r"breakpoint set --func-regex '^NOTIFY_DEBUGGER_ABOUT_RX_PAGES$'";
const _stopHook = 'target stop-hook add -o "thread backtrace all" -o "detach"';

String _devicectl(String osVersionNumber) =>
    '''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room", "osVersionNumber": "$osVersionNumber", "osBuildUpdate": "24A123"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical", "productType": "AppleTV14,1"}
}]}}
''';

void main() {
  late _FakeLldbProcessManager lldbProcess;

  setUp(() {
    lldbProcess = _FakeLldbProcessManager();
  });

  Map<Type, Generator> overrides() => <Type, Generator>{
    ProcessManager: () => lldbProcess,
    FileSystem: () => MemoryFileSystem.test(),
    Platform: () => FakePlatform(environment: <String, String>{'HOME': '/Users/dev'}),
  };

  /// Attaches a debug build the way `startApp` does, through the device's own
  /// factory and `attachLldb`, and returns every line lldb was sent.
  Future<List<String>> attach(String osVersionNumber) async {
    final TvosDevice device = TvosEmulator.parseDevicectlOutput(
      _devicectl(osVersionNumber),
      BufferLogger.test(),
    ).single;
    final LLDB lldb = device.lldbForDebugSession(_FakeXcodeProjectInterpreter());

    final bool attached = await device.attachLldb(
      lldb: lldb,
      lldbLogForwarder: LLDBLogForwarder(),
      pid: 568,
      mode: BuildMode.debug,
      // A wrong mode or a missing answer fails here, not in a hung test.
      timeout: const Duration(seconds: 10),
    );
    lldb.exit();

    expect(attached, isTrue);
    expect(lldbProcess.started, <List<String>>[
      <String>['xcrun', 'lldb'],
    ]);
    final List<String> sent = lldbProcess.received;
    expect(sent, contains('device select ${device.id}'));
    expect(sent, contains('device process attach --pid 568'));
    // Upstream gives lldb an iOS sysroot when Device Support has symbols;
    // flutter-tvos gives it none, and lldb switches to remote-tvos and finds
    // the symbols itself (#84).
    expect(sent.where((String line) => line.startsWith('platform select')), isEmpty);
    return sent;
  }

  testUsingContext(
    'below tvOS 27, sets the JIT breakpoint to continue on its own and detaches on a crash',
    () async {
      final List<String> sent = await attach('26.6');

      expect(sent, contains(_autoContinueBreakpoint));
      expect(sent, contains(_stopHook));
    },
    overrides: overrides(),
  );

  testUsingContext('from tvOS 27, leaves both to the stop handling LLDB does by hand', () async {
    final List<String> sent = await attach('27.0');

    expect(sent, contains(_manualBreakpoint));
    expect(sent, isNot(contains(_autoContinueBreakpoint)));
    expect(sent, isNot(contains(_stopHook)));
  }, overrides: overrides());
}

class _FakeXcodeProjectInterpreter extends Fake implements XcodeProjectInterpreter {
  @override
  List<String> xcrunCommand() => <String>['xcrun'];
}

/// Starts [_FakeLldbProcess]es and remembers what was started.
class _FakeLldbProcessManager extends Fake implements ProcessManager {
  final List<List<String>> started = <List<String>>[];
  final List<String> received = <String>[];

  @override
  Future<io.Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async {
    started.add(<String>[for (final Object part in command) '$part']);
    return _FakeLldbProcess(received);
  }
}

/// Plays lldb's side of an attach: answers each command with the line LLDB
/// waits for, and records every line it is sent.
class _FakeLldbProcess extends Fake implements io.Process {
  _FakeLldbProcess(this._received) {
    stdin = io.IOSink(_stdin.sink);
    _stdin.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(_answer);
  }

  final List<String> _received;
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<List<int>>();
  final _exitCode = Completer<int>();

  @override
  late final io.IOSink stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 4242;

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
      unawaited(_stdout.close());
    }
    return true;
  }

  void _answer(String line) {
    _received.add(line);
    final String? reply = switch (line) {
      _ when line.startsWith('breakpoint set ') => 'Breakpoint 1: no locations (pending).',
      _ when line.startsWith('device process attach ') =>
        'Process 568 stopped\n'
            '* thread #1, stop reason = signal SIGSTOP\n'
            'Target 0: (Runner) stopped.',
      _ when line.startsWith('target stop-hook add ') => 'Stop hook #1 added.',
      'platform status' => '  Platform: remote-tvos',
      'process continue' => '1 location added to breakpoint 1',
      _ => null,
    };
    if (reply != null && !_stdout.isClosed) {
      _stdout.add(utf8.encode('$reply\n'));
    }
  }
}
