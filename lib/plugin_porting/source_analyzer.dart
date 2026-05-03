// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:yaml/yaml.dart';

/// The native source language used by a plugin's existing iOS or macOS
/// implementation.
enum SourceLanguage { swift, objc, mixed, unknown }

/// Result of inspecting a candidate source plugin directory.
///
/// Built by [SourceAnalyzer.analyze]. Drives the templates module and the
/// eventual native-source porters by giving them the canonical interpretation
/// of the source's pubspec and on-disk layout.
class PluginSource {
  PluginSource({
    required this.directory,
    required this.packageName,
    required this.basePackageName,
    required this.outputPackageName,
    required this.sourcePlatform,
    required this.pluginClass,
    required this.dartPluginClass,
    required this.sourceLanguage,
    required this.platformInterfacePackage,
    required this.descriptionFromPubspec,
    required this.licenseFile,
    required this.classesDirectory,
  });

  /// Absolute source directory.
  final Directory directory;

  /// Pubspec name (e.g. `url_launcher_ios`).
  final String packageName;

  /// Base name with platform suffix stripped if any (e.g. `url_launcher` from
  /// `url_launcher_ios`, `path_provider` from `path_provider_foundation`).
  /// For non-federated plugins this equals [packageName].
  final String basePackageName;

  /// Suggested output package name for the generated `*_tvos` package.
  final String outputPackageName;

  /// Whichever of `ios` / `macos` we're modelling the port on (chosen by the
  /// user via `--base-platform`, or the analyzer's default).
  final String sourcePlatform;

  /// Native plugin class name as declared in
  /// `flutter.plugin.platforms.<sourcePlatform>.pluginClass`.
  final String pluginClass;

  /// Optional Dart plugin class declared on the same key. Federated plugins
  /// usually set this.
  final String? dartPluginClass;

  /// Detected language of the existing native implementation.
  final SourceLanguage sourceLanguage;

  /// Name of the federated platform-interface package this plugin depends on
  /// (e.g. `url_launcher_platform_interface`), or `null` if the plugin isn't
  /// federated.
  final String? platformInterfacePackage;

  /// `description:` line from the source pubspec, used to seed the output
  /// pubspec's description.
  final String descriptionFromPubspec;

  /// `LICENSE` file from the source if present, copied verbatim to the output.
  final File? licenseFile;

  /// Directory containing the native source files (`<sourcePlatform>/Classes`).
  /// May not exist on disk if the plugin uses a non-standard layout.
  final Directory classesDirectory;
}

/// Inspects a candidate source plugin directory and produces a [PluginSource]
/// describing how to port it.
///
/// Throws [PluginSourceError] for fatal misconfigurations:
///   * missing/unreadable pubspec
///   * not a Flutter plugin (no `flutter.plugin` key)
///   * pure-Dart plugin (no `iOS`/`macOS` native implementation)
///   * source already targets tvOS
///
/// The analyzer is deliberately tolerant about non-fatal oddities; it emits
/// warnings on the supplied `warningSink` (caller decides how to surface
/// them) and still returns a usable [PluginSource].
class SourceAnalyzer {
  SourceAnalyzer({required FileSystem fileSystem, void Function(String)? warningSink})
    : _fs = fileSystem,
      _warn = warningSink ?? ((_) {});

  final FileSystem _fs;
  final void Function(String) _warn;

  /// Analyses [sourceDirectory], honouring [preferPlatform] when both
  /// `ios` and `macos` are present (defaults to `ios`).
  PluginSource analyze(Directory sourceDirectory, {String preferPlatform = 'ios'}) {
    if (!sourceDirectory.existsSync()) {
      throw PluginSourceError('Source directory does not exist: ${sourceDirectory.path}');
    }

    final File pubspecFile = sourceDirectory.childFile('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw PluginSourceError(
        'No pubspec.yaml in ${sourceDirectory.path}. Pass a Flutter plugin directory.',
      );
    }

    final YamlMap pubspec;
    try {
      pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    } on YamlException catch (e) {
      throw PluginSourceError('Could not parse pubspec.yaml: $e');
    }

    final String packageName = (pubspec['name'] as String?) ?? '';
    if (packageName.isEmpty) {
      throw PluginSourceError('pubspec.yaml has no `name` field.');
    }
    if (packageName.endsWith('_tvos')) {
      throw PluginSourceError(
        '$packageName already targets tvOS. Pass an iOS or macOS plugin instead.',
      );
    }

    final flutter = pubspec['flutter'] as YamlMap?;
    final plugin = flutter?['plugin'] as YamlMap?;
    if (plugin == null) {
      throw PluginSourceError(
        '$packageName is not a Flutter plugin (no `flutter.plugin` key).',
      );
    }
    final platforms = plugin['platforms'] as YamlMap?;
    if (platforms == null) {
      throw PluginSourceError(
        '$packageName has no `flutter.plugin.platforms` map. Pure-Dart plugins '
        'do not need a separate `*_tvos` package — they federate through the '
        'platform interface and work on tvOS as-is.',
      );
    }

