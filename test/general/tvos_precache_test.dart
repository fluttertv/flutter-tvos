// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/precache.dart';

import '../src/common.dart';
import '../src/fakes.dart';

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
}
