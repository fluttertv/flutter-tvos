// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Phase 1 of tvOS Swift Package Manager support: `flutter-tvos plugin port`
// emits a `tvos/Package.swift` so the ported plugin is consumable via SPM
// (Flutter 3.44+ default) alongside its CocoaPods podspec, from one source
// tree. A single SwiftPM target can't mix languages, so the manifest is only
// emitted for Swift plugins; Objective-C / mixed plugins stay CocoaPods-only.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/plugin_porting/scaffolder.dart';
import 'package:flutter_tvos/plugin_porting/source_analyzer.dart';

import '../src/common.dart';

Directory _createSwiftPlugin(FileSystem fs) {
  final Directory dir = fs.directory('/src/gizmo_ios')..createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: gizmo_ios
description: iOS implementation of gizmo.
version: 1.2.3

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.13.0"

dependencies:
  flutter:
    sdk: flutter
  gizmo_platform_interface: ^1.0.0

flutter:
  plugin:
    implements: gizmo
    platforms:
      ios:
        pluginClass: GizmoPlugin
        dartPluginClass: GizmoIOS
''');
  dir
      .childDirectory('ios')
      .childDirectory('Classes')
      .childFile('GizmoPlugin.swift')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import Flutter
import UIKit

public class GizmoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
''');
  return dir;
}

Directory _createObjcPlugin(FileSystem fs) {
  final Directory dir = fs.directory('/src/widget_ios')..createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: widget_ios
description: iOS implementation of widget.
version: 0.5.0

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.13.0"

dependencies:
  flutter:
    sdk: flutter
  widget_platform_interface: ^1.0.0

flutter:
  plugin:
    implements: widget
    platforms:
      ios:
        pluginClass: WidgetPlugin
        dartPluginClass: WidgetIOS
''');
  final Directory classes = dir.childDirectory('ios').childDirectory('Classes')
    ..createSync(recursive: true);
  classes.childFile('WidgetPlugin.h').writeAsStringSync('''
#import <Flutter/Flutter.h>
@interface WidgetPlugin : NSObject <FlutterPlugin>
@end
''');
  classes.childFile('WidgetPlugin.m').writeAsStringSync('''
#import "WidgetPlugin.h"
@implementation WidgetPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {}
@end
''');
  return dir;
}

ScaffoldResult _port(FileSystem fs, Directory src, Directory out) {
  final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
  return Scaffolder(
    fileSystem: fs,
    logger: BufferLogger.test(),
    licenseHolder: 'Test',
  ).scaffold(source: source, outputDirectory: out);
}

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
  });

  group('plugin port — Package.swift (SPM)', () {
    test('Swift plugin gets a tvos/Package.swift with the right shape', () {
      final Directory out = fs.directory('/out/gizmo_tvos');
      _port(fs, _createSwiftPlugin(fs), out);

      final File manifest = out.childDirectory('tvos').childFile('Package.swift');
      expect(manifest.existsSync(), isTrue, reason: 'Swift plugins should be SPM-consumable');

      final String pkg = manifest.readAsStringSync();
      expect(pkg, startsWith('// swift-tools-version: 5.9'));
      // Product + target named after the output package.
      expect(pkg, contains('name: "gizmo_tvos"'));
      expect(pkg, contains('.library(name: "gizmo_tvos", targets: ["gizmo_tvos"])'));
      // tvOS platform, tvOS deployment floor.
      expect(pkg, contains('.tvOS(.v13)'));
      // Reuses the same sources the podspec compiles — no duplicated tree.
      expect(pkg, contains('path: "Classes"'));
      // Keeps Swift `#if TARGET_OS_TV` branches active under SwiftPM.
      expect(pkg, contains('.define("TARGET_OS_TV")'));
    });

    test('Package.swift sits beside the podspec and reuses Classes/', () {
      final Directory out = fs.directory('/out/gizmo_tvos');
      _port(fs, _createSwiftPlugin(fs), out);

      final Directory tvos = out.childDirectory('tvos');
      // Both dependency managers are present...
      expect(tvos.childFile('Package.swift').existsSync(), isTrue);
      expect(tvos.childFile('gizmo_tvos.podspec').existsSync(), isTrue);
      // ...pointing at the single shared source tree.
      expect(tvos.childDirectory('Classes').childFile('GizmoPlugin.swift').existsSync(), isTrue);
    });

    test('Objective-C plugin does NOT get a Package.swift (pods-only)', () {
      final Directory out = fs.directory('/out/widget_tvos');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(_createObjcPlugin(fs));
      // Sanity: the fixture really is Obj-C.
      expect(source.sourceLanguage, SourceLanguage.objc);

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out);

      expect(
        out.childDirectory('tvos').childFile('Package.swift').existsSync(),
        isFalse,
        reason: 'a single SwiftPM target cannot mix Swift + Obj-C',
      );
      // ...but the podspec is still generated, so the plugin still works.
      expect(out.childDirectory('tvos').childFile('widget_tvos.podspec').existsSync(), isTrue);
    });
  });
}
