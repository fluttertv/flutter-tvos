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
    required this.sourceVersion,
    required this.sourcePlatform,
    required this.pluginClass,
    required this.dartPluginClass,
    required this.sourceLanguage,
    required this.platformInterfacePackage,
    required this.platformInterfaceConstraint,
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

  /// `version:` from the source pubspec, used in the porting report's
  /// provenance header. `null` when the source pubspec omits a version
  /// (rare, but valid for path-only packages).
  final String? sourceVersion;

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

  /// The version constraint the source declared for
  /// [platformInterfacePackage] (e.g. `^2.4.0`), copied verbatim into the
  /// generated pubspec so `pub get` resolves. `null` when unknown — the
  /// template then falls back to `any`.
  final String? platformInterfaceConstraint;

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
    final bool sharedDarwin = platformConfig?['sharedDarwinSource'] == true;
    final dartPluginClass = platformConfig?['dartPluginClass'] as String?;
    String? pluginClass = platformConfig?['pluginClass'] as String?;
    if (pluginClass != null && (pluginClass.isEmpty || pluginClass == 'none')) {
      pluginClass = null;
    }

    // Locate the real native sources. Modern Flutter plugins put them under
    // `<platform>/<pkg>/Sources/<pkg>` (Swift Package Manager) or
    // `darwin/<pkg>/Sources/<pkg>` (`sharedDarwinSource: true`), not the
    // legacy `<platform>/Classes`.
    final Directory? sourcesDir = _resolveSourceDir(
      sourceDirectory,
      chosenPlatform,
      packageName,
      sharedDarwin: sharedDarwin,
    );

    if (sourcesDir == null && pluginClass == null) {
      // No native code AND no declared native class — a pure-Dart plugin
      // or a dart:ffi / package:objective_c plugin (e.g. modern
      // path_provider_foundation). These already work on tvOS through
      // their Dart implementation; no `*_tvos` package is needed.
      throw PluginSourceError(
        '$packageName has no native iOS/macOS sources — it is a pure-Dart '
        'or dart:ffi/package:objective_c plugin. It already works on tvOS '
        'through its Dart implementation; no '
        '`${_stripPlatformSuffix(packageName)}_tvos` package is needed.',
        advisory: true,
      );
    }

    if (sourcesDir != null && pluginClass == null) {
      // sharedDarwinSource / federated-only plugins sometimes omit
      // pluginClass. Recover the native registrant class from the sources.
      pluginClass = _derivePluginClass(sourcesDir) ??
          _defaultPluginClass(_stripPlatformSuffix(packageName));
      _warn(
        '$packageName declares no `pluginClass`; using `$pluginClass` '
        'inferred from ${sourcesDir.path}.',
      );
    }

    // When pluginClass is declared but no sources were found (e.g. Pigeon
    // generates them at build time), fall back to the legacy
    // `<platform>/Classes` path so the scaffolder emits the Phase-1 stub.
    final Directory classesDir = sourcesDir ??
        sourceDirectory.childDirectory(chosenPlatform).childDirectory('Classes');
    final SourceLanguage lang = _detectLanguage(classesDir);
    if (lang == SourceLanguage.unknown) {
      _warn(
        'Could not detect Swift or Objective-C sources under '
        '${classesDir.path}. The scaffold will assume Swift; rename the stub '
        'to .m if needed.',
      );
    }

    // Best-effort: find the platform interface package AND carry its
    // version constraint over verbatim. Hardcoding `^1.0.0` (the old
    // behaviour) makes `pub get` fail for the many plugins whose
    // interface is already past 1.x.
    String? platformInterface;
    String? platformInterfaceConstraint;
    final deps = pubspec['dependencies'] as YamlMap?;
    if (deps != null) {
      for (final Object? key in deps.keys) {
        if (key is String && key.endsWith('_platform_interface')) {
          platformInterface = key;
          final Object? v = deps[key];
          if (v is String && v.trim().isNotEmpty) {
            platformInterfaceConstraint = v.trim();
          }
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
      sourceVersion: (pubspec['version'] as String?)?.trim(),
      sourcePlatform: chosenPlatform,
      pluginClass: pluginClass!,
      dartPluginClass: dartPluginClass,
      sourceLanguage: lang,
      platformInterfacePackage: platformInterface,
      platformInterfaceConstraint: platformInterfaceConstraint,
      descriptionFromPubspec: (pubspec['description'] as String?)?.trim() ?? packageName,
      licenseFile: license.existsSync() ? license : null,
      classesDirectory: classesDir,
    );
  }

  /// Finds the directory that actually holds the native sources, trying
  /// (in order) the legacy `Classes/`, SPM `…/Sources/<pkg>`, any other
  /// `Sources/<dir>`, and finally the platform root. When
  /// `sharedDarwinSource` is set the shared `darwin/` tree is searched
  /// before the platform-specific one. Returns `null` when there is no
  /// native code anywhere (pure-Dart / FFI plugin).
  Directory? _resolveSourceDir(
    Directory source,
    String platform,
    String pkg, {
    required bool sharedDarwin,
  }) {
    final List<String> roots =
        sharedDarwin ? <String>['darwin', platform] : <String>[platform, 'darwin'];
    final List<Directory> candidates = <Directory>[];
    for (final String r in roots) {
      final Directory root = source.childDirectory(r);
      candidates.add(root.childDirectory('Classes'));
      candidates.add(
        root.childDirectory(pkg).childDirectory('Sources').childDirectory(pkg),
      );
      candidates.add(root.childDirectory('Sources').childDirectory(pkg));
      for (final Directory srcRoot in <Directory>[
        root.childDirectory(pkg).childDirectory('Sources'),
        root.childDirectory('Sources'),
      ]) {
        if (srcRoot.existsSync()) {
          for (final FileSystemEntity e in srcRoot.listSync()) {
            if (e is Directory) {
              candidates.add(e);
            }
          }
        }
      }
      candidates.add(root); // legacy flat layout — last resort.
    }
    for (final Directory c in candidates) {
      if (c.existsSync() && _hasNativeFiles(c)) {
        return c;
      }
    }
    return null;
  }

  /// True when [dir] (recursively) contains at least one Swift/ObjC source.
  /// `Package.swift` / `Package.resolved` are SPM manifests, not plugin
  /// code, so they don't count.
  bool _hasNativeFiles(Directory dir) {
    for (final FileSystemEntity e in dir.listSync(recursive: true)) {
      if (e is! File) {
        continue;
      }
      final String base = _fs.path.basename(e.path);
      if (base == 'Package.swift' || base == 'Package.resolved') {
        continue;
      }
      final String ext = _fs.path.extension(e.path).toLowerCase();
      if (ext == '.swift' || ext == '.h' || ext == '.m' || ext == '.mm') {
        return true;
      }
    }
    return false;
  }

  /// Best-effort scan for the class that registers with Flutter, so a
  /// plugin that omits `pluginClass` from its pubspec still scaffolds.
  /// Matches Swift `class X: … FlutterPlugin` and ObjC
  /// `@interface X : … <FlutterPlugin>`.
  String? _derivePluginClass(Directory dir) {
    final RegExp swift =
        RegExp(r'class\s+([A-Za-z_]\w*)\s*:\s*[^{]*\bFlutterPlugin\b');
    final RegExp objc =
        RegExp(r'@interface\s+([A-Za-z_]\w*)\s*:[^<]*<[^>]*\bFlutterPlugin\b');
    for (final FileSystemEntity e in dir.listSync(recursive: true)) {
      if (e is! File) {
        continue;
      }
      final String ext = _fs.path.extension(e.path).toLowerCase();
      if (ext != '.swift' && ext != '.h' && ext != '.m' && ext != '.mm') {
        continue;
      }
      final String src = e.readAsStringSync();
      final RegExpMatch? m =
          swift.firstMatch(src) ?? objc.firstMatch(src);
      if (m != null) {
        return m.group(1);
      }
    }
    return null;
  }

  /// `shared_preferences` → `SharedPreferencesPlugin`. Fallback when no
  /// class could be detected in the sources.
  String _defaultPluginClass(String base) {
    final String camel = base
        .split('_')
        .where((String p) => p.isNotEmpty)
        .map((String p) => p[0].toUpperCase() + p.substring(1))
        .join();
    return '${camel}Plugin';
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
    // Federated Apple-implementation naming conventions. Order matters:
    // longer/more-specific suffixes first so `_avfoundation` is not
    // shortened by `_foundation`.
    const suffixes = <String>[
      '_avfoundation',
      '_foundation',
      '_storekit',
      '_apple',
      '_ios',
      '_macos',
      '_darwin',
    ];
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
  PluginSourceError(this.message, {this.advisory = false});

  final String message;

  /// When true this is not a failure: the source legitimately needs no
  /// `*_tvos` package (pure-Dart / dart:ffi). The command prints the
  /// message and exits successfully rather than erroring.
  final bool advisory;

  @override
  String toString() => 'PluginSourceError: $message';
}
