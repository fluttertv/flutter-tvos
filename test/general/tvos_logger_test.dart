// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The chain comparison below reads DelegatingLogger's private delegate, which
// has no public accessor. Tests run on the VM, where mirrors are available.
import 'dart:mirrors';

import 'package:flutter_tools/executable.dart' show LoggerFactory;
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/commands/daemon.dart' show MachineOutputLogger, NotifyingLogger;
import 'package:flutter_tools/src/commands/widget_preview.dart'
    show WidgetPreviewMachineAwareLogger;
import 'package:flutter_tvos/tvos_logger.dart';

import '../src/common.dart';
import '../src/fakes.dart';

/// The logger `flutter-tvos` installs (flutter-tvos#100).
///
/// Stock requires the daemon and machine loggers by type: `daemon` and
/// `run --machine` with `asLogger`, `attach --machine` and `widget-preview`
/// with a cast on the logger itself. Before this was fixed the override always
/// built `TvosCategoryRewritingLogger(StdoutLogger)`, and all three commands
/// failed before doing anything.
void main() {
  const tvosLine =
      'Apple TV 4K (3rd generation) (mobile) • 1234-ABCD • tvos • tvOS 27.0 (simulator)';
  const rewrittenLine =
      'Apple TV 4K (3rd generation) (tv)     • 1234-ABCD • tvos • tvOS 27.0 (simulator)';

  late FakeStdio stdio;

  setUp(() {
    stdio = FakeStdio();
  });

  Logger create({
    bool verbose = false,
    bool prefixedErrors = false,
    bool machine = false,
    bool daemon = false,
    bool windows = false,
    bool widgetPreviews = false,
  }) => createTvosLogger(
    terminal: Terminal.test(),
    stdio: stdio,
    outputPreferences: OutputPreferences.test(),
    verbose: verbose,
    prefixedErrors: prefixedErrors,
    machine: machine,
    daemon: daemon,
    windows: windows,
    widgetPreviews: widgetPreviews,
  );

  String stdout() => stdio.writtenToStdout.join();

  group('daemon mode', () {
    testWithoutContext('the chain holds the NotifyingLogger the daemon looks up', () {
      final Logger logger = create(daemon: true);
      expect(logger, isA<NotifyingLogger>());
      expect(asLogger<NotifyingLogger>(logger), same(logger));
      expect(asLogger<TvosCategoryRewritingLogger>(logger), isA<TvosCategoryRewritingLogger>());
    });

    testWithoutContext('also with --verbose', () {
      final Logger logger = create(daemon: true, verbose: true);
      expect(asLogger<NotifyingLogger>(logger), same(logger));
      expect((logger as NotifyingLogger).verbose, isTrue);
      expect(asLogger<VerboseLogger>(logger), isA<VerboseLogger>());
    });
  });

  group('machine mode', () {
    testWithoutContext('the logger is the MachineOutputLogger run and attach require', () {
      final Logger logger = create(machine: true);
      // `run --machine` looks it up with asLogger; `attach --machine` casts.
      expect(asLogger<MachineOutputLogger>(logger), same(logger));
      expect(logger as MachineOutputLogger, isNotNull);
      expect(logger.isMachine, isTrue);
      expect(asLogger<TvosCategoryRewritingLogger>(logger), isA<TvosCategoryRewritingLogger>());
    });

    testWithoutContext('reports no colour and no terminal, and shows no spinner', () {
      final Logger logger = create(machine: true);
      expect(logger.supportsColor, isFalse);
      expect(logger.hasTerminal, isFalse);
      logger.startProgress('Launching lib/main.dart on Apple TV').stop();
      expect(stdout(), isEmpty);
    });

    testWithoutContext('with --verbose the machine logger stays outermost', () {
      final Logger logger = create(machine: true, verbose: true);
      expect(logger, isA<MachineOutputLogger>());
      expect(logger.isVerbose, isTrue);
      expect(asLogger<VerboseLogger>(logger), isA<VerboseLogger>());
    });

    testWithoutContext('passes JSON lines through untouched', () {
      final Logger logger = create(machine: true);
      // A JSON document whose text happens to match the device-line pattern.
      const json = '[{"name":"$tvosLine","targetPlatform":"tvos"}]';
      logger.printStatus(json);
      expect(stdout(), '$json\n');
    });

    testWithoutContext('still rewrites a device table printed as text', () {
      create(machine: true).printStatus(tvosLine);
      expect(stdout(), '$rewrittenLine\n');
    });
  });

  group('normal and verbose modes', () {
    testWithoutContext('normal mode is the rewriting logger over StdoutLogger', () {
      final Logger logger = create();
      expect(logger, isA<TvosCategoryRewritingLogger>());
      expect(asLogger<StdoutLogger>(logger), isA<StdoutLogger>());
      expect(logger.isVerbose, isFalse);
      expect(logger.isMachine, isFalse);
      expect(() => asLogger<NotifyingLogger>(logger), throwsStateError);
      expect(() => asLogger<MachineOutputLogger>(logger), throwsStateError);
    });

    testWithoutContext('verbose mode puts VerboseLogger beneath the rewriting logger', () {
      final Logger logger = create(verbose: true);
      expect(logger, isA<TvosCategoryRewritingLogger>());
      expect(asLogger<VerboseLogger>(logger), isA<VerboseLogger>());
      expect(logger.isVerbose, isTrue);
    });

    testWithoutContext('rewrites (mobile) to (tv) on a tvOS device line', () {
      create().printStatus(tvosLine);
      expect(stdout(), '$rewrittenLine\n');
    });

    testWithoutContext('rewrites in verbose mode too', () {
      create(verbose: true).printStatus(tvosLine);
      expect(stdout(), contains(rewrittenLine));
    });

    testWithoutContext('leaves other devices alone', () {
      const iosLine = 'iPhone 17 (mobile) • 5678-EFGH • ios • iOS 26.5 (simulator)';
      create().printStatus(iosLine);
      expect(stdout(), '$iosLine\n');
    });

    testWithoutContext('rewrites a device whose name starts with a bracket', () {
      const line = '[Lab] Apple TV (mobile) • 1234 • tvos • tvOS 27.0';
      create().printStatus(line);
      expect(stdout(), '[Lab] Apple TV (tv)     • 1234 • tvos • tvOS 27.0\n');
    });
  });

  testWithoutContext('widget-preview gets the logger it casts to', () {
    final Logger logger = create(widgetPreviews: true, machine: true);
    expect(logger, isA<WidgetPreviewMachineAwareLogger>());
    expect(asLogger<TvosCategoryRewritingLogger>(logger), isA<TvosCategoryRewritingLogger>());
  });

  // createTvosLogger calls stock's LoggerFactory for the base of the chain
  // and repeats its daemon, machine and widget-preview branches, to put the
  // rewriting logger beneath them. If a Flutter update changes those
  // branches, their order, or how the base is built, this fails: the two
  // chains must match type for type once the rewriting logger is taken out.
  testWithoutContext('matches stock LoggerFactory for every combination of flags', () {
    final factory = LoggerFactory(
      terminal: Terminal.test(),
      stdio: stdio,
      outputPreferences: OutputPreferences.test(),
    );
    for (var bits = 0; bits < 64; bits++) {
      bool flag(int i) => bits & (1 << i) != 0;
      final bool verbose = flag(0);
      final bool prefixedErrors = flag(1);
      final bool machine = flag(2);
      final bool daemon = flag(3);
      final bool windows = flag(4);
      final bool widgetPreviews = flag(5);
      final List<Type> stock = _chain(
        factory.createLogger(
          verbose: verbose,
          prefixedErrors: prefixedErrors,
          machine: machine,
          daemon: daemon,
          windows: windows,
          widgetPreviews: widgetPreviews,
        ),
      );
      final List<Type> ours = _chain(
        create(
          verbose: verbose,
          prefixedErrors: prefixedErrors,
          machine: machine,
          daemon: daemon,
          windows: windows,
          widgetPreviews: widgetPreviews,
        ),
      );
      final flags =
          'verbose: $verbose, prefixedErrors: $prefixedErrors, machine: $machine, '
          'daemon: $daemon, windows: $windows, widgetPreviews: $widgetPreviews';
      expect(ours, contains(TvosCategoryRewritingLogger), reason: flags);
      expect(ours.where((Type t) => t != TvosCategoryRewritingLogger), stock, reason: flags);
      // A mode logger (daemon, machine, widget-preview) stays outermost:
      // stock casts the logger itself to some of them.
      if (daemon || machine || widgetPreviews) {
        expect(ours.first, stock.first, reason: flags);
      }
    }
  });
}

final Symbol _delegateField = MirrorSystem.getSymbol(
  '_delegate',
  reflectClass(DelegatingLogger).owner! as LibraryMirror,
);

/// The runtime types of [logger] and each delegate beneath it, outermost first.
List<Type> _chain(Logger logger) {
  final types = <Type>[];
  Logger? current = logger;
  while (current != null) {
    types.add(current.runtimeType);
    current = current is DelegatingLogger
        ? reflect(current).getField(_delegateField).reflectee as Logger
        : null;
  }
  return types;
}
