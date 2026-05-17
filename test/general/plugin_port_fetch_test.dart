// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/plugin_porting/source_fetcher.dart';

import '../src/common.dart';
import '../src/fake_process_manager.dart';

void main() {
  group('SourceSpec.parse', () {
    test('local path only', () {
      final SourceSpec s = SourceSpec.parse(positional: '../gadget_ios');
      expect(s.mode, FetchMode.localPath);
      expect(s.identifier, '../gadget_ios');
      expect(s.ref, isNull);
    });

    test('--from-pub only', () {
      final SourceSpec s = SourceSpec.parse(fromPub: 'gadget_ios');
      expect(s.mode, FetchMode.pub);
      expect(s.identifier, 'gadget_ios');
      expect(s.derivedName, 'gadget_ios');
    });

    test('--from-git with --ref', () {
      final SourceSpec s = SourceSpec.parse(
        fromGit: 'https://github.com/foo/gadget.git',
        ref: 'main',
      );
      expect(s.mode, FetchMode.git);
      expect(s.ref, 'main');
      expect(s.derivedName, 'gadget');
      expect(
        s.gitCloneArgs('/tmp/x'),
        <String>[
          'git', 'clone', '--depth', '1',
          '--branch', 'main',
          'https://github.com/foo/gadget.git', '/tmp/x',
        ],
      );
    });

    test('git clone args without ref omit --branch', () {
      final SourceSpec s =
          SourceSpec.parse(fromGit: 'git@github.com:foo/bar/');
      expect(s.derivedName, 'bar');
      expect(s.gitCloneArgs('/d'),
          <String>['git', 'clone', '--depth', '1', 'git@github.com:foo/bar/', '/d']);
    });

    test('rejects no source', () {
      expect(() => SourceSpec.parse(),
          throwsA(isA<SourceFetchError>().having((e) => e.message, 'm', contains('No source'))));
    });

    test('rejects more than one source', () {
      expect(
        () => SourceSpec.parse(positional: '.', fromPub: 'x'),
        throwsA(isA<SourceFetchError>()
            .having((e) => e.message, 'm', contains('exactly one'))),
      );
    });

    test('rejects --ref without --from-git', () {
      expect(
        () => SourceSpec.parse(fromPub: 'x', ref: 'main'),
        throwsA(isA<SourceFetchError>()
            .having((e) => e.message, 'm', contains('--ref is only valid'))),
      );
    });

    test('treats blank/whitespace as unset', () {
      expect(() => SourceSpec.parse(positional: '   '),
          throwsA(isA<SourceFetchError>()));
    });
  });

  group('SourceFetcher', () {
    late MemoryFileSystem fs;
    late BufferLogger logger;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
    });

    test('localPath returns the directory, errors when missing', () async {
      final Directory dir = fs.directory('/p')..createSync(recursive: true);
      final SourceFetcher f = SourceFetcher(
        fileSystem: fs,
        processManager: FakeProcessManager.empty(),
        logger: logger,
      );
      final Directory got = await f.resolve(
        SourceSpec.parse(positional: '/p'),
        workDir: fs.directory('/w')..createSync(),
      );
      expect(got.path, dir.path);

      await expectLater(
        f.resolve(SourceSpec.parse(positional: '/nope'),
            workDir: fs.directory('/w')),
        throwsA(isA<SourceFetchError>()),
      );
    });

    test('git clone success returns the checkout dir', () async {
      final Directory work = fs.directory('/w')..createSync(recursive: true);
      final String dest = fs.path.join(work.path, 'gadget');
      final FakeProcessManager pm = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: <String>[
            'git', 'clone', '--depth', '1',
            'https://github.com/foo/gadget.git', dest,
          ],
          onRun: (_) {
            fs.directory(dest).createSync(recursive: true);
            fs.directory(dest).childFile('pubspec.yaml').writeAsStringSync('name: gadget\n');
          },
        ),
      ]);
      final Directory got = await SourceFetcher(
        fileSystem: fs,
        processManager: pm,
        logger: logger,
      ).resolve(
        SourceSpec.parse(fromGit: 'https://github.com/foo/gadget.git'),
        workDir: work,
      );
      expect(fs.path.canonicalize(got.path), fs.path.canonicalize(dest));
      expect(got.existsSync(), isTrue);
      expect(pm, hasNoRemainingExpectations);
    });

    test('git clone failure raises SourceFetchError with stderr', () async {
      final Directory work = fs.directory('/w')..createSync(recursive: true);
      final String dest = fs.path.join(work.path, 'bar');
      final FakeProcessManager pm = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: <String>['git', 'clone', '--depth', '1', 'https://x/bar.git', dest],
          exitCode: 128,
          stderr: 'fatal: repository not found',
        ),
      ]);
      await expectLater(
        SourceFetcher(fileSystem: fs, processManager: pm, logger: logger)
            .resolve(SourceSpec.parse(fromGit: 'https://x/bar.git'), workDir: work),
        throwsA(isA<SourceFetchError>()
            .having((e) => e.message, 'm', contains('repository not found'))),
      );
    });

    test('pub resolves the package root from package_config.json', () async {
      final Directory work = fs.directory('/w')..createSync(recursive: true);
      final String probe = fs.path.join(work.path, '_pub_probe');
      // The directory pub "downloads" the package into.
      final Directory pkg = fs.directory(fs.path.join(work.path, 'cache_gadget_ios'))
        ..createSync(recursive: true);
      pkg.childFile('pubspec.yaml').writeAsStringSync('name: gadget_ios\n');
      // Real package_config rootUri is relative to the .dart_tool dir.
      final String rootUri =
          fs.path.relative(pkg.path, from: fs.path.join(probe, '.dart_tool'));

      final FakeProcessManager pm = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: const <String>['dart', 'pub', 'get'],
          onRun: (_) {
            final Directory dt = fs.directory(fs.path.join(probe, '.dart_tool'))
              ..createSync(recursive: true);
            dt.childFile('package_config.json').writeAsStringSync(
              '{"configVersion":2,"packages":[{"name":"gadget_ios",'
              '"rootUri":"$rootUri"}]}',
            );
          },
        ),
      ]);

      final Directory got = await SourceFetcher(
        fileSystem: fs,
        processManager: pm,
        logger: logger,
      ).resolve(SourceSpec.parse(fromPub: 'gadget_ios'), workDir: work);

      expect(fs.path.canonicalize(got.path), fs.path.canonicalize(pkg.path));
      expect(got.childFile('pubspec.yaml').existsSync(), isTrue);
      expect(pm, hasNoRemainingExpectations);
    });

    test('pub raises when the package is absent from package_config', () async {
      final Directory work = fs.directory('/w')..createSync(recursive: true);
      final String probe = fs.path.join(work.path, '_pub_probe');
      final FakeProcessManager pm = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: const <String>['dart', 'pub', 'get'],
          onRun: (_) {
            fs.directory(fs.path.join(probe, '.dart_tool')).createSync(recursive: true);
            fs
                .directory(fs.path.join(probe, '.dart_tool'))
                .childFile('package_config.json')
                .writeAsStringSync('{"configVersion":2,"packages":[]}');
          },
        ),
      ]);
      await expectLater(
        SourceFetcher(fileSystem: fs, processManager: pm, logger: logger)
            .resolve(SourceSpec.parse(fromPub: 'ghost_pkg'), workDir: work),
        throwsA(isA<SourceFetchError>()
            .having((e) => e.message, 'm', contains('not found in package_config'))),
      );
    });
  });
}
