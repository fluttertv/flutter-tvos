// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/platform_plugins.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:yaml/yaml.dart';
import 'dart:convert';

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
  final List<TvosPlugin> tvosPlugins = <TvosPlugin>[];

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
  } catch (_) {
    return tvosPlugins;
  }

  final List<dynamic> depGraph = (depsJson['dependencyGraph'] as List<dynamic>?) ?? <dynamic>[];

  // Build a name→path map from the pub package config
  final Map<String, String> packagePaths = <String, String>{};
  final File packageConfigFile = project.directory
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  if (packageConfigFile.existsSync()) {
    try {
      final Map<String, dynamic> packageConfig =
          json.decode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
      final List<dynamic> packages = (packageConfig['packages'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic pkg in packages) {
        final Map<String, dynamic> pkgMap = pkg as Map<String, dynamic>;
        final String name = pkgMap['name'] as String;
        String rootUri = pkgMap['rootUri'] as String;
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
    } catch (_) {
      // Fall through
    }
  }

  for (final dynamic dep in depGraph) {
    final Map<String, dynamic> depMap = dep as Map<String, dynamic>;
    final String pluginName = depMap['name'] as String;
    final String? pluginPath = packagePaths[pluginName];
    if (pluginPath == null) continue;

    // Read the plugin's pubspec.yaml for tvos platform
    final File pubspecFile = globals.fs.file(
      globals.fs.path.join(pluginPath, 'pubspec.yaml'),
    );
    if (!pubspecFile.existsSync()) continue;

    try {
      final YamlMap pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      final YamlMap? flutter = pubspec['flutter'] as YamlMap?;
      if (flutter == null) continue;

      final YamlMap? plugin = flutter['plugin'] as YamlMap?;
      if (plugin == null) continue;

      final YamlMap? platforms = plugin['platforms'] as YamlMap?;
      if (platforms == null) continue;

      final YamlMap? tvosConfig = platforms['tvos'] as YamlMap?;
      if (tvosConfig == null) continue;

      // Found a tvOS plugin
      tvosPlugins.add(TvosPlugin(
        name: pluginName,
        path: pluginPath,
        pluginClass: tvosConfig['pluginClass'] as String?,
        dartPluginClass: tvosConfig['dartPluginClass'] as String?,
        ffiPlugin: tvosConfig[kFfiPlugin] as bool?,
      ));

      globals.logger.printTrace('Discovered tvOS plugin: $pluginName at $pluginPath');
    } catch (_) {
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
  final List<Map<String, Object?>> methodChannelPlugins = <Map<String, Object?>>[];
  final List<Map<String, Object?>> ffiPlugins = <Map<String, Object?>>[];

  final Map<String, dynamic> dependenciesJson = <String, dynamic>{
    'info': 'This is a generated file; do not edit or check into version control.',
    'plugins': <String, dynamic>{
      'tvos': <Map<String, dynamic>>[],
    },
    'dependencyGraph': <dynamic>[],
  };

  final StringBuffer pluginsBuffer = StringBuffer();

  for (final TvosPlugin plugin in plugins) {
    if (plugin.hasMethodChannel()) {
      methodChannelPlugins.add(plugin.toMap());
    }
    if (plugin.hasFfi()) {
      ffiPlugins.add(plugin.toMap());
    }

    (dependenciesJson['plugins'] as Map<String, dynamic>)['tvos'].add(<String, dynamic>{
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

  final Map<String, Object> context = <String, Object>{
    'methodChannelPlugins': methodChannelPlugins,
  };

  final File registryFile = tvosDir.childDirectory('Flutter').childFile('GeneratedPluginRegistrant.swift');

  final String renderedTemplate = globals.templateRenderer.renderString(_swiftPluginRegistryTemplate, context);
  registryFile.parent.createSync(recursive: true);
  registryFile.writeAsStringSync(renderedTemplate);

  globals.logger.printTrace('Generated $registryFile successfully for tvOS');

  // Also generate the ObjC registrant in Runner/ which is what the Xcode project
  // actually compiles. This bridges to the CocoaPods framework modules.
  final Directory runnerDir = tvosDir.childDirectory('Runner');
  if (runnerDir.existsSync()) {
    final StringBuffer imports = StringBuffer();
    final StringBuffer registrations = StringBuffer();

    for (final TvosPlugin plugin in plugins) {
      if (plugin.hasMethodChannel()) {
        imports.writeln('@import ${plugin.name};');
        registrations.writeln(
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
      '${imports.toString()}'
      '\n'
      '@implementation GeneratedPluginRegistrant\n'
      '\n'
      '+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n'
      '${registrations.toString()}'
      '}\n'
      '\n'
      '@end\n',
    );

    globals.logger.printTrace('Generated ObjC plugin registrant in Runner/');
  }
}

class TvosPlugin extends PluginPlatform implements NativeOrDartPlugin {
  TvosPlugin({
    required this.name,
    this.path = '',
    this.pluginClass,
    this.dartPluginClass,
    this.defaultPackage,
    this.ffiPlugin,
  }) : assert(pluginClass != null ||
            dartPluginClass != null ||
            defaultPackage != null ||
            (ffiPlugin ?? false));

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
