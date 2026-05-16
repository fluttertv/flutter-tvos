// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';

/// Writes the shared, platform-agnostic part of a Flutter app (the bits
/// `flutter create` would put in `lib/`, `test/`, `pubspec.yaml`, …) so a
/// tvOS-only project can be produced WITHOUT scaffolding — and then
/// deleting — an unwanted iOS/Android app.
///
/// The caller renders `tvos/` on top of this. Nothing here references any
/// other platform, so the result is tvOS-only by construction.
class TvosAppScaffold {
  TvosAppScaffold(this._fs);

  final FileSystem _fs;

  /// Generates the app shell at [projectDirPath] for package [name].
  /// Files that already exist are left untouched (so re-runs are safe).
  void write(String projectDirPath, String name) {
    final Directory root = _fs.directory(projectDirPath)..createSync(recursive: true);

    _put(root.childFile('pubspec.yaml'), _pubspec(name));
    _put(root.childDirectory('lib').childFile('main.dart'), _mainDart(name));
    _put(root.childDirectory('test').childFile('widget_test.dart'), _widgetTest(name));
    _put(root.childFile('analysis_options.yaml'), _analysisOptions());
    _put(root.childFile('.gitignore'), _gitignore());
    _put(root.childFile('README.md'), _readme(name));
  }

  void _put(File f, String contents) {
    if (f.existsSync()) {
      return;
    }
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  }

  String _pubspec(String name) => '''
name: $name
description: "A tvOS example app for $name."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
''';

  String _mainDart(String name) => '''
import 'package:flutter/material.dart';

void main() => runApp(const ${_pascal(name)}App());

class ${_pascal(name)}App extends StatelessWidget {
  const ${_pascal(name)}App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$name',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('$name (tvOS)')),
        body: const Center(child: Text('Running on Apple TV')),
      ),
    );
  }
}
''';

  String _widgetTest(String name) => '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:$name/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ${_pascal(name)}App());
    expect(find.text('Running on Apple TV'), findsOneWidget);
  });
}
''';

  String _analysisOptions() => '''
include: package:flutter_lints/flutter.yaml
''';

  String _gitignore() => '''
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
*.iml
.idea/
.DS_Store

# tvOS / CocoaPods
tvos/Pods/
tvos/Podfile.lock
tvos/.symlinks/
tvos/Flutter/Flutter.framework
''';

  String _readme(String name) => '''
# $name

A tvOS-only example app. Run it on an Apple TV simulator with:

```sh
flutter-tvos run
```
''';

  /// `url_launcher_tvos_example` → `UrlLauncherTvosExample`.
  String _pascal(String s) => s
      .split(RegExp(r'[_\- ]'))
      .where((String p) => p.isNotEmpty)
      .map((String p) => p[0].toUpperCase() + p.substring(1))
      .join();
}
