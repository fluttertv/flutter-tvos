// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/error_handling_io.dart';
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
/// So, on every build, with upstream's `enable-uiscene-migration` on:
///
///  * On scenes already: fix the storyboards the scene manifest names, and
///    finish the job when the `AppDelegate` is still the template's.
///  * Not on scenes, with the runner flutter-tvos generated, unchanged:
///    migrate it — the new `AppDelegate`, the scene manifest and the
///    storyboard — as upstream does for an unchanged iOS app.
///  * Not on scenes otherwise: touch nothing and say why and how to migrate.
///    The storyboard is deliberately left alone there: fixed, it would make
///    UIKit build a second, throwaway `FlutterViewController` and engine
///    behind the one the `AppDelegate` creates.
///
/// With the setting off it edits nothing, and only says what keeps an app
/// already on scenes from starting.
///
/// It edits people's projects unasked, so it stays narrow: only the scene's
/// storyboards, only a `FlutterViewController` in the `Flutter` module, never
/// through a link out of the project, and a file it cannot write is reported
/// rather than failing the build.
///
/// Why it is not optional: built with Xcode 27, an app without the UIScene
/// lifecycle does not launch on tvOS 27 at all — UIKit stops it with "UIScene
/// life cycle is required for apps built with this SDK". tvOS 26 and earlier
/// still run it.
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

  static String _sceneManifestXml(String indent, String newline) {
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
    return lines.map((String line) => '$indent$line$newline').join();
  }

  @override
  Future<void> migrate() async {
    if (!_infoPlist.existsSync()) {
      // As upstream does for iOS: with no Info.plist where the template put
      // it, there is no telling whether the app is on scenes.
      if (_isMigrationFeatureEnabled) {
        logger.printError(
          'flutter-tvos could not find tvos/Runner/Info.plist, so it cannot tell whether this '
          'tvOS app uses the UIScene lifecycle. Built with Xcode 27, an app without it will not '
          'launch on tvOS 27. See $_guide\n'
          'See $_guide/#hide-migration-warning for instructions to hide this warning.',
        );
      }
      return;
    }

    final List<String>? sceneStoryboards = _sceneStoryboardNames();
    if (sceneStoryboards != null) {
      _onScenes(sceneStoryboards);
      return;
    }
    if (_isMigrationFeatureEnabled) {
      _migrate();
    }
  }

  /// A project on scenes: its storyboards and its `AppDelegate`.
  void _onScenes(List<String> storyboardNames) {
    final broken = <File>[
      for (final String name in storyboardNames)
        ..._storyboardsNamed(
          name,
        ).where((File storyboard) => _namesFlutterModule(storyboard.readAsStringSync())),
    ];
    if (!_isMigrationFeatureEnabled) {
      // Upstream's switch: edit nothing, but say what keeps the app from
      // starting rather than leave #87 to be found on a device.
      for (final storyboard in broken) {
        logger.printWarning(
          '${_described(storyboard)} names FlutterViewController as a Swift class in the '
          'Flutter module, which UIKit cannot find, so the scene starts with no Flutter view. '
          'Remove customModule="Flutter" and customModuleProvider from it, or turn '
          'enable-uiscene-migration on to have flutter-tvos fix it.',
        );
      }
      _warnIfAppDelegateBuildsItsOwnWindow();
      return;
    }
    broken.forEach(_repairStoryboard);
    // Moved onto scenes by hand with the template's AppDelegate left as it
    // was: its window is never shown, and the plugins it registers never
    // reach the scene's engine. It is the one flutter-tvos generated, so
    // finish the job, as the migration would have, but only when the scene
    // shows a Flutter view without it: every storyboard the manifest names
    // opens on a FlutterViewController. Otherwise that window may be all the
    // app has.
    final sceneStoryboards = <File>[
      for (final String name in storyboardNames) ..._storyboardsNamed(name),
    ];
    if (_appDelegateIsTemplate() &&
        sceneStoryboards.isNotEmpty &&
        sceneStoryboards.every(
          (File storyboard) => _opensOnFlutterViewController(storyboard.readAsStringSync()),
        )) {
      if (_tryWrite(_appDelegate, migratedAppDelegate)) {
        logger.printStatus(
          'Finished migration to UIScene lifecycle: tvos/Runner/AppDelegate.swift still built '
          'its own window. See $_guide for details.',
        );
      } else {
        logger.printError(
          'Could not write tvos/Runner/AppDelegate.swift. Its window is never shown under the '
          "UIScene lifecycle, and the plugins it registers do not reach the scene's Flutter "
          'view. Replace it as $_guide describes.',
        );
      }
      return;
    }
    _warnIfAppDelegateBuildsItsOwnWindow();
  }

  /// A project not on scenes, with the setting on.
  void _migrate() {
    String? notMigrated = _whyNotMigratedAutomatically();
    if (notMigrated == null) {
      final List<int> originalPlist = _infoPlist.readAsBytesSync();
      notMigrated = _insertSceneManifest();
      if (notMigrated == null) {
        if (_tryWrite(_appDelegate, migratedAppDelegate)) {
          // Part of the migration, not a separate repair: its own message
          // would describe a failed launch this project never had.
          for (final File storyboard in _storyboardsNamed('Main')) {
            _repairStoryboard(storyboard, quiet: true);
          }
          logger.printStatus('Finished migration to UIScene lifecycle. See $_guide for details.');
          return;
        }
        // Half a migration launches nowhere new: put the manifest back out.
        _tryWriteBytes(_infoPlist, originalPlist);
        notMigrated = 'tvos/Runner/AppDelegate.swift could not be written';
      }
    }

    // An error, as upstream prints it for iOS, and not a failed build: the app
    // still runs on tvOS 26 and earlier, and UIKit's message puts the
    // requirement on apps built with the tvOS 27 SDK.
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
    if (!_appDelegateIsTemplate()) {
      return 'tvos/Runner/AppDelegate.swift has been changed from the one flutter-tvos generated';
    }
    if (_mainStoryboardName() != 'Main') {
      return 'tvos/Runner/Info.plist does not name Main as its UIMainStoryboardFile';
    }
    final List<File> storyboards = _storyboardsNamed('Main');
    if (storyboards.isEmpty) {
      return 'tvos/Runner has no Main.storyboard';
    }
    // Before scenes tvOS never showed this storyboard, since the AppDelegate
    // replaced its window, so it can have drifted from the template unnoticed.
    // A scene shows it: one that does not open on a FlutterViewController
    // starts with no Flutter view.
    for (final storyboard in storyboards) {
      if (!_opensOnFlutterViewController(storyboard.readAsStringSync())) {
        return '${_described(storyboard)} does not open on a FlutterViewController';
      }
    }
    return null;
  }

  /// The storyboards the scene manifest names, or null when Info.plist has no
  /// manifest and the app is not on scenes.
  ///
  /// A text plist is read as text, as upstream reads it, with its comments and
  /// CDATA masked, since UIKit never reads either as keys. Only a binary one
  /// goes through plutil: plutil cannot parse a plist Xcode preprocesses, and
  /// every call on one prints its errors, on every build.
  List<String>? _sceneStoryboardNames() {
    final String? text = _readText(_infoPlist);
    if (text == null) {
      final Object? manifest = _plistParser.getValueFromFile<Object>(
        _infoPlist.path,
        'UIApplicationSceneManifest',
      );
      return manifest == null ? null : _storyboardNamesIn(manifest);
    }
    final String masked = _masked(text);
    if (_topLevelKey(masked, 'UIApplicationSceneManifest') == null) {
      return null;
    }
    return <String>[
      for (final Match name in RegExp(
        r'<key>UISceneStoryboardFile</key>\s*<string>([^<]*)</string>',
      ).allMatches(masked))
        name[1]!.trim(),
    ];
  }

  static List<String> _storyboardNamesIn(Object? value) => <String>[
    if (value is Map)
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key == 'UISceneStoryboardFile' && entry.value is String)
          entry.value! as String
        else
          ..._storyboardNamesIn(entry.value),
    if (value is List)
      for (final Object? item in value) ..._storyboardNamesIn(item),
  ];

  /// Info.plist's `UIMainStoryboardFile`, read as [_sceneStoryboardNames] reads
  /// the manifest.
  String? _mainStoryboardName() {
    final String? text = _readText(_infoPlist);
    if (text == null) {
      return _plistParser.getValueFromFile<String>(_infoPlist.path, 'UIMainStoryboardFile');
    }
    final String masked = _masked(text);
    final int? key = _topLevelKey(masked, 'UIMainStoryboardFile');
    if (key == null) {
      return null;
    }
    return RegExp(
      r'<key>UIMainStoryboardFile</key>\s*<string>([^<]*)</string>',
    ).matchAsPrefix(masked, key)?.group(1)?.trim();
  }

  /// `<name>.storyboard` wherever the runner can hold it: directly, in
  /// Base.lproj, or in a localized .lproj. Never through a link, which can
  /// lead out of the project.
  List<File> _storyboardsNamed(String name) {
    // No existence check: the runner holds the Info.plist that got us here.
    final List<Directory> localizations =
        _runnerDirectory
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((Directory directory) => directory.basename.endsWith('.lproj'))
            .toList()
          ..sort((Directory a, Directory b) {
            // Base.lproj first: it is what Interface Builder edits.
            if (a.basename == 'Base.lproj') {
              return -1;
            }
            if (b.basename == 'Base.lproj') {
              return 1;
            }
            return a.basename.compareTo(b.basename);
          });
    return <File>[
      for (final File candidate in <File>[
        _runnerDirectory.childFile('$name.storyboard'),
        for (final Directory localization in localizations)
          localization.childFile('$name.storyboard'),
      ])
        if (candidate.fileSystem.isFileSync(candidate.path) &&
            !candidate.fileSystem.isLinkSync(candidate.path))
          candidate,
    ];
  }

  bool _appDelegateIsTemplate() =>
      _appDelegate.existsSync() &&
      _normalized(_appDelegate.readAsStringSync()) == _normalized(originalAppDelegate);

  /// The opening tag of an element whose class is `FlutterViewController`,
  /// with its attributes in any order and across lines.
  static final _flutterViewControllerTag = RegExp(
    r'<[A-Za-z]+\b[^>]*\bcustomClass="FlutterViewController"[^>]*>',
  );

  static final _flutterModule = RegExp(r'\bcustomModule="Flutter"');

  /// Whether [storyboard] names `FlutterViewController` in the `Flutter`
  /// module: #87's defect. A `FlutterViewController` in any other module is
  /// the app's own Swift class, and correct as it is.
  static bool _namesFlutterModule(String storyboard) => _flutterViewControllerTag
      .allMatches(storyboard)
      .any((Match tag) => _flutterModule.hasMatch(tag[0]!));

  /// Whether [storyboard]'s initial view controller is a `FlutterViewController`.
  static bool _opensOnFlutterViewController(String storyboard) {
    final String? initial = RegExp(
      r'<document\b[^>]*\binitialViewController="([^"]*)"',
    ).firstMatch(storyboard)?.group(1);
    if (initial == null) {
      return false;
    }
    final id = RegExp('\\sid="${RegExp.escape(initial)}"');
    return _flutterViewControllerTag
        .allMatches(storyboard)
        .any((Match tag) => id.hasMatch(tag[0]!));
  }

  /// [file] as text, or null when it is not UTF-8: a binary plist, which
  /// `defaults write` leaves behind.
  static String? _readText(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// [text] with its comments and CDATA blanked out, character for character,
  /// so an offset in the result is the same offset in [text].
  static String _masked(String text) => text.replaceAllMapped(
    RegExp(r'<!--.*?-->|<!\[CDATA\[.*?\]\]>', dotAll: true),
    (Match hidden) => hidden[0]!.replaceAll(RegExp(r'[^\r\n]'), ' '),
  );

  static final _conditionalStart = RegExp(r'^[ \t]*#[ \t]*if(?:n?def)?\b', multiLine: true);
  static final _conditionalEnd = RegExp(r'^[ \t]*#[ \t]*endif\b', multiLine: true);
  static final _directive = RegExp(r'^[ \t]*#[ \t]*[a-z]+\b', multiLine: true);

  /// The offset of `<key>[key]</key>` in the plist's root dictionary, in
  /// [masked] text, or null. With [outsideConditionals], also outside any
  /// preprocessor `#if` block.
  static int? _topLevelKey(String masked, String key, {bool outsideConditionals = false}) {
    for (final Match match in RegExp('<key>${RegExp.escape(key)}</key>').allMatches(masked)) {
      final String before = masked.substring(0, match.start);
      final int depth =
          RegExp(r'<dict\s*>').allMatches(before).length -
          RegExp(r'</dict\s*>').allMatches(before).length;
      if (depth != 1) {
        continue;
      }
      if (outsideConditionals &&
          _conditionalStart.allMatches(before).length !=
              _conditionalEnd.allMatches(before).length) {
        continue;
      }
      return match.start;
    }
    return null;
  }

  /// Whitespace-insensitive, so a template reindented or saved with CRLF line
  /// endings still counts as unchanged. Anything else does not.
  static String _normalized(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Inserts the manifest as text, before the root dictionary's
  /// `UIMainStoryboardFile`, which keeps the file's comments and layout — the
  /// tvOS template documents `FLTAssetsPath` in one, and `plutil -insert`
  /// rewrites the file without them. Null when the manifest is in; otherwise
  /// why not.
  ///
  /// The result is read back through plutil, and one plutil cannot read falls
  /// back to upstream's `plutil -insert`. A preprocessed plist is the
  /// exception: plutil cannot parse it at all, so the insertion stands on its
  /// own — in the root dictionary, outside comments and `#if` blocks.
  String? _insertSceneManifest() {
    final String? text = _readText(_infoPlist);
    if (text == null) {
      return _plutilInsert();
    }
    final String masked = _masked(text);
    final bool preprocessed = _directive.hasMatch(masked);
    final int? key = _topLevelKey(
      masked,
      'UIMainStoryboardFile',
      outsideConditionals: preprocessed,
    );
    final int lineStart = key == null ? 0 : text.lastIndexOf('\n', key - 1) + 1;
    final String indent = key == null ? '' : text.substring(lineStart, key);
    if (key == null || indent.trim().isNotEmpty) {
      // No line of its own to insert before: all on one line, or none at all.
      if (preprocessed) {
        return 'tvos/Runner/Info.plist is preprocessed, and plutil cannot edit it';
      }
      return _plutilInsert();
    }
    final newline = text.contains('\r\n') ? '\r\n' : '\n';
    final String inserted = text.replaceRange(
      lineStart,
      lineStart,
      _sceneManifestXml(indent, newline),
    );
    if (!_tryWrite(_infoPlist, inserted)) {
      return 'tvos/Runner/Info.plist could not be written';
    }
    if (preprocessed) {
      return null;
    }
    if (_plistParser.getValueFromFile<Object>(_infoPlist.path, 'UIApplicationSceneManifest') !=
        null) {
      return null;
    }
    if (!_tryWrite(_infoPlist, text)) {
      return 'tvos/Runner/Info.plist could not be written';
    }
    return _plutilInsert();
  }

  String? _plutilInsert() =>
      _plistParser.insertKeyWithJson(
        _infoPlist.path,
        key: 'UIApplicationSceneManifest',
        json: _sceneManifestJson,
      )
      ? null
      : 'tvos/Runner/Info.plist could not be edited';

  /// Drops `customModule` and `customModuleProvider` from any
  /// `FlutterViewController` in the `Flutter` module, leaving every other
  /// element as it was, and reports a storyboard it cannot write.
  void _repairStoryboard(File storyboard, {bool quiet = false}) {
    final String original = storyboard.readAsStringSync();
    final String repaired = original.replaceAllMapped(_flutterViewControllerTag, (Match element) {
      final String tag = element[0]!;
      if (!_flutterModule.hasMatch(tag)) {
        return tag;
      }
      return tag.replaceAll(RegExp(r'\s+customModule(?:Provider)?="[^"]*"'), '');
    });
    if (repaired == original) {
      return;
    }
    if (!_tryWrite(storyboard, repaired)) {
      logger.printError(
        'Could not write ${_described(storyboard)}. It names FlutterViewController as a Swift '
        'class in the Flutter module, which UIKit cannot find, so the scene starts with no '
        'Flutter view. Remove customModule="Flutter" and customModuleProvider from it.',
      );
      return;
    }
    if (quiet) {
      return;
    }
    logger.printStatus(
      'Fixed ${_described(storyboard)}: it referred to FlutterViewController as a Swift class, '
      'which UIKit cannot find, so the scene started without a Flutter view.',
    );
  }

  /// Writes [contents] to [file], and says whether it could. A read-only
  /// checkout or file must not stop the build; the caller reports it.
  bool _tryWrite(File file, String contents) =>
      _tryWriting(file, () => file.writeAsStringSync(contents));

  bool _tryWriteBytes(File file, List<int> bytes) =>
      _tryWriting(file, () => file.writeAsBytesSync(bytes));

  bool _tryWriting(File file, void Function() write) {
    var written = false;
    // Flutter's file system turns a permission error into a ToolExit.
    ErrorHandlingFileSystem.noExitOnFailure(() {
      try {
        write();
        written = true;
      } on FileSystemException catch (error) {
        logger.printTrace('UIScene migration: could not write ${file.path}: $error');
      }
    });
    return written;
  }

  /// [file] as the developer sees it: tvos/Runner/Base.lproj/Main.storyboard.
  String _described(File file) =>
      'tvos/Runner/${file.fileSystem.path.relative(file.path, from: _runnerDirectory.path)}';

  bool _appDelegateBuildsItsOwnWindow() =>
      _appDelegate.existsSync() &&
      _appDelegate.readAsStringSync().contains('FlutterViewController(');

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
