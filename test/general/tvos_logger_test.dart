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
import 'package:flutter_tvos/executable.dart' show TvosMainFlags, mainFlags, mainLogger;
import 'package:flutter_tvos/tvos_logger.dart';

import '../src/common.dart';
import '../src/fakes.dart';

/// The logger `flutter-tvos` installs (flutter-tvos#100).
///
/// Stock requires the daemon and machine loggers by type: `daemon` and
/// `run --machine` with `asLogger`, `attach --machine` with a cast on the
/// logger itself. Before this was fixed the override always
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
  }) => createTvosLogger(
    terminal: Terminal.test(),
    stdio: stdio,
    outputPreferences: OutputPreferences.test(),
    verbose: verbose,
    prefixedErrors: prefixedErrors,
    machine: machine,
    daemon: daemon,
    windows: windows,
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

  // What main installs, from the command line as main reads it. The cases
  // above call createTvosLogger with flags already chosen; these hold how main
  // chooses them, which is where #100 came back if they were all false.
  group('the logger main installs', () {
    Logger fromArgs(List<String> args) => mainLogger(
      mainFlags(args),
      terminal: Terminal.test(),
      stdio: stdio,
      outputPreferences: OutputPreferences.test(),
      windows: false,
    );

    for (final args in <List<String>>[
      <String>['daemon'],
      <String>['-v', 'daemon'],
      <String>['--verbose', 'daemon'],
    ]) {
      testWithoutContext('`${args.join(' ')}` gets the NotifyingLogger the daemon looks up', () {
        final Logger logger = fromArgs(args);
        expect(asLogger<NotifyingLogger>(logger), same(logger));
        expect(logger.isVerbose, args.length > 1);
        expect(asLogger<TvosCategoryRewritingLogger>(logger), isA<TvosCategoryRewritingLogger>());
      });
    }

    for (final args in <List<String>>[
      <String>['run', '--machine'],
      <String>['attach', '--machine', '-d', '1234-ABCD'],
      <String>['--machine', '--version'],
      <String>['-v', 'devices', '--machine'],
    ]) {
      testWithoutContext('`${args.join(' ')}` gets the MachineOutputLogger run and attach require', () {
        final Logger logger = fromArgs(args);
        expect(logger, isA<MachineOutputLogger>());
        expect(asLogger<MachineOutputLogger>(logger), same(logger));
        expect(asLogger<TvosCategoryRewritingLogger>(logger), isA<TvosCategoryRewritingLogger>());
      });
    }

    testWithoutContext('`devices` gets the rewriting logger over the terminal', () {
      final Logger logger = fromArgs(<String>['devices']);
      expect(logger, isA<TvosCategoryRewritingLogger>());
      expect(logger.isVerbose, isFalse);
      expect(logger.isMachine, isFalse);
    });

    testWithoutContext('`-v devices` is verbose', () {
      expect(fromArgs(<String>['-v', 'devices']).isVerbose, isTrue);
    });

    for (final args in <List<String>>[
      <String>['-v', 'help'],
      <String>['-v', 'doctor'],
      <String>['-v', 'run', '-h'],
      <String>['-v', 'run', '-?'],
    ]) {
      testWithoutContext('`${args.join(' ')}` mutes verbose logging, as stock does', () {
        expect(fromArgs(args).isVerbose, isFalse);
      });
    }

    testWithoutContext('`-vv doctor` stays verbose', () {
      expect(fromArgs(<String>['-vv', 'doctor']).isVerbose, isTrue);
    });

    testWithoutContext('the flags runner.run is given', () {
      final args = <String>['-v', 'run', '/?'];
      final TvosMainFlags flags = mainFlags(args);
      expect(args, <String>['-v', 'run', '-h'], reason: 'the help idioms become -h, as in stock');
      expect(flags.verbose, isTrue);
      expect(flags.verboseHelp, isTrue);
      expect(flags.muteCommandLogging, isTrue);
      expect(mainFlags(<String>['--prefixed-errors', 'devices']).prefixedErrors, isTrue);
      expect(mainFlags(<String>['devices']).prefixedErrors, isFalse);
    });
  });

  // createTvosLogger calls stock's LoggerFactory for the base of the chain
  // and repeats its daemon and machine branches, to put the rewriting logger
  // beneath them. flutter-tvos has no widget-preview command, so stock is
  // asked without it. If a Flutter update changes those
  // branches, their order, or how the base is built, this fails: the two
  // chains must match type for type once the rewriting logger is taken out.
  testWithoutContext('matches stock LoggerFactory for every combination of flags', () {
    final factory = LoggerFactory(
      terminal: Terminal.test(),
      stdio: stdio,
      outputPreferences: OutputPreferences.test(),
    );
    for (var bits = 0; bits < 32; bits++) {
      bool flag(int i) => bits & (1 << i) != 0;
      final bool verbose = flag(0);
      final bool prefixedErrors = flag(1);
      final bool machine = flag(2);
      final bool daemon = flag(3);
      final bool windows = flag(4);
      final List<Type> stock = _chain(
        factory.createLogger(
          verbose: verbose,
          prefixedErrors: prefixedErrors,
          machine: machine,
          daemon: daemon,
          windows: windows,
          widgetPreviews: false,
        ),
      );
      final List<Type> ours = _chain(
        create(
          verbose: verbose,
          prefixedErrors: prefixedErrors,
          machine: machine,
          daemon: daemon,
          windows: windows,
        ),
      );
      final flags =
          'verbose: $verbose, prefixedErrors: $prefixedErrors, machine: $machine, '
          'daemon: $daemon, windows: $windows';
      expect(ours, contains(TvosCategoryRewritingLogger), reason: flags);
      expect(ours.where((Type t) => t != TvosCategoryRewritingLogger), stock, reason: flags);
      // A mode logger (daemon, machine) stays outermost: stock casts the
      // logger itself to the machine one.
      if (daemon || machine) {
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
