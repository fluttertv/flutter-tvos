// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/user_messages.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/doctor_validator.dart';
import 'package:process/process.dart';

TvosWorkflow? get tvosWorkflow => context.get<TvosWorkflow>();
TvosValidator? get tvosValidator => context.get<TvosValidator>();

/// See: [_DefaultDoctorValidatorsProvider] in `doctor.dart`
class TvosDoctorValidatorsProvider implements DoctorValidatorsProvider {
  @override
  List<DoctorValidator> get validators {
    final List<DoctorValidator> validators =
        DoctorValidatorsProvider.defaultInstance.validators;
    return <DoctorValidator>[
      validators.first,
      tvosValidator!,
      ...validators.sublist(1)
    ];
  }

  @override
  List<Workflow> get workflows => <Workflow>[
        ...DoctorValidatorsProvider.defaultInstance.workflows,
        tvosWorkflow!,
      ];
}

class TvosValidator extends DoctorValidator {
  TvosValidator({
    required ProcessManager processManager,
    required UserMessages userMessages,
  })  : _processManager = processManager,
        super('tvOS toolchain - develop for Apple tvOS devices');

  final ProcessManager _processManager;

  @override
  Future<ValidationResult> validate() async {
    ValidationType validationType = ValidationType.success;
    final List<ValidationMessage> messages = <ValidationMessage>[];

    // 1. Check Xcode installation
    final bool xcodeOk = await _checkXcode(messages);
    if (!xcodeOk) {
      return ValidationResult(ValidationType.missing, messages);
    }

    // 2. Check tvOS SDK
    await _checkTvosSdk(messages);

    // 3. Check tvOS Simulator runtime
    await _checkSimulatorRuntime(messages);

    // 4. Check CocoaPods
    await _checkCocoaPods(messages);

    // 5. Check engine artifacts
    await _checkEngineArtifacts(messages);

    // Determine overall status from messages
    final bool hasErrors = messages.any(
      (ValidationMessage m) => m.type == ValidationMessage.error('').type,
    );
    final bool hasHints = messages.any(
      (ValidationMessage m) => m.type == ValidationMessage.hint('').type,
    );

    if (hasErrors) {
      validationType = ValidationType.partial;
    } else if (hasHints) {
      validationType = ValidationType.success;
    }

    return ValidationResult(validationType, messages);
  }

  /// Checks that Xcode is installed and reports its version.
  Future<bool> _checkXcode(List<ValidationMessage> messages) async {
    try {
      final ProcessResult result = await _processManager.run(<String>[
        'xcodebuild', '-version',
      ]);
      if (result.exitCode == 0) {
        final String version = (result.stdout as String).split('\n').first;
        messages.add(ValidationMessage('Xcode installed ($version)'));
        return true;
      }
    } on ProcessException {
      // ignore
    }

    messages.add(const ValidationMessage.error(
      'Xcode is not installed. Install it from the Mac App Store.\n'
      'Xcode is required for tvOS development.',
    ));
    return false;
  }

  /// Checks that the tvOS SDK is available in Xcode.
  Future<void> _checkTvosSdk(List<ValidationMessage> messages) async {
    try {
      final ProcessResult result = await _processManager.run(<String>[
        'xcrun', '--sdk', 'appletvos', '--show-sdk-path',
      ]);
      if (result.exitCode == 0) {
        final String sdkPath = (result.stdout as String).trim();
        // Extract version from path like .../AppleTVOS17.0.sdk
        final RegExp versionRegex = RegExp(r'AppleTVOS(\d+\.\d+)\.sdk');
        final Match? match = versionRegex.firstMatch(sdkPath);
        final String version = match != null ? ' ${match.group(1)}' : '';
        messages.add(ValidationMessage('tvOS SDK$version installed'));
        return;
      }
    } on ProcessException {
      // ignore
    }

    messages.add(const ValidationMessage.error(
      'tvOS SDK not found. Open Xcode → Settings → Platforms → download tvOS.',
    ));
  }

  /// Checks that at least one tvOS Simulator runtime is installed.
  Future<void> _checkSimulatorRuntime(List<ValidationMessage> messages) async {
    try {
      final ProcessResult result = await _processManager.run(<String>[
        'xcrun', 'simctl', 'list', 'runtimes', '--json',
      ]);
      if (result.exitCode == 0) {
        final String stdout = result.stdout as String;
        // Simple check: look for tvOS in the runtime list
        if (stdout.contains('tvOS') || stdout.contains('com.apple.CoreSimulator.SimRuntime.tvOS')) {
          // Extract latest tvOS version
          final RegExp versionRegex = RegExp(r'"name"\s*:\s*"tvOS (\d+\.\d+)"');
          final Iterable<Match> matches = versionRegex.allMatches(stdout);
          if (matches.isNotEmpty) {
            final String latest = matches.last.group(1)!;
            messages.add(ValidationMessage('tvOS Simulator runtime (tvOS $latest)'));
          } else {
            messages.add(const ValidationMessage('tvOS Simulator runtime installed'));
          }
          return;
        }
      }
    } on ProcessException {
      // ignore
    }

    messages.add(const ValidationMessage.error(
      'No tvOS Simulator runtime found. Open Xcode → Settings → Platforms → download tvOS Simulator.',
    ));
  }

  /// Checks that CocoaPods is installed (needed for plugin support).
  Future<void> _checkCocoaPods(List<ValidationMessage> messages) async {
    try {
      final ProcessResult result = await _processManager.run(<String>[
        'pod', '--version',
      ]);
      if (result.exitCode == 0) {
        final String version = (result.stdout as String).trim();
        messages.add(ValidationMessage('CocoaPods $version'));
        return;
      }
    } on ProcessException {
      // ignore
    }

    messages.add(const ValidationMessage.hint(
      'CocoaPods not installed. Install with: brew install cocoapods\n'
      'CocoaPods is required for plugins with native tvOS code.',
    ));
  }

  /// Checks that tvOS engine artifacts are present.
  Future<void> _checkEngineArtifacts(List<ValidationMessage> messages) async {
    try {
      // Use `which flutter-tvos` or check known artifact paths
      // For now, check if the precache command would find artifacts
      final ProcessResult result = await _processManager.run(<String>[
        'ls', '-d',
        // This path is relative to the CLI root
        'engine_artifacts/tvos_debug_sim_arm64',
      ]);
      if (result.exitCode == 0) {
        messages.add(const ValidationMessage('tvOS engine artifacts present'));
        return;
      }
    } on ProcessException {
      // ignore
    }

    messages.add(const ValidationMessage.hint(
      'tvOS engine artifacts not found. Run: flutter-tvos precache',
    ));
  }

  @override
  Future<ValidationResult> validateImpl() async {
    return validate();
  }
}

/// The tvOS-specific implementation of a [Workflow].
class TvosWorkflow extends Workflow {
  TvosWorkflow({
    required OperatingSystemUtils operatingSystemUtils,
  }) : _operatingSystemUtils = operatingSystemUtils;

  final OperatingSystemUtils _operatingSystemUtils;

  @override
  bool get appliesToHostPlatform =>
      _operatingSystemUtils.hostPlatform == HostPlatform.darwin_x64 ||
      _operatingSystemUtils.hostPlatform == HostPlatform.darwin_arm64;

  @override
  bool get canLaunchDevices => true;

  @override
  bool get canListDevices => true;

  @override
  bool get canListEmulators => true;
}
