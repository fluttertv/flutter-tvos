// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/precache.dart';
import 'package:flutter_tvos/tvos_cache.dart';
import 'package:test/fake.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';
import '../src/test_flutter_command_runner.dart';

/// A [Cache] that records what it is asked to update and the host platform
/// override in force when the tvOS engine set is updated.
class _RecordingCache extends Fake implements Cache {
  HostPlatform? hostPlatformAtTvosUpdate;
  int tvosUpdates = 0;

  @override
  Future<void> lock() async {}

  @override
  void releaseLock() {}

  @override
  Future<void> updateAll(Set<DevelopmentArtifact> requiredArtifacts, {bool offline = false}) async {
    if (requiredArtifacts.contains(TvosDevelopmentArtifact.tvos)) {
      tvosUpdates++;
      hostPlatformAtTvosUpdate = osUtils.hostPlatformOverride;
    }
  }

  @override
  bool includeAllPlatforms = false;

  @override
  bool useUnsignedMacBinaries = false;

  @override
  final OperatingSystemUtils osUtils = FakeOperatingSystemUtils(
    hostPlatform: HostPlatform.darwin_arm64,
  );
}

void main() {
  // Builds the `isFlagOn` predicate the command passes, from a set of "on" flags.
  bool Function(String) flagsOn(Set<String> on) => (String name) => on.contains(name);

  Set<String> namesOf(Set<DevelopmentArtifact> artifacts) =>
      artifacts.map((DevelopmentArtifact a) => a.name).toSet();

  group('TvosPrecacheCommand.selectRequiredArtifacts', () {
    testWithoutContext('with no platform flags fetches only the universal/informative set — '
        'no Android, iOS, web, or macOS', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{}),
        ),
      );
      expect(names, containsAll(<String>['universal', 'informative']));
      expect(names, isNot(contains('ios')));
      expect(names, isNot(contains('android_gen_snapshot')));
      expect(names, isNot(contains('android_maven')));
      expect(names, isNot(contains('web')));
      expect(names, isNot(contains('macos')));
    });

    testWithoutContext('--ios adds the iOS artifact (and keeps the universal set)', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'ios'}),
        ),
      );
      expect(names, contains('ios'));
      expect(names, containsAll(<String>['universal', 'informative']));
      expect(names, isNot(contains('macos')));
    });

    testWithoutContext('--android expands to all three android child artifacts', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'android'}),
        ),
      );
      expect(
        names,
        containsAll(<String>['android_gen_snapshot', 'android_maven', 'android_internal_build']),
      );
    });

    testWithoutContext('an individual android child flag is honored on its own, without '
        'pulling in its siblings', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'android_maven'}),
        ),
      );
      expect(names, contains('android_maven'));
      expect(names, isNot(contains('android_gen_snapshot')));
    });

    testWithoutContext('a feature-gated platform is skipped when its feature is disabled, '
        'even if its flag is set', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'web'}),
        ),
      );
      expect(names, isNot(contains('web')));
    });

    testWithoutContext('a feature-enabled platform with its flag set is included', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(isWebEnabled: true),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'web'}),
        ),
      );
      expect(names, contains('web'));
    });

    testWithoutContext('--all-platforms includes every feature-enabled artifact', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(isWebEnabled: true, isMacOSEnabled: true),
          allPlatforms: true,
          isFlagOn: flagsOn(<String>{}),
        ),
      );
      expect(
        names,
        containsAll(<String>['ios', 'web', 'macos', 'universal', 'informative']),
      );
    });

    testWithoutContext('a disabled iOS feature excludes iOS even from the default set', () {
      final Set<String> names = namesOf(
        TvosPrecacheCommand.selectRequiredArtifacts(
          featureFlags: TestFeatureFlags(isIOSEnabled: false),
          allPlatforms: false,
          isFlagOn: flagsOn(<String>{'ios'}),
        ),
      );
      expect(names, isNot(contains('ios')));
    });
  });

  // Stock's --host-arch arrived with Flutter 3.50. The tvOS command replaces
  // stock's runCommand, so it has to take the flag itself, and set it before
  // its first download (the tvOS engine set), as stock sets it before its own.
  group('TvosPrecacheCommand --host-arch', () {
    late _RecordingCache cache;
    late FakePlatform platform;

    setUp(() {
      cache = _RecordingCache();
      platform = FakePlatform(
        operatingSystem: 'macos',
        environment: <String, String>{'FLUTTER_ALREADY_LOCKED': 'true'},
      );
    });

    Future<void> runPrecache(List<String> args) => createTestCommandRunner(
      TvosPrecacheCommand(
        verboseHelp: false,
        cache: cache,
        logger: BufferLogger.test(),
        platform: platform,
        featureFlags: TestFeatureFlags(),
      ),
    ).run(<String>['precache', ...args]);

    final overrides = <Type, Generator>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any(),
      Platform: () => platform,
      Cache: () => cache,
    };

    testUsingContext('picks the host artifacts before the tvOS engine is downloaded', () async {
      await runPrecache(const <String>['--host-arch', 'x64']);

      expect(cache.tvosUpdates, 1);
      expect(cache.hostPlatformAtTvosUpdate, HostPlatform.darwin_x64);
    }, overrides: overrides);

    testUsingContext('leaves the host platform alone without the flag', () async {
      await runPrecache(const <String>[]);

      expect(cache.tvosUpdates, 1);
      expect(cache.hostPlatformAtTvosUpdate, isNull);
    }, overrides: overrides);
  });
}
