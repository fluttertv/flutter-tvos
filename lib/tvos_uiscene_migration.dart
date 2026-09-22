// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/project_migrator.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:meta/meta.dart';

/// Moves a tvOS app onto the UIScene lifecycle, and repairs one that was
/// moved by hand.
///
/// The tvOS counterpart of upstream's `UISceneMigration`, which never sees a
/// tvOS project: flutter-tvos drives its own build, and its runner never
/// matched the iOS templates that migration recognises.
///
/// Two things differ from the iOS runner, and both matter here:
///
///  * `Main.storyboard` named `FlutterViewController` with
///    `customModule="Flutter"`. That makes Interface Builder encode it as a
///    Swift class (`_TtC6Runner21FlutterViewController`), and
///    `FlutterViewController` is Objective-C, so UIKit logs "Unknown class"
///    and puts a plain `UIViewController` there instead. The old runner never
///    noticed: its `AppDelegate` built the window and the view controller in
///    code, replacing whatever the storyboard produced. Under the UIScene
///    lifecycle the scene builds its window from that storyboard alone, so
///    the app starts with no Flutter view and no engine — no Dart output, no
///    VM service (fluttertv/flutter-tvos#87).
///  * That `AppDelegate` window is never shown once scenes are on, and
///    plugins registered against it do not reach the scene's Flutter view.
///
/// So, on every build:
///
///  * On scenes already: fix the storyboard, and warn if the `AppDelegate`
///    still builds its own view controller.
///  * Not on scenes, with the `AppDelegate` flutter-tvos generated, unchanged:
///    migrate it — the new `AppDelegate`, the scene manifest and the
///    storyboard — as upstream does for an unchanged iOS app.
///  * Not on scenes, with an `AppDelegate` the developer has changed: touch
///    nothing and say how to migrate. The storyboard is deliberately left
///    alone there: fixed, it would make UIKit build a second, throwaway
///    `FlutterViewController` and engine behind the one the `AppDelegate`
///    creates.
///
/// Why it is not optional: built with Xcode 27, an app without the UIScene
/// lifecycle does not launch on tvOS 27 at all — UIKit stops it with "UIScene
/// life cycle is required for apps built with this SDK". tvOS 26 and earlier
/// still run it.
///
/// Off when upstream's own switch is off (`enable-uiscene-migration`).
class TvosUISceneMigration extends ProjectMigrator {
  TvosUISceneMigration(
    this._runnerDirectory,
    super.logger, {
    required bool isMigrationFeatureEnabled,
    required PlistParser plistParser,
  }) : _isMigrationFeatureEnabled = isMigrationFeatureEnabled,
       _plistParser = plistParser;

  final Directory _runnerDirectory;
  final bool _isMigrationFeatureEnabled;
  final PlistParser _plistParser;

  File get _infoPlist => _runnerDirectory.childFile('Info.plist');
  File get _appDelegate => _runnerDirectory.childFile('AppDelegate.swift');
  File get _mainStoryboard =>
      _runnerDirectory.childDirectory('Base.lproj').childFile('Main.storyboard');

  static const _guide = 'https://flutter.dev/to/uiscene-migration';

  /// The only `AppDelegate.swift` the tvOS app template has ever generated.
  @visibleForTesting
  static const originalAppDelegate = '''
import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
''';

