// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'source_analyzer.dart';
import 'templates.dart' as tmpl;

/// Generates a NATIVE federated `*_tvos` package for a dart:ffi /
/// native-assets source (e.g. `path_provider_foundation`).
///
/// The flutter-tvos toolchain can't build native-assets for tvOS and we
/// don't patch Flutter, so reusing the FFI implementation is impossible.
/// Instead — exactly like flutter-tizen/plugins — we emit a Swift
/// method-channel plugin plus a Dart class that extends the plugin's
/// platform interface and forwards to that channel. This builds on tvOS
/// today (proven by `shared_preferences_tvos`).
///
/// Well-known plugins are seeded with a real, working implementation
/// (see [_seeds]); anything else gets a buildable skeleton whose handlers
/// return `FlutterMethodNotImplemented` and whose Dart inherits the
/// interface's throwing defaults, with a `PORTING_REPORT.md` checklist.
class NativeSkeleton {
  const NativeSkeleton();

  /// Relative-path → file-content for the whole generated package. Pure
  /// (no I/O) so the scaffolder owns writing and it unit-tests directly.
  Map<String, String> files({
    required PluginSource source,
    required String licenseHolder,
  }) {
    final String out = source.outputPackageName;
    final String swiftClass = source.pluginClass;
    final _Seed seed =
        _seeds[source.basePackageName]?.call(source) ?? _genericSeed(source);

    return <String, String>{
      'pubspec.yaml':
          tmpl.renderPubspec(source: source, licenseHolder: licenseHolder),
      'README.md':
          tmpl.renderReadme(source: source, licenseHolder: licenseHolder),
      'CHANGELOG.md': tmpl.renderChangelog(source: source),
      'analysis_options.yaml': tmpl.renderAnalysisOptions(),
      '.gitignore': tmpl.renderGitignore(),
      'test/${out}_test.dart':
          tmpl.renderTestStub(source: source, licenseHolder: licenseHolder),
      'tvos/$out.podspec':
          tmpl.renderPodspec(source: source, licenseHolder: licenseHolder),
      'lib/$out.dart': seed.dart,
      'tvos/Classes/$swiftClass.swift': seed.swift,
      'PORTING_REPORT.md': _report(source, seed),
      // A runnable, tvOS-only example so the package is testable
      // (`cd example && flutter-tvos run`). The command renders
      // `example/tvos/` on top of these.
      'example/pubspec.yaml': _examplePubspec(source),
      'example/lib/main.dart': seed.exampleMain,
      'example/analysis_options.yaml': tmpl.renderAnalysisOptions(),
      'example/.gitignore': tmpl.renderGitignore(),
      'example/README.md': '# ${source.basePackageName}_example\n\n'
          'tvOS-only example for `$out`. Run with:\n\n'
          '```sh\nflutter-tvos run\n```\n',
    };
  }

  String _examplePubspec(PluginSource source) {
    final String base = source.basePackageName;
    final String out = source.outputPackageName;
    return '''
name: ${base}_example
description: "tvOS example for $out."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  $base: any
  $out:
    path: ../

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
''';
  }

  String _report(PluginSource source, _Seed seed) {
    final String b = source.basePackageName;
    final StringBuffer r = StringBuffer()
      ..writeln('# ${source.outputPackageName} — native federated skeleton')
      ..writeln()
      ..writeln('Source `${source.packageName}` is a dart:ffi / '
          'native-assets plugin. That implementation cannot be built for '
          'tvOS by the flutter-tvos toolchain, so this package is a '
          '**native federated** port: a Swift method-channel plugin plus '
          'a Dart class extending `${source.platformInterfacePackage ?? '<platform interface>'}`.')
      ..writeln()
      ..writeln('## Status')
      ..writeln();
    if (seed.seeded) {
      r
        ..writeln('✅ Seeded with a working implementation. Methods wired:')
        ..writeln();
      for (final String m in seed.implemented) {
        r.writeln('- `$m` — implemented (native)');
      }
      for (final String m in seed.unsupported) {
        r.writeln('- `$m` — throws `UnsupportedError` (not available on tvOS)');
      }
      r
        ..writeln()
        ..writeln('Build the example on the tvOS simulator to verify, then '
            'publish.');
    } else {
      r
        ..writeln('⚠️ No seed for `$b`. This is a BUILDABLE SKELETON, not a '
            'working port:')
        ..writeln()
        ..writeln('- The Swift plugin registers its channel and returns '
            '`FlutterMethodNotImplemented` for every method.')
        ..writeln('- The Dart class extends the platform interface and '
            'inherits its throwing defaults (so it compiles and registers '
            'cleanly).')
        ..writeln()
        ..writeln('To finish it: implement each `${b}_platform_interface` '
            'method in `tvos/Classes/${source.pluginClass}.swift` and '
            'override it in `lib/${source.outputPackageName}.dart` to call '
            'the channel. Methods with no tvOS equivalent should throw '
            '`UnsupportedError`.');
    }
    r
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('Generated by `flutter-tvos plugin port`. Native federated '
          'model — no dart:ffi, no Flutter patching.');
    return r.toString();
  }

  /// Registry of hand-written, verified native mappings. Add an entry to
  /// turn a skeleton into a fully-working port.
  static final Map<String, _Seed Function(PluginSource)> _seeds =
      <String, _Seed Function(PluginSource)>{
    'path_provider': _pathProviderSeed,
  };

  // ----- generic (unseeded) ------------------------------------------------