    // Pick the source platform we'll model the port on.
    final bool hasIos = platforms.containsKey('ios');
    final bool hasMacos = platforms.containsKey('macos');
    if (!hasIos && !hasMacos) {
      throw PluginSourceError(
        '$packageName has neither an `ios` nor a `macos` platform implementation. '
        'Add one of those before porting to tvOS.',
      );
    }
    final String chosenPlatform;
    if (preferPlatform == 'macos' && hasMacos) {
      chosenPlatform = 'macos';
    } else if (hasIos) {
      chosenPlatform = 'ios';
    } else {
      chosenPlatform = 'macos';
    }
    if (preferPlatform == 'ios' && !hasIos && hasMacos) {
      _warn(
        '$packageName has no iOS implementation; modelling the port on its '
        'macOS implementation instead.',
      );
    }

    final platformConfig = platforms[chosenPlatform] as YamlMap?;
    final pluginClass = platformConfig?['pluginClass'] as String?;
    if (pluginClass == null || pluginClass.isEmpty || pluginClass == 'none') {
      throw PluginSourceError(
        '$packageName declares no `pluginClass` under '
        '`flutter.plugin.platforms.$chosenPlatform`. Cannot scaffold a tvOS '
        'plugin without a native class to register.',
      );
    }
    final dartPluginClass = platformConfig?['dartPluginClass'] as String?;

    // Detect language by inspecting `<platform>/Classes/`. Fall back to
    // `<platform>/` itself when Classes/ doesn't exist (some old plugins).
    final Directory classesDir = _resolveClassesDir(sourceDirectory, chosenPlatform);
    final SourceLanguage lang = _detectLanguage(classesDir);
    if (lang == SourceLanguage.unknown) {
      _warn(
        'Could not detect Swift or Objective-C sources under '
        '${classesDir.path}. The scaffold will assume Swift; rename the stub '
        'to .m if needed.',
      );
    }

    // Best-effort: find the platform interface package in dependencies.
    String? platformInterface;
    final deps = pubspec['dependencies'] as YamlMap?;
    if (deps != null) {
      for (final Object? key in deps.keys) {
        if (key is String && key.endsWith('_platform_interface')) {
          platformInterface = key;
          break;
        }
      }
    }

    final String basePackageName = _stripPlatformSuffix(packageName);
    final outputPackageName = '${basePackageName}_tvos';

    final File license = sourceDirectory.childFile('LICENSE');

    return PluginSource(
      directory: sourceDirectory,
      packageName: packageName,
      basePackageName: basePackageName,
      outputPackageName: outputPackageName,
      sourcePlatform: chosenPlatform,
      pluginClass: pluginClass,
      dartPluginClass: dartPluginClass,
      sourceLanguage: lang,
      platformInterfacePackage: platformInterface,
      descriptionFromPubspec: (pubspec['description'] as String?)?.trim() ?? packageName,
      licenseFile: license.existsSync() ? license : null,
      classesDirectory: classesDir,
    );
  }

  Directory _resolveClassesDir(Directory source, String platform) {
    final Directory primary = source.childDirectory(platform).childDirectory('Classes');
    if (primary.existsSync()) {
      return primary;
    }
    return source.childDirectory(platform);
  }

  SourceLanguage _detectLanguage(Directory dir) {
    if (!dir.existsSync()) {
      return SourceLanguage.unknown;
    }
    var hasSwift = false;
    var hasObjc = false;
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final String ext = _fs.path.extension(entity.path).toLowerCase();
        if (ext == '.swift') {
          hasSwift = true;
        } else if (ext == '.m' || ext == '.mm' || ext == '.h') {
          hasObjc = true;
        }
      }
    }
    if (hasSwift && hasObjc) {
      return SourceLanguage.mixed;
    }
    if (hasSwift) {
      return SourceLanguage.swift;
    }
    if (hasObjc) {
      return SourceLanguage.objc;
    }
    return SourceLanguage.unknown;
  }

  /// `url_launcher_ios` → `url_launcher`; `path_provider_foundation` →
  /// `path_provider`; `audio_session` → `audio_session` (unchanged).
  ///
  /// Foundation is the umbrella name Flutter teams use when one package
  /// implements both iOS and macOS (`shared_preferences_foundation`,
  /// `path_provider_foundation`). We strip it the same way as `_ios`.
  String _stripPlatformSuffix(String name) {
    const suffixes = <String>['_ios', '_macos', '_foundation', '_darwin'];
    for (final s in suffixes) {
      if (name.endsWith(s) && name.length > s.length) {
        return name.substring(0, name.length - s.length);
      }
    }
    return name;
  }
}

/// Thrown when the source directory can't be ported (missing pubspec, wrong
/// package layout, already a tvOS plugin, etc).
class PluginSourceError implements Exception {
  PluginSourceError(this.message);
  final String message;
  @override
  String toString() => 'PluginSourceError: $message';
}
