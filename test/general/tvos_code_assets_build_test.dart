// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Drives NativeTvosBundle.build, with Xcode replaced by a fake, for a build
// that has code assets: what reaches the app, and when the build stops.
//
// Whether a project's Xcode build embeds the code assets cannot be read
// reliably from project.pbxproj: an XML-format project file, an embed script
// kept in a file, a renamed phase or a second phase all embed them without
// the text showing it. So nothing stops before Xcode; the built app shows
// whether the Xcode build embedded them. If it did not, simulator and
// unsigned builds have them added after Xcode, and a signed device build
// stops, since adding them to an app Xcode has signed puts them outside its
// signature.

import 'dart:io' as io show Process, ProcessResult, ProcessSignal, ProcessStartMode, systemEncoding;
import 'dart:isolate' show Isolate;

import 'package:file/local.dart' as local;
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/build_targets/tvos_code_assets.dart';
import 'package:flutter_tvos/tvos_artifacts.dart';
import 'package:flutter_tvos/tvos_build_info.dart';
import 'package:flutter_tvos/tvos_embed_phase_migration.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';

late Directory _root;

const String _templatePath = 'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl';

/// The app template's project file as `flutter-tvos create` writes it: the
/// mustache sections that only add a team are dropped, the values filled in.
String _renderedTemplate() => _root
    .childFile(_templatePath)
    .readAsStringSync()
    .split('\n')
    .where((String line) => !RegExp(r'^\{\{[#/^]').hasMatch(line))
    .join('\n')
    .replaceAll(RegExp(r'\{\{[a-zA-Z]+\}\}'), 'com.example.app');

const String _currentScript = 'shellScript = "';
const String _codeAssetsInput = '\t\t\t\t"\$(PROJECT_DIR)/Flutter/native_assets",\n';

/// The template with its "Embed Flutter.framework" script replaced by
/// [script] (escaped as project.pbxproj stores it).
String _withEmbedScript(String script, {bool codeAssetsInput = true}) {
  final String template = _renderedTemplate();
  final current = '$_currentScript$currentEmbedFlutterFrameworkScript";';
  expect(template, contains(current));
  final String project = template.replaceFirst(current, '$_currentScript$script";');
  return codeAssetsInput ? project : project.replaceFirst(_codeAssetsInput, '');
}

/// The project file flutter-tvos 1.12.2 created: the template before code
/// assets, whose phase only embeds the engine.
String _from1122() =>
    _withEmbedScript(earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!, codeAssetsInput: false);

/// The 1.12.2 phase with a line of the user's own, so the migration leaves it
/// alone: a project whose Xcode build does not embed code assets.
String _edited1122() => _withEmbedScript('${earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!}echo mine\\n');

/// The template with the phase's script kept in a file of the project.
String _scriptInAFile() => _withEmbedScript(r'/bin/sh \"${PROJECT_DIR}/scripts/embed.sh\"\n');

/// The template with the phase renamed.
String _renamedPhase() => _renderedTemplate().replaceAll('Embed Flutter.framework', 'Embed Flutter and code assets');

/// An edited 1.12.2 phase for the engine, and a second phase of the Runner
/// target that embeds the code assets.
String _secondPhase() {
  const embedEntry = '\t\t\t\tAAF50000000000000000F00D /* Embed Flutter.framework */,\n';
  final String script = pbxprojEscapeScript(
    '#!/bin/sh\nDEST_FRAMEWORKS="\${CODESIGNING_FOLDER_PATH}/Frameworks"\n$kCodeAssetEmbedScript',
  );
  final phase =
      '\t\t1234567890ABCDEF12345678 /* Embed code assets */ = {\n'
      '\t\t\tisa = PBXShellScriptBuildPhase;\n'
      '\t\t\talwaysOutOfDate = 1;\n'
      '\t\t\tbuildActionMask = 2147483647;\n'
      '\t\t\tfiles = (\n\t\t\t);\n'
      '\t\t\tinputPaths = (\n\t\t\t);\n'
      '\t\t\tname = "Embed code assets";\n'
      '\t\t\toutputPaths = (\n\t\t\t);\n'
      '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
      '\t\t\tshellPath = /bin/sh;\n'
      '\t\t\tshellScript = "$script";\n'
      '\t\t};\n';
  final String project = _edited1122();
  expect(project, contains(embedEntry));
  return project
      .replaceFirst(embedEntry, '$embedEntry\t\t\t\t1234567890ABCDEF12345678 /* Embed code assets */,\n')
      .replaceFirst(
        '/* End PBXShellScriptBuildPhase section */',
        '$phase/* End PBXShellScriptBuildPhase section */',
      );
}

