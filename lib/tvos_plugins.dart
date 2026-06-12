// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/platform_plugins.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:yaml/yaml.dart';

import 'tvos_swift_package_manager.dart';

const String _swiftPluginRegistryTemplate = '''
//
//  Generated file. Do not edit.
//

import Flutter
import Foundation

{{#methodChannelPlugins}}
import {{name}}
{{/methodChannelPlugins}}

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  {{#methodChannelPlugins}}
  {{class}}.register(with: registry.registrar(forPlugin: "{{class}}"))
{{/methodChannelPlugins}}
}
''';

/// Snapshot of the user-facing plugins for which a federated
/// `<name>_tvos` package is published under the
/// [`fluttertv.dev`](https://pub.dev/publishers/fluttertv.dev/packages)
/// verified publisher.
///
/// Keys are the **user-facing** pub package names — the aggregator the
/// app pulls into its pubspec, not its iOS/macOS federated
/// implementation. Users depend on `audioplayers`, never on
/// `audioplayers_darwin` directly, so suggesting once on the
/// aggregator name is enough — the `_darwin` sibling is not a key and
/// will never match.
///
/// Values are alternative tvOS implementations the user might already
/// have (e.g. one upstream plugin could in future have two competing
/// `*_tvos` ports). Empty list means the canonical `<name>_tvos` is
/// the only acceptable fix.
///
/// Source of truth: https://pub.dev/publishers/fluttertv.dev/packages.
/// Update this table when the publisher gains or loses a package.
const Map<String, List<String>> _kKnownTvosPlugins = <String, List<String>>{
  'audioplayers': <String>[],
  'connectivity_plus': <String>[],
  'device_info_plus': <String>[],
  'flutter_secure_storage': <String>[],
  'flutter_tts': <String>[],
  'package_info_plus': <String>[],
  'path_provider': <String>[],
  'shared_preferences': <String>[],
  'sqflite': <String>[],
  'video_player': <String>[],
  'wakelock_plus': <String>[],
};

/// One entry surfaced by [_walkPluginDependencies].
class _DependencyPluginYaml {
  _DependencyPluginYaml({
    required this.name,
    required this.path,
    required this.pluginYaml,
  });

  /// Pub package name (e.g. `audioplayers`).
  final String name;

  /// Resolved absolute filesystem path to the plugin's checkout.
  final String path;

  /// The `flutter.plugin:` map from the plugin's `pubspec.yaml`.
  final YamlMap pluginYaml;
}

