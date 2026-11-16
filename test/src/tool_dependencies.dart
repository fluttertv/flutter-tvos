// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The tool's dependencies, read from the test's context.
library;

import 'package:flutter_tools/src/android/android_sdk.dart';
import 'package:flutter_tools/src/android/android_studio.dart';
import 'package:flutter_tools/src/android/gradle_utils.dart';
import 'package:flutter_tools/src/android/java.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/build_targets.dart';
import 'package:flutter_tools/src/context/android_context.dart';
import 'package:flutter_tools/src/context/apple_context.dart';
import 'package:flutter_tools/src/context/tool_context.dart';
import 'package:flutter_tools/src/context/tool_dependencies.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/emulator.dart';
import 'package:flutter_tools/src/emulator.dart' as emulator show emulatorManager;
import 'package:flutter_tools/src/experimental/extension_build_manager.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/features.dart' as features show featureFlags;
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/ios/ios_workflow.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tools/src/ios/simulators.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tools/src/macos/cocoapods.dart';
import 'package:flutter_tools/src/macos/cocoapods_validator.dart';
import 'package:flutter_tools/src/macos/xcdevice.dart';
import 'package:flutter_tools/src/macos/xcode.dart';
import 'package:flutter_tools/src/reporting/crash_reporting.dart';
import 'package:test/fake.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'context.dart' show FakeDeviceManager, FakeXcodeProjectInterpreter;
import 'fakes.dart';

/// The [ToolDependencies] that `runner.run` would build from the current
/// context, for a test that builds commands itself.
///
/// Since Flutter 3.50 commands are given their services when they are made,
/// where before they read them from the context as they ran. Each service
/// here is read from the context when a command first asks for it, as before:
/// a `testUsingContext` override (a file system, a process manager, a logger,
/// a device manager, …) reaches a command as it did, and a service no command
/// uses is never looked up. A service the context does not hold is a fake.
///
/// Make and use it inside the test's context. No extension managers, as the
/// tool passes none.
ToolDependencies contextToolDependencies() => _ContextToolDependencies();

class _ContextToolDependencies implements ToolDependencies {
  @override
  Analytics get analytics => globals.analytics;

  @override
  final AndroidContext androidContext = _ContextAndroidContext();

  @override
  final AppleContext appleContext = _ContextAppleContext();

  @override
  BuildSystem get buildSystem => globals.buildSystem;

  @override
  BuildTargets? get buildTargets => globals.buildTargets;

  @override
  CrashReporter get crashReporter => globals.crashReporter ?? FakeCrashReporter();

  @override
  DeviceManager get deviceManager => globals.deviceManager ?? FakeDeviceManager();

  @override
  Doctor get doctor => globals.doctor ?? FakeDoctor();

  @override
  final EmulatorManager emulatorManager = _ContextEmulatorManager();

  @override
  ExtensionBuildManager? get extensionBuildManager => null;

  @override
  ExtensionManager? get extensionManager => null;

  @override
  FeatureFlags get featureFlags => features.featureFlags;

  @override
  ToolContext get toolContext => const DelegatingToolContext();
}

/// The context's [EmulatorManager], looked up when it is first used.
///
/// Stock's context builds one by looking for Android Studio and Java, which
/// runs processes; a test that never lists emulators does not expect those.
class _ContextEmulatorManager implements EmulatorManager {
  EmulatorManager get _manager => emulator.emulatorManager ?? FakeEmulatorManager();

  @override
  bool get canListAnything => _manager.canListAnything;

  @override
  Future<CreateEmulatorResult> createEmulator({String? name}) =>
      _manager.createEmulator(name: name);

  @override
  Future<List<Emulator>> getAllAvailableEmulators() => _manager.getAllAvailableEmulators();

  @override
  Future<List<Emulator>> getEmulatorsMatching(String searchText) =>
      _manager.getEmulatorsMatching(searchText);
}

class _ContextAndroidContext implements AndroidContext {
  @override
  AndroidSdk? get androidSdk => globals.androidSdk;

  @override
  AndroidStudio? get androidStudio => globals.androidStudio;

  @override
  GradleUtils get gradleUtils => globals.gradleUtils ?? FakeGradleUtils();

  @override
  Java? get java => globals.java;
}

class _ContextAppleContext implements AppleContext {
  @override
  CocoaPods get cocoaPods => globals.cocoaPods ?? FakeCocoaPods();

  @override
  CocoaPodsValidator get cocoapodsValidator =>
      globals.cocoapodsValidator ?? FakeCocoaPodsValidator();

  @override
  IOSSimulatorUtils get iosSimulatorUtils => globals.iosSimulatorUtils ?? FakeIOSSimulatorUtils();

  @override
  IOSWorkflow get iosWorkflow => globals.iosWorkflow ?? FakeIOSWorkflow();

  @override
  PlistParser get plistParser => globals.plistParser;

  @override
  XCDevice get xcdevice => globals.xcdevice ?? FakeXCDevice();

  @override
  Xcode get xcode => globals.xcode ?? _NoXcode();

  @override
  XcodeProjectInterpreter get xcodeProjectInterpreter =>
      globals.xcodeProjectInterpreter ?? FakeXcodeProjectInterpreter();
}

/// What a context with no [Xcode] stood for before commands were given one:
/// a Mac without Xcode, so a command skips its Xcode steps.
class _NoXcode extends Fake implements Xcode {
  @override
  bool get isInstalled => false;

  @override
  bool get isInstalledAndMeetsVersionCheck => false;
}