/// [pbxproj] converted to the XML property-list format, which Xcode reads as
/// well and tools such as the xcodeproj gem can write.
String _asXml(String pbxproj) {
  final Directory dir = const local.LocalFileSystem().systemTempDirectory.createTempSync('tvos_xml.');
  try {
    final File file = dir.childFile('project.pbxproj')..writeAsStringSync(pbxproj);
    final io.ProcessResult result = io.Process.runSync('plutil', <String>['-convert', 'xml1', file.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return file.readAsStringSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Answers every command with success and records it. `rsync`, `cp -R` and
/// `plutil -convert xml1 -o -` work on the file system the build uses;
/// `xcodebuild` runs [onXcodebuild], which stands in for what Xcode leaves
/// on disk.
class _RecordingProcessManager implements ProcessManager {
  _RecordingProcessManager(this._fileSystem, this.onXcodebuild);

  final FileSystem _fileSystem;
  final void Function(List<String> command) onXcodebuild;
  final List<List<String>> commands = <List<String>>[];

  io.ProcessResult _run(List<Object> command) {
    final args = <String>[for (final Object a in command) '$a'];
    commands.add(args);
    if (args.first == 'xcodebuild') {
      onXcodebuild(args);
    } else if (args.first == 'rsync') {
      // rsync -a [--delete] SOURCE DESTINATION/: a source ending in / copies
      // its contents, any other copies the directory itself.
      final String source = args[args.length - 2];
      final Directory destination = _fileSystem.directory(args.last);
      if (source.endsWith('/')) {
        copyDirectory(_fileSystem.directory(source), destination);
      } else {
        final Directory from = _fileSystem.directory(source);
        final Directory to = destination.childDirectory(from.basename);
        if (to.existsSync()) {
          to.deleteSync(recursive: true);
        }
        copyDirectory(from, to);
      }
    } else if (args.length == 4 && args[0] == 'cp' && args[1] == '-R') {
      final Directory source = _fileSystem.directory(args[2]);
      Directory destination = _fileSystem.directory(args[3]);
      if (destination.existsSync()) {
        destination = destination.childDirectory(source.basename);
      }
      copyDirectory(source, destination);
    } else if (args.first == '/usr/bin/plutil' && args.contains('xml1')) {
      return io.ProcessResult(0, 0, _fileSystem.file(args.last).readAsStringSync(), '');
    }
    return io.ProcessResult(0, 0, '', '');
  }

  @override
  Future<io.ProcessResult> run(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Object? stdoutEncoding = io.systemEncoding,
    Object? stderrEncoding = io.systemEncoding,
  }) async => _run(command);

  @override
  io.ProcessResult runSync(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Object? stdoutEncoding = io.systemEncoding,
    Object? stderrEncoding = io.systemEncoding,
  }) => _run(command);

  @override
  Future<io.Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) => throw UnimplementedError('start: $command');

  @override
  bool canRun(dynamic executable, {String? workingDirectory}) => true;

  @override
  bool killPid(int pid, [io.ProcessSignal signal = io.ProcessSignal.sigterm]) => false;
}

/// The AOT compile is not under test here (tvos_aot_compile_test.dart drives
/// it); this leaves the App.framework it would produce.
class _Bundle extends NativeTvosBundle {
  _Bundle(super.buildInfo, super.targetFile);

  @override
  Future<void> compileAotSnapshot(
    FlutterProject project,
    Directory tvosProjectDir,
    Environment environment,
  ) async {
    tvosProjectDir.childDirectory('Flutter').childDirectory('App.framework').childFile('App')
      ..createSync(recursive: true)
      ..writeAsStringSync('this build');
  }
}

void main() {
  setUpAll(() async {
    final Uri lib = (await Isolate.resolvePackageUri(Uri.parse('package:flutter_tvos/')))!;
    _root = const local.LocalFileSystem().directory(lib.toFilePath()).parent;
  });

  testWithoutContext('the 1.12.2 project file is the template before code assets', () {
    // The template gained exactly the code-asset lines of the phase and its
    // input path since 1.12.2, so the migration turns a 1.12.2 project into
    // a current one.
    expect(TvosEmbedPhaseMigration.migrateEmbedPhase(_from1122()), _renderedTemplate());
  });

  group('a build with code assets', () {
    late MemoryFileSystem fileSystem;
    late TvosArtifacts artifacts;
    late BufferLogger logger;
    late _RecordingProcessManager processManager;
    late Environment environment;

    /// Whether the fake Xcode build embeds the staged code assets, decided
    /// from the project file as it is when Xcode starts.
    late bool Function(String pbxproj) xcodeEmbeds;

    /// The frameworks the fake Xcode build embeds when [xcodeEmbeds]; every
    /// staged one when null.
    Set<String>? xcodeEmbedsOnly;

    /// The code-asset frameworks in the app when Xcode started, by name, with
    /// their binary's contents.
    Map<String, String>? inAppWhenXcodeStarted;

    const pbxprojPath = '/project/tvos/Runner.xcodeproj/project.pbxproj';
    const stagedPath = '/project/tvos/Flutter/native_assets';
    String frameworksPath({bool simulator = false}) =>
        '/project/build/tvos/Release-${simulator ? 'appletvsimulator' : 'appletvos'}/Runner.app/Frameworks';
    String inApp(String name, {bool simulator = false}) {
      final File binary = fileSystem
          .directory(frameworksPath(simulator: simulator))
          .childDirectory('$name.framework')
          .childFile(name);
      return binary.existsSync() ? binary.readAsStringSync() : '(missing)';
    }

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      logger = BufferLogger.test();
      inAppWhenXcodeStarted = null;
      xcodeEmbedsOnly = null;
      Cache.flutterRoot = '/flutter';
      artifacts = TvosArtifacts(
        fileSystem: fileSystem,
        cache: Cache.test(fileSystem: fileSystem, processManager: FakeProcessManager.any()),
        platform: FakePlatform(operatingSystem: 'macos'),
        operatingSystemUtils: FakeOperatingSystemUtils(),
      );
      processManager = _RecordingProcessManager(fileSystem, (List<String> command) {
        final Directory frameworks = fileSystem.directory(
          frameworksPath(simulator: command.contains('appletvsimulator')),
        );
        inAppWhenXcodeStarted = <String, String>{
          if (frameworks.existsSync())
            for (final Directory framework in frameworks.listSync().whereType<Directory>())
              if (!<String>{'Flutter.framework', 'App.framework'}.contains(framework.basename))
                framework.basename: framework
                    .childFile(framework.basename.replaceFirst('.framework', ''))
                    .readAsStringSync(),
        };
        frameworks.childDirectory('Flutter.framework').childFile('Flutter').createSync(recursive: true);
        copyDirectory(
          fileSystem.directory('/project/tvos/Flutter/App.framework'),
          frameworks.childDirectory('App.framework'),
        );
        if (!xcodeEmbeds(fileSystem.file(pbxprojPath).readAsStringSync())) {
          return;
        }
        for (final String framework in stagedCodeAssetFrameworks(fileSystem.directory(stagedPath))) {
          if (xcodeEmbedsOnly != null && !xcodeEmbedsOnly!.contains(framework)) {
            continue;
          }
          final String name = framework.replaceFirst('.framework', '');
          final Directory embedded = frameworks.childDirectory(framework);
          if (embedded.existsSync()) {
            embedded.deleteSync(recursive: true);
          }
          copyDirectory(fileSystem.directory(stagedPath).childDirectory(framework), embedded);
          final File binary = embedded.childFile(name);
          binary.writeAsStringSync('${binary.readAsStringSync()}, signed by Xcode');
        }
      });
      environment = Environment.test(
        fileSystem.directory('/project'),
        artifacts: artifacts,
        fileSystem: fileSystem,
        logger: logger,
        processManager: FakeProcessManager.any(),
      );
    });

    /// A project at /project with [pbxproj] as its project file, the engine
    /// artifacts, the assets the earlier build steps leave, and code assets
    /// [names] installed by the hooks.
    void seedProject(String pbxproj, {List<String> names = const <String>['foo']}) {
      fileSystem.file('/project/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: app\nversion: 1.0.0+1\n');
      fileSystem.file(pbxprojPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(pbxproj);
      fileSystem.directory('/project/tvos/Runner').createSync(recursive: true);
      fileSystem.file('/project/build/tvos/AssetManifest.bin').createSync(recursive: true);
      fileSystem.file('/usr/bin/plutil').createSync(recursive: true);
      for (final EnvironmentType type in EnvironmentType.values) {
        for (final artifact in <Artifact>[Artifact.flutterFramework, Artifact.flutterXcframework]) {
          fileSystem
              .directory(artifacts.getArtifactPath(artifact, mode: BuildMode.release, environmentType: type))
              .createSync(recursive: true);
        }
      }
      for (final name in names) {
        final Directory framework = environment.buildDir
            .childDirectory(TvosInstallCodeAssets.directoryName)
            .childDirectory('$name.framework');
        framework.childFile(name)
          ..createSync(recursive: true)
          ..writeAsStringSync('this build');
        framework.childFile('Info.plist').writeAsStringSync(
          codeAssetInfoPlist(
            name: name,
            bundleIdentifier: '$kCodeAssetBundleIdentifierPrefix$name',
            minimumOSVersion: '15.0',
            simulator: false,
          ),
        );
      }
      fileSystem.currentDirectory = fileSystem.directory('/project');
    }

    /// What an earlier build that embedded code assets after Xcode left in
    /// the app: [names], as that build's.
    void seedEarlierCopies(List<String> names, {bool simulator = false}) {
      for (final name in names) {
        final Directory framework = fileSystem.directory(frameworksPath(simulator: simulator)).childDirectory('$name.framework');
        framework.childFile(name)
          ..createSync(recursive: true)
          ..writeAsStringSync('an earlier build');
        framework.childFile('Info.plist').writeAsStringSync(
          codeAssetInfoPlist(
            name: name,
            bundleIdentifier: '$kCodeAssetBundleIdentifierPrefix$name',
            minimumOSVersion: '15.0',
            simulator: simulator,
          ),
        );
      }
    }

    Future<void> build({bool simulator = false, bool codesign = true}) {
      environment.buildDir.createSync(recursive: true);
      return _Bundle(
        TvosBuildInfo(
          const BuildInfo(
            BuildMode.release,
            null,
            treeShakeIcons: false,
            packageConfigPath: '.dart_tool/package_config.json',
          ),
          targetArch: 'arm64',
          simulator: simulator,
          codesign: codesign,
        ),
        'lib/main.dart',
      ).build(environment);
    }

    bool ranXcode() => processManager.commands.any((List<String> c) => c.first == 'xcodebuild');

    /// The commands run after Xcode that name a code-asset framework: a copy
    /// into the app, or a signature.
    List<List<String>> codeAssetCommandsAfterXcode() {
      final int xcode = processManager.commands.indexWhere((List<String> c) => c.first == 'xcodebuild');
      return <List<String>>[
        if (xcode >= 0)
          for (final List<String> c in processManager.commands.skip(xcode + 1))
            if (c.any((String a) => a.contains('foo.framework') || a.contains('bar.framework'))) c,
      ];
    }

    Map<Type, Generator> overrides() => <Type, Generator>{
      FileSystem: () => fileSystem,
      Artifacts: () => artifacts,
      Logger: () => logger,
      ProcessManager: () => processManager,
      PlistParser: () => PlistParser(fileSystem: fileSystem, processManager: processManager, logger: logger),
      Platform: () => FakePlatform(
        operatingSystem: 'macos',
        environment: <String, String>{
          'DEVELOPMENT_TEAM': 'ABC1234567',
          'TVOS_ENGINE_SKIP_SIGNING': '1',
        },
      ),
    };

    // Projects whose Xcode build embeds the code assets. Only the first has
    // an "Embed Flutter.framework" phase whose text names them; 1.12.2 built
    // all of them, and the Xcode build of each embeds what was staged.
    final projects = <String, String Function()>{
      'the current template': _renderedTemplate,
      'the current template in XML format': () => _asXml(_renderedTemplate()),
      'the current template with the embed script kept in a file': _scriptInAFile,
      'the current template with the phase renamed': _renamedPhase,
      'a project embedding them in a second phase': _secondPhase,
    };
    for (final MapEntry<String, String Function()> project in projects.entries) {
      testUsingContext(
        'a signed device build of ${project.key} runs Xcode and keeps what it embedded',
        () async {
          seedProject(project.value(), names: <String>['bar', 'foo']);
          xcodeEmbeds = (_) => true;

          await build();

          expect(ranXcode(), isTrue);
          expect(inApp('foo'), 'this build, signed by Xcode');
          expect(inApp('bar'), 'this build, signed by Xcode');
          expect(codeAssetCommandsAfterXcode(), isEmpty, reason: 'nothing changes the app after Xcode');
          expect(logger.warningText, isNot(contains('foo.framework')));
          expect(fileSystem.file(pbxprojPath).readAsStringSync(), project.value(), reason: 'the project is not rewritten');
        },
        overrides: overrides(),
      );
    }

    testUsingContext(
      'a signed device build of a project from 1.12.2 updates the phase before Xcode runs',
      () async {
        seedProject(_from1122());
        xcodeEmbeds = (String pbxproj) => pbxproj.contains(pbxprojEscapeScript(kCodeAssetEmbedScript));

        await build();

        expect(fileSystem.file(pbxprojPath).readAsStringSync(), _renderedTemplate());
        expect(logger.statusText, contains('Updated the "Embed Flutter.framework" build phase'));
        expect(inApp('foo'), 'this build, signed by Xcode');
        expect(codeAssetCommandsAfterXcode(), isEmpty);
      },
      overrides: overrides(),
    );

    testUsingContext(
      'removes code assets an earlier build added, before Xcode runs, for a project it does not see embedding them',
      () async {
        seedProject(_scriptInAFile());
        // foo is staged again, gone is not: an earlier copy of either would
        // otherwise be sealed into the app or pass for this build's.
        seedEarlierCopies(<String>['foo', 'gone']);
        xcodeEmbeds = (_) => true;

        await build();

        expect(inAppWhenXcodeStarted, isEmpty);
        expect(inApp('foo'), 'this build, signed by Xcode');
        expect(inApp('gone'), '(missing)');
      },
      overrides: overrides(),
    );

    testUsingContext(
      'a signed device build whose Xcode build left the code assets out stops after Xcode',
      () async {
        seedProject(_edited1122(), names: <String>['bar', 'foo']);
        seedEarlierCopies(<String>['foo']);
        xcodeEmbeds = (_) => false;

        await expectLater(
          build(),
          throwsToolExit(message: 'The Xcode build did not embed bar.framework, foo.framework, code assets'),
        );

        expect(ranXcode(), isTrue, reason: 'it stops after Xcode, not before');
        expect(inAppWhenXcodeStarted, isEmpty, reason: "an earlier build's copy does not pass for this one's");
        expect(codeAssetCommandsAfterXcode(), isEmpty, reason: 'nothing is copied into or signed in an app Xcode signed');
        expect(inApp('foo'), '(missing)');
        expect(inApp('bar'), '(missing)');
        expect(fileSystem.file(pbxprojPath).readAsStringSync(), _edited1122(), reason: 'an edited phase is left alone');
      },
      overrides: overrides(),
    );

    testUsingContext(
      'the stop after Xcode prints the lines to add to the phase',
      () async {
        seedProject(_edited1122());
        xcodeEmbeds = (_) => false;

        ToolExit? error;
        try {
          await build();
        } on ToolExit catch (e) {
          error = e;
        }

        expect(error?.message, contains(kCodeAssetEmbedScript));
        expect(error?.message, contains('"Embed Flutter.framework" Run Script phase'));
      },
      overrides: overrides(),
    );

    testUsingContext(
      'a signed device build stops after Xcode when Xcode embedded only some of them',
      () async {
        // A phase whose text names the staging directory, as the tool looks
        // for, but which was edited to embed a list of its own that lacks
        // bar. Only the built app shows it.
        final String project = _withEmbedScript('$currentEmbedFlutterFrameworkScript# edited\\n');
        expect(pbxprojEmbedsCodeAssets(project), isTrue);
        seedProject(project, names: <String>['bar', 'foo']);
        xcodeEmbeds = (_) => true;
        xcodeEmbedsOnly = <String>{'foo.framework'};

        await expectLater(
          build(),
          throwsToolExit(message: 'The Xcode build did not embed bar.framework, code assets'),
        );
        expect(inApp('foo'), 'this build, signed by Xcode');
        expect(inApp('bar'), '(missing)');
        expect(codeAssetCommandsAfterXcode(), isEmpty);
      },
      overrides: overrides(),
    );

    for (final (bool simulator, bool codesign) in <(bool, bool)>[(false, false), (true, true)]) {
      final kind = simulator ? 'a simulator' : 'an unsigned device';
      testUsingContext(
        '$kind build whose Xcode build left the code assets out embeds them after Xcode, unsigned',
        () async {
          seedProject(_edited1122());
          seedEarlierCopies(<String>['foo', 'gone'], simulator: simulator);
          xcodeEmbeds = (_) => false;

          await build(simulator: simulator, codesign: codesign);

          expect(inAppWhenXcodeStarted, isEmpty);
          expect(inApp('foo', simulator: simulator), 'this build');
          expect(inApp('gone', simulator: simulator), '(missing)');
          expect(codeAssetCommandsAfterXcode(), hasLength(1));
          expect(codeAssetCommandsAfterXcode().single.first, 'rsync');
          expect(logger.warningText, contains('foo.framework'));
          expect(logger.warningText, contains(kCodeAssetEmbedScript));
        },
        overrides: overrides(),
      );

      testUsingContext(
        '$kind build keeps what Xcode embedded, for a project it does not see embedding them',
        () async {
          seedProject(_scriptInAFile());
          xcodeEmbeds = (_) => true;

          await build(simulator: simulator, codesign: codesign);

          expect(inApp('foo', simulator: simulator), 'this build, signed by Xcode');
          expect(codeAssetCommandsAfterXcode(), isEmpty);
          expect(logger.warningText, isNot(contains('foo.framework')));
        },
        overrides: overrides(),
      );
    }

    testUsingContext(
      'a build without code assets is not affected by a project that does not embed them',
      () async {
        seedProject(_edited1122(), names: const <String>[]);
        xcodeEmbeds = (_) => false;

        await build();

        expect(ranXcode(), isTrue);
        expect(fileSystem.directory(stagedPath).existsSync(), isFalse);
        expect(codeAssetCommandsAfterXcode(), isEmpty);
      },
      overrides: overrides(),
    );
  });
}
