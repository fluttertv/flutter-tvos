// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/signals.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/template.dart';
import 'package:flutter_tvos/commands/create.dart';
import 'package:package_config/package_config.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/test_flutter_command_runner.dart';

// NOTE: these tests spell the flag `--tvos-only`, never `--platforms=tvos`.
// Users type the latter; `expandTvosPlatformArgs` (executable.dart) rewrites it
// to the former before the arg parser sees it, because upstream's `--platforms`
// enum rejects `tvos`. `createTestCommandRunner` hands argv straight to the
// command and never runs that shim, so `--platforms=tvos` fails here with
// '"tvos" is not an allowed value for option "platforms"'.
void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    Cache.flutterRoot = '/flutter';
    fileSystem.directory('/flutter').createSync(recursive: true);
  });

  group('TvosCreateCommand project name', () {
    testUsingContext(
      'derives the name from the current directory for `create .`',
      () async {
        final Directory projectDir = fileSystem.directory('/home/my_tv_app')
          ..createSync(recursive: true);
        fileSystem.currentDirectory = projectDir;

        await createTestCommandRunner(
          TvosCreateCommand(verboseHelp: false),
        ).run(<String>['create', '--tvos-only', '--no-pub', '.']);

        expect(
          projectDir.childFile('pubspec.yaml').readAsStringSync(),
          contains('name: my_tv_app'),
        );
        expect(
          projectDir.childDirectory('lib').childFile('main.dart').readAsStringSync(),
          contains('MyTvAppApp'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'derives the name from the target directory basename',
      () async {
        await createTestCommandRunner(
          TvosCreateCommand(verboseHelp: false),
        ).run(<String>['create', '--tvos-only', '--no-pub', '/home/other_app']);

        expect(
          fileSystem.file('/home/other_app/pubspec.yaml').readAsStringSync(),
          contains('name: other_app'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      '--project-name still wins over the directory name',
      () async {
        await createTestCommandRunner(TvosCreateCommand(verboseHelp: false)).run(<String>[
          'create',
          '--tvos-only',
          '--no-pub',
          '--project-name=chosen_name',
          '/home/ignored_dir',
        ]);

        expect(
          fileSystem.file('/home/ignored_dir/pubspec.yaml').readAsStringSync(),
          contains('name: chosen_name'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'rejects a directory name that is not a valid Dart package name',
      () async {
        final Directory projectDir = fileSystem.directory('/home/my-tv-app')
          ..createSync(recursive: true);
        fileSystem.currentDirectory = projectDir;

        await expectLater(
          createTestCommandRunner(
            TvosCreateCommand(verboseHelp: false),
          ).run(<String>['create', '--tvos-only', '--no-pub', '.']),
          throwsToolExit(message: 'is not a valid Dart package name'),
        );
        expect(projectDir.childFile('pubspec.yaml').existsSync(), isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  // The `--tvos-only` tests above return before `super.runCommand()`. Without
  // that flag the command delegates to upstream `flutter create` first, and
  // upstream resolves the *Dart* package name itself — so pre-fix that path was
  // split-brain rather than uniformly broken: a correctly named Dart project
  // wrapping a `tvos/` runner named `.` (`CFBundleName = .`, and a bundle
  // identifier that collapsed to a bare `com.example`, shared by every project
  // created this way). This test pins the runner side of that.
  //
  // It needs the real template tree (`renderMerged` reads
  // `templates/template_manifest.json` from the Flutter root), which a
  // MemoryFileSystem does not have — hence the local file system and a temp
  // directory, running against the vendored `flutter/` checkout.
  //
  // The one piece of the SDK it must NOT depend on is
  // `flutter/packages/flutter_tools/.dart_tool/package_config.json`, which
  // upstream's `TemplatePathProvider.imageDirectory` reads to locate
  // `flutter_template_images`. That file only exists once the Flutter tool has
  // bootstrapped itself, which a developer checkout has done and a fresh CI
  // clone has not — so depending on it makes the test pass locally and fail in
  // CI. `_LocalPackageConfigTemplatePathProvider` below resolves the same
  // package from *our* `.dart_tool/package_config.json` instead, which
  // `dart pub get` always produces (the suite cannot run without it).
  group('TvosCreateCommand standard path', () {
    late LocalFileSystem localFileSystem;
    late Directory tempDir;
    late String originalCwd;

    setUp(() {
      localFileSystem = LocalFileSystem.test(signals: Signals.test());
      originalCwd = localFileSystem.currentDirectory.path;
      // Absolute, and resolved before the cwd moves below.
      Cache.flutterRoot = localFileSystem.path.join(originalCwd, 'flutter');
      tempDir = localFileSystem.systemTempDirectory.createTempSync('flutter_tvos_create_test.');
    });

    tearDown(() {
      // `LocalFileSystem.currentDirectory` is process-global; always put it back.
      localFileSystem.currentDirectory = originalCwd;
      tempDir.deleteSync(recursive: true);
    });

    testUsingContext(
      'names the tvOS runner after the directory for `create .`',
      () async {
        final Directory projectDir = tempDir.childDirectory('my_tv_app')..createSync();
        localFileSystem.currentDirectory = projectDir;

        await createTestCommandRunner(
          TvosCreateCommand(verboseHelp: false),
        ).run(<String>['create', '--no-pub', '--platforms=ios', '.']);

        // Upstream resolves this one correctly even without the fix.
        expect(
          projectDir.childFile('pubspec.yaml').readAsLinesSync().first,
          'name: my_tv_app',
        );

        // These two came from our `name` and were `.` before the fix.
        final Directory runner = projectDir.childDirectory('tvos');
        expect(
          runner.childDirectory('Runner').childFile('Info.plist').readAsStringSync(),
          contains('<string>my_tv_app</string>'),
        );
        expect(
          runner.childDirectory('Runner.xcodeproj').childFile('project.pbxproj').readAsStringSync(),
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.myTvApp;'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => localFileSystem,
        ProcessManager: () => processManager,
        TemplatePathProvider: () =>
            _LocalPackageConfigTemplatePathProvider(originalCwd),
      },
    );
  });
}

/// A [TemplatePathProvider] that resolves `flutter_template_images` from this
/// package's own `.dart_tool/package_config.json` rather than the Flutter
/// tool's, which is only present in a bootstrapped SDK checkout.
///
/// Everything else — including the template directories themselves — comes
/// from the real provider.
class _LocalPackageConfigTemplatePathProvider extends TemplatePathProvider {
  const _LocalPackageConfigTemplatePathProvider(this.packageRoot);

  /// Root of this package, i.e. the directory holding `.dart_tool/`.
  final String packageRoot;

  @override
  Future<Directory> imageDirectory(String? name, FileSystem fileSystem, Logger logger) async {
    final PackageConfig packageConfig = await loadPackageConfigWithLogging(
      fileSystem.file(
        fileSystem.path.join(packageRoot, '.dart_tool', 'package_config.json'),
      ),
      logger: logger,
    );
    final Uri? imagePackageLibDir = packageConfig['flutter_template_images']?.packageUriRoot;
    final Directory templateDirectory = fileSystem
        .directory(imagePackageLibDir)
        .parent
        .childDirectory('templates');
    return name == null ? templateDirectory : templateDirectory.childDirectory(name);
  }
}