/// Walks the project's plugin dependency graph and yields each entry
/// that declares a `flutter.plugin:` block, regardless of platform.
///
/// Flutter's built-in [`findPlugins`](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/flutter_plugins.dart)
/// ignores unknown platform keys like `tvos`, so we read the
/// `dependencyGraph` from `.flutter-plugins-dependencies` (which
/// Flutter does populate even for unrecognized platforms) to get
/// plugin names, resolve each one's path through
/// `.dart_tool/package_config.json`, and parse each pubspec ourselves.
///
/// Returns `[]` (not an error) if either input file is missing or
/// malformed; callers degrade silently the same way Flutter itself
/// does for plugin discovery.
List<_DependencyPluginYaml> _walkPluginDependencies(FlutterProject project) {
  final out = <_DependencyPluginYaml>[];

  final File depsFile = project.flutterPluginsDependenciesFile;
  if (!depsFile.existsSync()) {
    return out;
  }
  Map<String, dynamic> depsJson;
  try {
    final decoded = json.decode(depsFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      // Root JSON is valid but not an object (e.g. `[]`, `null`, a
      // bare number). A blind `as Map` cast would throw `TypeError`
      // outside the try/catch — degrade silently here the same way
      // we do for malformed JSON.
      return out;
    }
    depsJson = decoded;
  } on FormatException {
    return out; // Malformed JSON — treat as no plugins.
  } on FileSystemException {
    return out; // File disappeared between existsSync() and read.
  }
  final rawGraph = depsJson['dependencyGraph'];
  final List<dynamic> depGraph =
      rawGraph is List<dynamic> ? rawGraph : <dynamic>[];

  // Build a name→path map from .dart_tool/package_config.json.
  final packagePaths = <String, String>{};
  final File packageConfigFile = project.directory
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  if (packageConfigFile.existsSync()) {
    try {
      final packageConfig =
          json.decode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
      final List<dynamic> packages =
          (packageConfig['packages'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic pkg in packages) {
        final pkgMap = pkg as Map<String, dynamic>;
        final name = pkgMap['name'] as String;
        var rootUri = pkgMap['rootUri'] as String;
        // rootUri may be relative to .dart_tool/ or a file:// URI.
        if (rootUri.startsWith('../')) {
          rootUri = globals.fs.path.normalize(
            globals.fs.path.join(project.directory.path, '.dart_tool', rootUri),
          );
        } else if (rootUri.startsWith('file://')) {
          rootUri = Uri.parse(rootUri).toFilePath();
        }
        packagePaths[name] = rootUri;
      }
    } on FormatException {
      // Malformed package_config.json — leave packagePaths empty.
    } on TypeError {
      // Unexpected JSON shape; fall through with empty packagePaths.
    }
  }

  for (final dynamic dep in depGraph) {
    final depMap = dep as Map<String, dynamic>;
    final pluginName = depMap['name'] as String;
    final String? pluginPath = packagePaths[pluginName];
    if (pluginPath == null) {
      continue;
    }
    final File pubspecFile = globals.fs.file(
      globals.fs.path.join(pluginPath, 'pubspec.yaml'),
    );
    if (!pubspecFile.existsSync()) {
      continue;
    }
    try {
      final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      final flutter = pubspec['flutter'] as YamlMap?;
      final plugin = flutter?['plugin'] as YamlMap?;
      if (plugin == null) {
        continue;
      }
      out.add(_DependencyPluginYaml(
        name: pluginName,
        path: pluginPath,
        pluginYaml: plugin,
      ));
    } on YamlException {
      // Malformed pubspec.yaml — skip this plugin.
      continue;
    } on TypeError {
      // pubspec layout doesn't match the expected schema (e.g.
      // plugin.platforms is a list rather than a map); skip.
      continue;
    }
  }

  return out;
}

/// Discovers plugins in [project] that declare a `flutter.plugin.platforms.tvos`
/// block, parsing them into [TvosPlugin] instances.
List<TvosPlugin> _discoverTvosPlugins(FlutterProject project) {
  final tvosPlugins = <TvosPlugin>[];
  for (final dep in _walkPluginDependencies(project)) {
    final platforms = dep.pluginYaml['platforms'];
    if (platforms is! YamlMap) {
      continue;
    }
    final tvosConfig = platforms['tvos'];
    if (tvosConfig is! YamlMap) {
      continue;
    }
    tvosPlugins.add(
      TvosPlugin(
        name: dep.name,
        path: dep.path,
        pluginClass: tvosConfig['pluginClass'] as String?,
        dartPluginClass: tvosConfig['dartPluginClass'] as String?,
        ffiPlugin: tvosConfig[kFfiPlugin] as bool?,
      ),
    );
    globals.logger.printTrace(
      'Discovered tvOS plugin: ${dep.name} at ${dep.path}',
    );
  }
  return tvosPlugins;
}

/// Discovers the tvOS plugins in [project] that ship a Swift Package
/// (`<plugin>/tvos/Package.swift`) and returns them as [TvosSpmPlugin]s for the
/// generated SPM umbrella.
///
/// A plugin is consumed via Swift Package Manager when it has a `Package.swift`;
/// plugins with only a `<name>.podspec` continue to resolve through CocoaPods
/// (the Podfile skips any plugin that has a `Package.swift`, so the two never
/// double-link). A plugin that ships both is treated as SPM here.
List<TvosSpmPlugin> discoverTvosSpmPlugins(FlutterProject project) {
  final spmPlugins = <TvosSpmPlugin>[];
  for (final TvosPlugin plugin in _discoverTvosPlugins(project)) {
    final Directory tvosDir = globals.fs.directory(
      globals.fs.path.join(plugin.path, 'tvos'),
    );
    final File manifest = tvosDir.childFile('Package.swift');
    if (!manifest.existsSync()) {
      continue;
    }
    final _SwiftPackageNames names = _readSwiftPackageNames(manifest);
    // Prefer the package name declared in the manifest; fall back to the pub
    // package name (the porter sets them equal). The library name defaults to
    // the hyphenated package name when the manifest doesn't declare one.
    final String packageName = names.package ?? plugin.name;
    spmPlugins.add(
      TvosSpmPlugin(
        name: packageName,
        packagePath: tvosDir.path,
        libraryName: names.library,
      ),
    );
    globals.logger.printTrace(
      'tvOS SPM plugin: $packageName (product ${names.library ?? '${packageName.replaceAll('_', '-')} [derived]'}) at ${tvosDir.path}',
    );
  }
  return spmPlugins;
}

/// The `name:` (package) and `.library(name:)` (product) declared in a
/// `Package.swift`. Either may be null when it can't be parsed.
class _SwiftPackageNames {
  const _SwiftPackageNames({this.package, this.library});
  final String? package;
  final String? library;
}

// SwiftPM identifiers used as a symlink filename and interpolated into the
// generated umbrella manifest. Package names are `[A-Za-z0-9_]`; product
// (library) names may also contain hyphens.
final RegExp _packageNamePattern = RegExp(r'^[A-Za-z0-9_]+$');
final RegExp _libraryNamePattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Extracts the SwiftPM package name (anchored to the `Package(` initializer,
/// so a `name:` in a comment or a product can't win) and the first
/// `.library(name:)` product from a `Package.swift`. Validates both against the
/// SwiftPM identifier charset; an unparseable or invalid value is logged and
/// returned as null so the caller falls back to a safe default.
_SwiftPackageNames _readSwiftPackageNames(File manifest) {
  String contents;
  try {
    contents = manifest.readAsStringSync();
  } on FileSystemException catch (e) {
    globals.logger.printTrace('Could not read ${manifest.path}: $e');
    return const _SwiftPackageNames();
  }

  String? validated(Match? match, RegExp charset, String what) {
    final String? value = match?.group(1);
    if (value == null) {
      return null;
    }
    if (!charset.hasMatch(value)) {
      globals.logger.printTrace(
        'Ignoring invalid SwiftPM $what "$value" in ${manifest.path}; '
        'falling back to a derived name.',
      );
      return null;
    }
    return value;
  }

  // Anchor the package name to `Package( name:` rather than the first `name:`
  // anywhere in the file (which could be a comment or a product/target).
  final String? package = validated(
    RegExp(r'Package\s*\(\s*name:\s*"([^"]+)"').firstMatch(contents),
    _packageNamePattern,
    'package name',
  );
  final String? library = validated(
    RegExp(r'\.library\s*\(\s*name:\s*"([^"]+)"').firstMatch(contents),
    _libraryNamePattern,
    'library name',
  );
  return _SwiftPackageNames(package: package, library: library);
}

/// Returns the names of every dependency that declares `flutter.plugin`,
/// regardless of whether it advertises a `tvos:` platform.
///
/// Used by [recommendTvosPluginsToInstall] to decide which entries from
/// [_kKnownTvosPlugins] are worth suggesting and which the user has
/// already satisfied.
List<String> _findAllPluginNames(FlutterProject project) {
  return <String>[
    for (final dep in _walkPluginDependencies(project)) dep.name,
  ];
}

/// Builds the developer-facing warning lines for any plugin in the
/// project's dep graph that has a FlutterTV-published tvOS
/// implementation the user hasn't added yet.
///
/// For each plugin in [allPluginNames] whose **base name** is a key
/// of [_kKnownTvosPlugins], if the user hasn't already added the
/// canonical `<name>_tvos` (or one of the listed alternatives), emit a
/// one-line warning pointing at pub.dev.
///
/// Aggregator-vs-impl deduplication is handled implicitly by keying
/// only on user-facing names — when an app pulls in `audioplayers`,
/// `audioplayers_darwin` also lands in the dep graph but isn't a key,
/// so the warning fires exactly once.
///
/// Public so tests can drive it without faking a project tree.
List<String> recommendTvosPluginsToInstall({
  required Iterable<String> allPluginNames,
}) {
  // Every plugin in the project's dep graph — used both as the
  // iteration source AND as the "what does the user already have?"
  // membership check. If the user added `<name>_tvos`, that package
  // also lands here, so the canonical-or-alternative check below
  // suppresses re-suggesting what's already installed.
  final depGraph = allPluginNames.toSet();
  final messages = <String>[];
  for (final name in allPluginNames) {
    final List<String>? alternatives = _kKnownTvosPlugins[name];
    if (alternatives == null) {
      continue;
    }
    final canonical = '${name}_tvos';
    final satisfied = depGraph.contains(canonical)
        || alternatives.any(depGraph.contains);
    if (satisfied) {
      continue;
    }
    if (alternatives.isEmpty) {
      messages.add(
        '$canonical is available on pub.dev under the fluttertv.dev '
        'verified publisher. Did you forget to add it to pubspec.yaml?',
      );
    } else {
      final List<String> options = <String>[canonical, ...alternatives];
      final last = options.removeLast();
      messages.add(
        '[${options.join(', ')} or $last] is available on pub.dev. '
        'Did you forget to add one to pubspec.yaml?',
      );
    }
  }
  return messages;
}

Future<void> ensureReadyForTvosTooling(FlutterProject project) async {
  final Directory tvosDir = project.directory.childDirectory('tvos');
  if (!tvosDir.existsSync()) {
    return;
  }

  final List<TvosPlugin> plugins = _discoverTvosPlugins(project);

  // For each plugin in the app's dep graph that has a FlutterTV-
  // published `<name>_tvos` sibling the user hasn't added yet, print
  // a one-line "available on pub.dev — did you forget?". Plugins
  // outside the curated list are silently ignored — we don't hard-fail
  // on them, and we don't auto-recommend the porter for every random
  // plugin (that would be presumptuous and noisy).
  final recommendations = recommendTvosPluginsToInstall(
    allPluginNames: _findAllPluginNames(project),
  );
  for (final message in recommendations) {
    globals.logger.printWarning(message);
  }
  final methodChannelPlugins = <Map<String, Object?>>[];
  final ffiPlugins = <Map<String, Object?>>[];

  // Tightly-typed inner list lets us avoid dynamic dispatch on `.add(...)`.
  final tvosPluginEntries = <Map<String, dynamic>>[];

  // CRITICAL: preserve the existing `.flutter-plugins-dependencies` rather
  // than overwriting it. Stock `flutter pub get` writes ios/android/...
  // plugin lists AND the `dependencyGraph` array we need for later
  // `_discoverTvosPlugins` calls (e.g. from `writeTvosDartPluginRegistrant`
  // during the build pipeline). Wiping `dependencyGraph: []` here caused
  // every federated tvOS plugin with `dartPluginClass:` to silently
  // disappear from the registrant — producing runtime
  // `MissingPluginException` and `Bad state: <X>Platform.instance must
  // be set` errors. See bug investigation 2026-05-26.
  var dependenciesJson = <String, dynamic>{
    'info': 'This is a generated file; do not edit or check into version control.',
    'plugins': <String, dynamic>{},
    'dependencyGraph': <dynamic>[],
  };
  final File depsFile = project.flutterPluginsDependenciesFile;
  if (depsFile.existsSync()) {
    try {
      final decoded = json.decode(depsFile.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        dependenciesJson = decoded;
      } else {
        // Valid JSON whose root isn't an object (e.g. `[]`, `null`,
        // a bare number). A blind `as Map<String, dynamic>` would
        // throw `TypeError` and crash the build — fall back to the
        // fresh skeleton instead, and surface a warning so the
        // bad file isn't silently masked.
        globals.logger.printWarning(
          '.flutter-plugins-dependencies is not a JSON object; regenerating from scratch.',
        );
      }
    } on FormatException catch (e) {
      globals.logger.printWarning(
        '.flutter-plugins-dependencies contains malformed JSON ($e); regenerating from scratch.',
      );
    } on FileSystemException catch (e) {
      globals.logger.printWarning(
        '.flutter-plugins-dependencies disappeared before it could be read ($e); regenerating from scratch.',
      );
    }
  }
  // Ensure `plugins` exists and graft the tvOS list onto it. iOS / Android
  // / etc. entries that stock pub get wrote stay intact. Use a runtime
  // type check rather than `as Map<String, dynamic>?` so a wrong-shaped
  // value (e.g. `"plugins": []`) falls back to an empty map instead of
  // throwing `TypeError` outside the try/catch above.
  final rawPlugins = dependenciesJson['plugins'];
  final pluginsMap = rawPlugins is Map<String, dynamic>
      ? rawPlugins
      : <String, dynamic>{};
  pluginsMap['tvos'] = tvosPluginEntries;
  dependenciesJson['plugins'] = pluginsMap;

  final pluginsBuffer = StringBuffer();

  for (final plugin in plugins) {
    if (plugin.hasMethodChannel()) {
      methodChannelPlugins.add(plugin.toMap());
    }
    if (plugin.hasFfi()) {
      ffiPlugins.add(plugin.toMap());
    }

    tvosPluginEntries.add(<String, dynamic>{
      'name': plugin.name,
      'path': plugin.path,
      'native_build': plugin.hasNativeBuild(),
      'dependencies': <String>[],
      'dev_dependency': false,
    });
    pluginsBuffer.writeln('${plugin.name}=${plugin.path}');
  }

  if (ffiPlugins.isNotEmpty) {
    globals.logger.printTrace(
      'Found ${ffiPlugins.length} FFI plugin(s): '
      '${ffiPlugins.map((p) => p['name']).join(', ')}',
    );
  }

  // Write .flutter-plugins-dependencies with tvos key for the Podfile to read
  project.flutterPluginsDependenciesFile.writeAsStringSync(json.encode(dependenciesJson));
  project.directory.childFile('.flutter-plugins').writeAsStringSync(pluginsBuffer.toString());

  final context = <String, Object>{'methodChannelPlugins': methodChannelPlugins};

  final File registryFile = tvosDir
      .childDirectory('Flutter')
      .childFile('GeneratedPluginRegistrant.swift');

  final String renderedTemplate = globals.templateRenderer.renderString(
    _swiftPluginRegistryTemplate,
    context,
  );
  registryFile.parent.createSync(recursive: true);
  registryFile.writeAsStringSync(renderedTemplate);

  globals.logger.printTrace('Generated $registryFile successfully for tvOS');

  // Also generate the ObjC registrant in Runner/ which is what the Xcode project
  // actually compiles. This bridges to the CocoaPods framework modules.
  final Directory runnerDir = tvosDir.childDirectory('Runner');
  if (runnerDir.existsSync()) {
    final imports = StringBuffer();
    final registrations = StringBuffer();

    for (final plugin in plugins) {
      if (plugin.hasMethodChannel()) {
        imports.writeln('@import ${plugin.name};');
        // The two string literals concatenate to one Objective-C statement.
        // No whitespace belongs between them — this is `selector:[arg]` syntax.
        registrations.writeln(
          // ignore: missing_whitespace_between_adjacent_strings
          '  [${plugin.pluginClass} registerWithRegistrar:'
          '[registry registrarForPlugin:@"${plugin.pluginClass}"]];',
        );
      }
    }

    final File objcHeader = runnerDir.childFile('GeneratedPluginRegistrant.h');
    objcHeader.writeAsStringSync(
      '//\n'
      '//  Generated file. Do not edit.\n'
      '//\n'
      '\n'
      '#ifndef GeneratedPluginRegistrant_h\n'
      '#define GeneratedPluginRegistrant_h\n'
      '\n'
      '#import <Flutter/Flutter.h>\n'
      '\n'
      'NS_ASSUME_NONNULL_BEGIN\n'
      '\n'
      '@interface GeneratedPluginRegistrant : NSObject\n'
      '+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;\n'
      '@end\n'
      '\n'
      'NS_ASSUME_NONNULL_END\n'
      '\n'
      '#endif /* GeneratedPluginRegistrant_h */\n',
    );

    final File objcImpl = runnerDir.childFile('GeneratedPluginRegistrant.m');
    objcImpl.writeAsStringSync(
      '//\n'
      '//  Generated file. Do not edit.\n'
      '//\n'
      '\n'
      '#import "GeneratedPluginRegistrant.h"\n'
      '\n'
      '$imports'
      '\n'
      '@implementation GeneratedPluginRegistrant\n'
      '\n'
      '+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n'
      '$registrations'
      '}\n'
      '\n'
      '@end\n',
    );

    globals.logger.printTrace('Generated ObjC plugin registrant in Runner/');
  }

  // Write the tvOS dart plugin registrant now that the native side is fully
  // configured. This is a second call — the first one ran before the kernel
  // compilation (see writeTvosDartPluginRegistrant) — kept for consistency.
  writeTvosDartPluginRegistrant(project, plugins: plugins);
}

/// Writes `.dart_tool/flutter_build/dart_plugin_registrant.dart` with tvOS-
/// aware plugin registrations.
///
/// **Must be called BEFORE `globals.buildSystem.build()`** so the Dart kernel
/// is compiled with the correct registrant. Flutter's own tooling only knows
/// about android/ios/linux/macos/windows; on tvOS (which identifies as an
/// iOS-family OS with `Platform.isIOS == true` and `Platform.isTvOS == true`)
/// upstream plugin discovery would register iOS plugins (e.g.
/// `shared_preferences_foundation`) that have no native pod in our tvOS
/// build, causing channel-error crashes at runtime. This tvOS-strict
/// registrant only lists plugins that declare `flutter.plugin.platforms.tvos`
/// in their pubspec — iOS-only plugins are silently ignored.
///
/// Pass [plugins] to skip re-discovery when already known (e.g. when called
/// from [ensureReadyForTvosTooling]). When omitted, plugins are discovered
/// from the project's pubspec/package-config.
void writeTvosDartPluginRegistrant(FlutterProject project, {List<TvosPlugin>? plugins}) {
  final List<TvosPlugin> dartPlugins = (plugins ?? _discoverTvosPlugins(project))
      .where((p) => p.hasDart())
      .toList();

  // Build registrant content even when there are no dart plugins — we still
  // want an empty (but valid) registrant to prevent the iOS one from loading.
  final dartImports = StringBuffer();
  final dartRegistrations = StringBuffer();

  for (final plugin in dartPlugins) {
    final String alias = plugin.name.replaceAll('.', '_').replaceAll('-', '_');
    final libFile = '${plugin.name}.dart';
    dartImports.writeln("import 'package:${plugin.name}/$libFile' as $alias;");
    dartRegistrations.writeln(
      '    try {\n'
      '      $alias.${plugin.dartPluginClass}.registerWith();\n'
      '    } catch (err) {\n'
      "      print('`${plugin.name}` threw an error: \$err. '\n"
      "          'The app may not function as expected until you remove this plugin from pubspec.yaml');\n"
      '    }',
    );
  }

  final dartRegistrantContent =
      '//\n'
      '// Generated by flutter-tvos. Do not edit.\n'
      "// Flutter's own plugin-registrant generator only recognizes the\n"
      '// android/ios/linux/macos/web/windows platform keys, so on tvOS it\n'
      '// emits no registrations for plugins declared under `tvos:`. This\n'
      '// file is the tvOS-aware replacement. TvosKernelSnapshot +\n'
      '// TvosDartPluginRegistrantTarget (see build_targets/application.dart)\n'
      '// keep the stock DartPluginRegistrantTarget out of our build graph,\n'
      '// so this file is never overwritten by the upstream generator.\n'
      '//\n'
      '\n'
      '// @dart = 3.9\n'
      '\n'
      '$dartImports\n'
      "@pragma('vm:entry-point')\n"
      'class _PluginRegistrant {\n'
      "  @pragma('vm:entry-point')\n"
      '  static void register() {\n'
      '$dartRegistrations'
      '  }\n'
      '}\n';

  final Directory dartToolBuildDir = project.directory
      .childDirectory('.dart_tool')
      .childDirectory('flutter_build');
  // Create the directory if it doesn't exist yet (first build).
  dartToolBuildDir.createSync(recursive: true);
  final File dartRegistrantFile = dartToolBuildDir.childFile('dart_plugin_registrant.dart');
  dartRegistrantFile.writeAsStringSync(dartRegistrantContent);
  globals.logger.printTrace(
    'Wrote tvOS dart_plugin_registrant.dart '
    '(${dartPlugins.length} dart plugin(s))',
  );
}

class TvosPlugin extends PluginPlatform implements NativeOrDartPlugin {
  TvosPlugin({
    required this.name,
    this.path = '',
    this.pluginClass,
    this.dartPluginClass,
    this.defaultPackage,
    this.ffiPlugin,
  }) : assert(
         pluginClass != null ||
             dartPluginClass != null ||
             defaultPackage != null ||
             (ffiPlugin ?? false),
       );

  final String name;
  final String path;
  final String? pluginClass;
  final String? dartPluginClass;
  final String? defaultPackage;
  final bool? ffiPlugin;

  @override
  bool hasMethodChannel() => pluginClass != null;

  @override
  bool hasFfi() => ffiPlugin ?? false;

  @override
  bool hasDart() => dartPluginClass != null;

  /// Whether this plugin has native code that needs to be built (via CocoaPods).
  bool hasNativeBuild() => hasMethodChannel() || hasFfi();

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      if (pluginClass != null) 'class': pluginClass,
      if (dartPluginClass != null) 'dartPluginClass': dartPluginClass,
      if (defaultPackage != null) kDefaultPackage: defaultPackage,
      if (ffiPlugin ?? false) kFfiPlugin: true,
    };
  }
}