  _Seed _genericSeed(PluginSource source) {
    final String channel = 'plugins.flutter.io/${source.basePackageName}';
    final String dart = tmpl.renderDartEntry(
      source: source,
      licenseHolder: 'The FlutterTV Authors',
    );
    final String swift = '''
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Native federated tvOS skeleton for `${source.basePackageName}`.
// TODO(porter): implement each platform-interface method here, then
// override it in lib/${source.outputPackageName}.dart.

import Flutter

public class ${source.pluginClass}: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "$channel",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(${source.pluginClass}(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // TODO(porter): handle the channel methods this plugin's platform
    // interface needs. Unknown / unsupported on tvOS -> leave as-is.
    result(FlutterMethodNotImplemented)
  }
}
''';
    return _Seed(
      dart: dart,
      swift: swift,
      seeded: false,
      exampleMain: '''
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('${source.outputPackageName}')),
        body: const Center(
          child: Text(
            'Skeleton example.\\nImplement the plugin, then call it here.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
''',
    );
  }
}

class _Seed {
  _Seed({
    required this.dart,
    required this.swift,
    required this.seeded,
    required this.exampleMain,
    this.implemented = const <String>[],
    this.unsupported = const <String>[],
  });

  final String dart;
  final String swift;
  final bool seeded;

  /// `example/lib/main.dart` — exercises the plugin on tvOS.
  final String exampleMain;

  final List<String> implemented;
  final List<String> unsupported;
}

// --------------------------------------------------------------------------
// path_provider — fully working tvOS implementation (NSFileManager).
// --------------------------------------------------------------------------

_Seed _pathProviderSeed(PluginSource source) {
  const String channel = 'plugins.flutter.io/path_provider';
  final String iface = source.platformInterfacePackage ??
      'path_provider_platform_interface';
  final String dart = '''
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// tvOS implementation of path_provider. Generated by
// `flutter-tvos plugin port` (native federated model).

import 'package:flutter/services.dart';
import 'package:$iface/$iface.dart';

/// The tvOS implementation of `PathProviderPlatform`.
class ${source.dartPluginClass} extends PathProviderPlatform {
  /// Registers this class as the default `PathProviderPlatform`.
  static void registerWith() {
    PathProviderPlatform.instance = ${source.dartPluginClass}();
  }

  final MethodChannel _channel =
      const MethodChannel('$channel');

  @override
  Future<String?> getTemporaryPath() =>
      _channel.invokeMethod<String>('getTemporaryDirectory');

  @override
  Future<String?> getApplicationSupportPath() =>
      _channel.invokeMethod<String>('getApplicationSupportDirectory');

  @override
  Future<String?> getLibraryPath() =>
      _channel.invokeMethod<String>('getLibraryDirectory');

  @override
  Future<String?> getApplicationDocumentsPath() =>
      _channel.invokeMethod<String>('getApplicationDocumentsDirectory');

  @override
  Future<String?> getApplicationCachePath() =>
      _channel.invokeMethod<String>('getApplicationCacheDirectory');

  @override
  Future<String?> getExternalStoragePath() async =>
      throw UnsupportedError('getExternalStoragePath is not supported on tvOS');

  @override
  Future<List<String>?> getExternalCachePaths() async =>
      throw UnsupportedError('getExternalCachePaths is not supported on tvOS');

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      throw UnsupportedError('getExternalStoragePaths is not supported on tvOS');

  @override
  Future<String?> getDownloadsPath() async =>
      throw UnsupportedError('getDownloadsPath is not supported on tvOS');
}
''';

  final String swift = '''
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// tvOS implementation of path_provider. Generated by
// `flutter-tvos plugin port` (native federated model). Uses
// NSSearchPathForDirectoriesInDomains / NSTemporaryDirectory, which are
// available on tvOS.

import Flutter
import Foundation

public class ${source.pluginClass}: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "$channel",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(${source.pluginClass}(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getTemporaryDirectory":
      result(NSTemporaryDirectory())
    case "getApplicationDocumentsDirectory":
      result(directory(.documentDirectory))
    case "getApplicationSupportDirectory":
      result(directory(.applicationSupportDirectory))
    case "getLibraryDirectory":
      result(directory(.libraryDirectory))
    case "getApplicationCacheDirectory":
      result(directory(.cachesDirectory))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func directory(_ dir: FileManager.SearchPathDirectory) -> String? {
    return NSSearchPathForDirectoriesInDomains(dir, .userDomainMask, true).first
  }
}
''';

  const String exampleMain = r'''
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const PathProviderExample());

class PathProviderExample extends StatefulWidget {
  const PathProviderExample({super.key});

  @override
  State<PathProviderExample> createState() => _State();
}

class _State extends State<PathProviderExample> {
  String _out = 'Querying path_provider on tvOS…';

  @override
  void initState() {
    super.initState();
    _query();
  }

  Future<void> _query() async {
    final StringBuffer b = StringBuffer();
    Future<void> probe(String label, Future<Directory> Function() f) async {
      try {
        b.writeln('$label = ${(await f()).path}');
      } catch (e) {
        b.writeln('$label ERROR: $e');
      }
    }

    await probe('temp', getTemporaryDirectory);
    await probe('documents', getApplicationDocumentsDirectory);
    await probe('support', getApplicationSupportDirectory);
    if (mounted) {
      setState(() => _out = b.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('path_provider on tvOS')),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_out, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
''';

  return _Seed(
    dart: dart,
    swift: swift,
    seeded: true,
    exampleMain: exampleMain,
    implemented: <String>[
      'getTemporaryPath',
      'getApplicationDocumentsPath',
      'getApplicationSupportPath',
      'getLibraryPath',
      'getApplicationCachePath',
    ],
    unsupported: <String>[
      'getExternalStoragePath',
      'getExternalCachePaths',
      'getExternalStoragePaths',
      'getDownloadsPath',
    ],
  );
}