  /// Upstream's migrated `AppDelegate`: the scene's storyboard supplies the
  /// view controller, and plugins register on the engine it creates.
  @visibleForTesting
  static const migratedAppDelegate = '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
''';

  /// The manifest upstream inserts. `FlutterSceneDelegate` is the engine's own
  /// class, so a migrated project needs no new source file in its Xcode
  /// project.
  static const _sceneManifestJson = '''
{
  "UIApplicationSupportsMultipleScenes": false,
  "UISceneConfigurations": {
    "UIWindowSceneSessionRoleApplication": [{
      "UISceneClassName": "UIWindowScene",
      "UISceneDelegateClassName": "FlutterSceneDelegate",
      "UISceneConfigurationName": "flutter",
      "UISceneStoryboardFile": "Main"
    }]
  }
}''';

  static String _sceneManifestXml(String indent) {
    const lines = <String>[
      '<key>UIApplicationSceneManifest</key>',
      '<dict>',
      '  <key>UIApplicationSupportsMultipleScenes</key>',
      '  <false/>',
      '  <key>UISceneConfigurations</key>',
      '  <dict>',
      '    <key>UIWindowSceneSessionRoleApplication</key>',
      '    <array>',
      '      <dict>',
      '        <key>UISceneClassName</key>',
      '        <string>UIWindowScene</string>',
      '        <key>UISceneConfigurationName</key>',
      '        <string>flutter</string>',
      '        <key>UISceneDelegateClassName</key>',
      '        <string>FlutterSceneDelegate</string>',
      '        <key>UISceneStoryboardFile</key>',
      '        <string>Main</string>',
      '      </dict>',
      '    </array>',
      '  </dict>',
      '</dict>',
    ];
    return lines.map((String line) => '$indent$line\n').join();
  }

  @override
  Future<void> migrate() async {
    if (!_isMigrationFeatureEnabled || !_infoPlist.existsSync()) {
      return;
    }

    // Null for a binary plist, which `defaults write` leaves behind: it is not
    // UTF-8 text, and only plutil can read or edit it. xcodebuild takes either,
    // so a build must not fail here over one.
    final String? plistText = _readText(_infoPlist);
    final bool onScenes = plistText != null
        ? plistText.contains('UIApplicationSceneManifest')
        : _plistParser.getValueFromFile<Object>(_infoPlist.path, 'UIApplicationSceneManifest') !=
              null;
    if (onScenes) {
      _repairStoryboards();
      _warnIfAppDelegateBuildsItsOwnWindow();
      return;
    }

    String? notMigrated = _whyNotMigratedAutomatically();
    if (notMigrated == null) {
      final List<int> originalPlist = _infoPlist.readAsBytesSync();
      if (_insertSceneManifest(plistText)) {
        _appDelegate.writeAsStringSync(migratedAppDelegate);
        // Part of the migration, not a separate repair: its own message would
        // describe a failed launch this project never had.
        _repairStoryboard(_mainStoryboard, quiet: true);
        logger.printStatus('Finished migration to UIScene lifecycle. See $_guide for details.');
        return;
      }
      _infoPlist.writeAsBytesSync(originalPlist);
      notMigrated = 'tvos/Runner/Info.plist could not be edited';
    }

    // An error, as upstream prints it for iOS, and not a failed build: the app
    // still runs on tvOS 26 and earlier, and built with Xcode 26 it runs
    // everywhere. Only the combination below refuses to start.
    final message = StringBuffer(
      'This tvOS app does not use the UIScene lifecycle. Built with Xcode 27, it will not launch on '
      'tvOS 27: tvOS stops it with "UIScene life cycle is required for apps built with this SDK".\n'
      'flutter-tvos could not migrate it automatically: $notMigrated. Migrate by hand: $_guide',
    );
    if (_appDelegateBuildsItsOwnWindow()) {
      message.write(
        '\nIn tvos/Runner/AppDelegate.swift, also remove the window and FlutterViewController the '
        'tvOS template created: with scenes, the view controller comes from Main.storyboard.',
      );
    }
    logger.printError(message.toString());
  }

  /// Null when the project is as the tvOS template generated it, and so can be
  /// migrated automatically; otherwise what stops that, for the error.
  String? _whyNotMigratedAutomatically() {
    if (!_appDelegate.existsSync()) {
      return 'tvos/Runner/AppDelegate.swift does not exist';
    }
    if (!_mainStoryboard.existsSync()) {
      return 'tvos/Runner/Base.lproj/Main.storyboard does not exist';
    }
    if (_normalized(_appDelegate.readAsStringSync()) != _normalized(originalAppDelegate)) {
      return 'tvos/Runner/AppDelegate.swift has been changed from the one flutter-tvos generated';
    }
    final String? storyboardName = _plistParser.getValueFromFile<String>(
      _infoPlist.path,
      'UIMainStoryboardFile',
    );
    if (storyboardName != 'Main') {
      return 'tvos/Runner/Info.plist does not name Main as its UIMainStoryboardFile';
    }
    return null;
  }

  /// [file] as text, or null when it is not UTF-8.
  static String? _readText(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Whitespace-insensitive, so a template reindented or saved with CRLF line
  /// endings still counts as unchanged. Anything else does not.
  static String _normalized(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Inserts the manifest as text, next to `UIMainStoryboardFile`, which keeps
  /// the file's comments and layout — the tvOS template documents
  /// `FLTAssetsPath` in one, and `plutil -insert` rewrites the file without
  /// them. The result is read back through `plutil`, and a file it cannot
  /// read, or one that is not text ([plistText] null), falls back to
  /// upstream's `plutil -insert`.
  bool _insertSceneManifest(String? plistText) {
    final Match? anchor = plistText == null
        ? null
        : RegExp(r'^([ \t]*)<key>UIMainStoryboardFile</key>', multiLine: true).firstMatch(plistText);
    if (anchor != null) {
      _infoPlist.writeAsStringSync(
        plistText!.replaceRange(anchor.start, anchor.start, _sceneManifestXml(anchor.group(1)!)),
      );
      if (_plistParser.getValueFromFile<Object>(_infoPlist.path, 'UIApplicationSceneManifest') !=
          null) {
        return true;
      }
      _infoPlist.writeAsStringSync(plistText);
    }
    return _plistParser.insertKeyWithJson(
      _infoPlist.path,
      key: 'UIApplicationSceneManifest',
      json: _sceneManifestJson,
    );
  }

  void _repairStoryboards() {
    if (!_runnerDirectory.existsSync()) {
      return;
    }
    for (final FileSystemEntity entity in _runnerDirectory.listSync(recursive: true)) {
      if (entity is File && entity.basename.endsWith('.storyboard')) {
        _repairStoryboard(entity);
      }
    }
  }

  /// Drops `customModule` and `customModuleProvider` from any element whose
  /// class is `FlutterViewController`, leaving every other element as it was.
  void _repairStoryboard(File storyboard, {bool quiet = false}) {
    if (!storyboard.existsSync()) {
      return;
    }
    final String original = storyboard.readAsStringSync();
    final String repaired = original.replaceAllMapped(
      RegExp(r'<[A-Za-z]+\b[^>]*\bcustomClass="FlutterViewController"[^>]*>'),
      (Match element) =>
          element[0]!.replaceAll(RegExp(r'\s+customModule(?:Provider)?="[^"]*"'), ''),
    );
    if (repaired == original) {
      return;
    }
    storyboard.writeAsStringSync(repaired);
    if (quiet) {
      return;
    }
    logger.printStatus(
      'Fixed ${storyboard.parent.basename}/${storyboard.basename}: it referred to '
      'FlutterViewController as a Swift class, which UIKit cannot find, so the scene started '
      'without a Flutter view.',
    );
  }

  bool _appDelegateBuildsItsOwnWindow() =>
      _appDelegate.existsSync() && _appDelegate.readAsStringSync().contains('FlutterViewController(');

  void _warnIfAppDelegateBuildsItsOwnWindow() {
    if (!_appDelegateBuildsItsOwnWindow()) {
      return;
    }
    logger.printWarning(
      'tvos/Runner/AppDelegate.swift creates its own FlutterViewController. With the UIScene '
      'lifecycle its window is never shown, and plugins registered against it do not reach the '
      "scene's Flutter view. Remove it and register plugins in "
      'didInitializeImplicitFlutterEngine; see $_guide',
    );
  }
}
