// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/tvos_releases.dart';

import '../src/common.dart';

void main() {
  group('TvosRelease.parse', () {
    test('splits a release tag into its Flutter and tool versions', () {
      final TvosRelease? r = TvosRelease.parse('v3.44.7-tvos.1.4.2');
      expect(r, isNotNull);
      expect(r!.tag, 'v3.44.7-tvos.1.4.2');
      expect(r.flutterVersion, '3.44.7');
      expect(r.toolVersion, '1.4.2');
      expect(r.hash, isNull);
    });

    test('trims surrounding whitespace', () {
      expect(TvosRelease.parse('  v3.44.7-tvos.1.4.2  ')!.tag, 'v3.44.7-tvos.1.4.2');
    });

    test('returns null for anything that is not a release tag', () {
      expect(TvosRelease.parse('nightly'), isNull);
      expect(TvosRelease.parse('latest'), isNull);
      expect(TvosRelease.parse('v3.44.1'), isNull); // plain Flutter-style tag
      expect(TvosRelease.parse('tvos.1.2.0'), isNull); // no v<flutter> prefix
      expect(TvosRelease.parse('v3.44.1-tvos.1.2'), isNull); // tool needs 3 parts
      expect(TvosRelease.parse('3.44.1-tvos.1.2.0'), isNull); // no leading v
      expect(TvosRelease.parse('v3.44.1-ios.1.2.0'), isNull); // wrong infix
    });

    test('accepts multi-digit version components', () {
      final TvosRelease? r = TvosRelease.parse('v10.0.0-tvos.12.34.56');
      expect(r!.flutterVersion, '10.0.0');
      expect(r.toolVersion, '12.34.56');
    });
  });

  group('TvosRelease.collapseToNewestPerFlutterVersion', () {
    // Newest-first, as `git tag -l --sort=-v:refname` produces. Mirrors the
    // real tag list, which has two tool releases for several Flutter versions.
    List<TvosRelease> parseAll(List<String> tags) =>
        tags.map(TvosRelease.parse).whereType<TvosRelease>().toList();

    test('keeps one entry per Flutter version, at its newest tool release', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>[
          'v3.44.7-tvos.1.4.2',
          'v3.44.5-tvos.1.4.0',
          'v3.44.5-tvos.1.3.3',
          'v3.32.8-tvos.1.0.0',
        ]),
      );

      expect(collapsed.map((TvosRelease r) => r.tag), <String>[
        'v3.44.7-tvos.1.4.2',
        'v3.44.5-tvos.1.4.0',
        'v3.32.8-tvos.1.0.0',
      ]);
    });

    test('preserves input order', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>['v3.44.7-tvos.1.4.2', 'v3.32.8-tvos.1.0.0']),
      );
      expect(collapsed.first.flutterVersion, '3.44.7');
      expect(collapsed.last.flutterVersion, '3.32.8');
    });

    test('returns an empty list for empty input', () {
      expect(TvosRelease.collapseToNewestPerFlutterVersion(<TvosRelease>[]), isEmpty);
    });
  });

  group('TvosRelease.withHash', () {
    test('attaches a commit without altering the other fields', () {
      final TvosRelease r = TvosRelease.parse('v3.32.8-tvos.1.0.0')!.withHash('cafebabe');
      expect(r.hash, 'cafebabe');
      expect(r.tag, 'v3.32.8-tvos.1.0.0');
      expect(r.flutterVersion, '3.32.8');
      expect(r.toolVersion, '1.0.0');
    });
  });
}
