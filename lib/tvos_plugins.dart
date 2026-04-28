// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/platform_plugins.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:yaml/yaml.dart';

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

/// Discovers tvOS plugins by scanning all dependencies' pubspec.yaml
/// and looking for `flutter.plugin.platforms.tvos`.
///
/// Flutter's built-in `findPlugins()` ignores unknown platform keys like `tvos`,
/// so we read the dependencyGraph from .flutter-plugins-dependencies
/// (which Flutter does populate) to get plugin names and paths,
/// then parse each plugin's pubspec.yaml ourselves.
List<TvosPlugin> _discoverTvosPlugins(FlutterProject project) {
  final tvosPlugins = <TvosPlugin>[];

  // Read .flutter-plugins-dependencies to get dependencyGraph
  // Flutter writes this even for unrecognized platforms — it lists all
  // packages that declare flutter.plugin in their pubspec.
  final File depsFile = project.flutterPluginsDependenciesFile;
  if (!depsFile.existsSync()) {
    return tvosPlugins;
  }

  Map<String, dynamic> depsJson;
  try {
    depsJson = json.decode(depsFile.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException {
    // Malformed JSON — treat as no plugins.
    return tvosPlugins;
  } on FileSystemException {
    // File disappeared between existsSync() and read.
    return tvosPlugins;
  }

  final List<dynamic> depGraph = (depsJson['dependencyGraph'] as List<dynamic>?) ?? <dynamic>[];

  // Build a name→path map from the pub package config
  final packagePaths = <String, String>{};
  final File packageConfigFile = project.directory
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  if (packageConfigFile.existsSync()) {
    try {
      final packageConfig =
          json.decode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
      final List<dynamic> packages = (packageConfig['packages'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic pkg in packages) {
        final pkgMap = pkg as Map<String, dynamic>;
        final name = pkgMap['name'] as String;
        var rootUri = pkgMap['rootUri'] as String;
        // rootUri may be relative to .dart_tool/
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
      // Malformed package_config.json — leave packagePaths empty and let
      // pubspec-based fallback handle plugin resolution.
    } on TypeError {
      // Unexpected JSON shape (cast failure); fall through to pubspec fallback.
    }
  }

  for (final dynamic dep in depGraph) {
    final depMap = dep as Map<String, dynamic>;
    final pluginName = depMap['name'] as String;
    final String? pluginPath = packagePaths[pluginName];
    if (pluginPath == null) {
      continue;
    }

    // Read the plugin's pubspec.yaml for tvos platform
    final File pubspecFile = globals.fs.file(globals.fs.path.join(pluginPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      continue;
    }

    try {
      final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      final flutter = pubspec['flutter'] as YamlMap?;
      if (flutter == null) {
        continue;
      }

      final plugin = flutter['plugin'] as YamlMap?;
      if (plugin == null) {
        continue;
      }

      final platforms = plugin['platforms'] as YamlMap?;
      if (platforms == null) {
        continue;
      }

      final tvosConfig = platforms['tvos'] as YamlMap?;
      if (tvosConfig == null) {
        continue;
      }

      // Found a tvOS plugin
      tvosPlugins.add(
        TvosPlugin(
          name: pluginName,
          path: pluginPath,
          pluginClass: tvosConfig['pluginClass'] as String?,
          dartPluginClass: tvosConfig['dartPluginClass'] as String?,
          ffiPlugin: tvosConfig[kFfiPlugin] as bool?,
        ),
      );

      globals.logger.printTrace('Discovered tvOS plugin: $pluginName at $pluginPath');
    } on YamlException {
      // Malformed pubspec.yaml — skip this plugin.
      continue;
    } on TypeError {
      // pubspec layout doesn't match the expected schema (e.g. plugin.platforms
      // is a list rather than a map); skip this plugin.
      continue;
    }
  }

  return tvosPlugins;
}

Future<void> ensureReadyForTvosTooling(FlutterProject project) async {
  final Directory tvosDir = project.directory.childDirectory('tvos');
  if (!tvosDir.existsSync()) {
    return;
  }

  final List<TvosPlugin> plugins = _discoverTvosPlugins(project);
  final methodChannelPlugins = <Map<String, Object?>>[];
  final ffiPlugins = <Map<String, Object?>>[];

  // Tightly-typed inner list lets us avoid dynamic dispatch on `.add(...)`.
  final tvosPluginEntries = <Map<String, dynamic>>[];
  final dependenciesJson = <String, dynamic>{
    'info': 'This is a generated file; do not edit or check into version control.',
    'plugins': <String, dynamic>{'tvos': tvosPluginEntries},
    'dependencyGraph': <dynamic>[],
  };

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
