// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/commands/upgrade.dart';

import '../src/common.dart';

void main() {
  group('TvosUpgradeCommandRunner.latestReleaseTag', () {
    // Mimics `git tag -l --sort=-v:refname` output: newest first.
    const realTags = <String>[
      'v3.44.1-tvos.1.2.0',
      'v3.44.0-tvos.1.1.1',
      'v3.44.0-tvos.1.1.0',
      'v3.41.9-tvos.1.1.0',
      'v3.41.9-tvos.1.0.1',
      'v3.41.4-tvos.1.0.0',
    ];

    test('picks the newest release tag from a version-sorted list', () {
      expect(TvosUpgradeCommandRunner.latestReleaseTag(realTags), 'v3.44.1-tvos.1.2.0');
    });

    test('ignores tags that are not flutter-tvos release tags', () {
      final tags = <String>[
        'nightly',
        'latest',
        'v3.44.1', // plain Flutter-style tag, not ours
        'tvos.1.2.0', // missing the v<flutter> prefix
        'v3.44.0-tvos.1.1.1', // first real match
        'v3.41.4-tvos.1.0.0',
      ];
      expect(TvosUpgradeCommandRunner.latestReleaseTag(tags), 'v3.44.0-tvos.1.1.1');
    });

    test('returns null when there are no release tags', () {
      expect(TvosUpgradeCommandRunner.latestReleaseTag(const <String>['nightly', 'foo']), isNull);
      expect(TvosUpgradeCommandRunner.latestReleaseTag(const <String>[]), isNull);
    });

    test('trims surrounding whitespace on the matched tag', () {
      expect(
        TvosUpgradeCommandRunner.latestReleaseTag(const <String>['  v3.44.1-tvos.1.2.0  ']),
        'v3.44.1-tvos.1.2.0',
      );
    });

    test('release tag pattern only matches the v<flutter>-tvos.<tool> shape', () {
      final RegExp p = TvosUpgradeCommandRunner.releaseTagPattern;
      expect(p.hasMatch('v3.44.1-tvos.1.2.0'), isTrue);
      expect(p.hasMatch('v10.0.0-tvos.12.34.56'), isTrue);
      expect(p.hasMatch('v3.44.1-tvos.1.2'), isFalse); // tool version needs 3 parts
      expect(p.hasMatch('3.44.1-tvos.1.2.0'), isFalse); // missing leading v
      expect(p.hasMatch('v3.44.1-ios.1.2.0'), isFalse); // wrong platform infix
    });
  });

  group('TvosVersion', () {
    test('label is the tag when tagged', () {
      const version = TvosVersion(hash: 'abcdef1234567890', tag: 'v3.44.1-tvos.1.2.0');
      expect(version.label, 'v3.44.1-tvos.1.2.0');
    });

    test('label falls back to the short hash when untagged', () {
      const version = TvosVersion(hash: 'abcdef1234567890', tag: null);
      expect(version.label, 'abcdef1234');
      expect(version.hashShort, 'abcdef1234');
    });

    test('hashShort tolerates a hash shorter than 10 chars', () {
      const version = TvosVersion(hash: 'abc123', tag: null);
      expect(version.hashShort, 'abc123');
    });
  });
}
