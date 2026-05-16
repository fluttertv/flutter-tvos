// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/tvos_platform_args.dart';

import '../src/common.dart';

void main() {
  group('expandTvosPlatformArgs', () {
    test('leaves non-create argv untouched', () {
      final List<String> a = <String>['build', 'tvos', '--platforms=tvos'];
      expect(expandTvosPlatformArgs(a), same(a));
    });

    test('leaves create without --platforms untouched', () {
      final List<String> a = <String>['create', '--org', 'com.x', '.'];
      expect(expandTvosPlatformArgs(a), same(a));
    });

    test('leaves create --platforms=ios (no tvos) untouched', () {
      final List<String> a = <String>['create', '--platforms=ios', '.'];
      expect(expandTvosPlatformArgs(a), same(a));
    });

    test('--platforms=tvos → minimal ios scaffold + --tvos-only', () {
      expect(
        expandTvosPlatformArgs(<String>['create', '--platforms=tvos', '--org', 'com.x', '.']),
        <String>['create', '--org', 'com.x', '.', '--platforms=ios', '--tvos-only'],
      );
    });

    test('--platforms tvos (space form) is handled', () {
      expect(
        expandTvosPlatformArgs(<String>['create', '--platforms', 'tvos', '.']),
        <String>['create', '.', '--platforms=ios', '--tvos-only'],
      );
    });

    test('--platforms=tvos,ios keeps ios, drops tvos, no strip', () {
      expect(
        expandTvosPlatformArgs(<String>['create', '--platforms=tvos,ios', '.']),
        <String>['create', '.', '--platforms=ios'],
      );
    });

    test('repeated --platforms tokens are merged', () {
      expect(
        expandTvosPlatformArgs(
            <String>['create', '--platforms', 'tvos', '--platforms', 'macos', '.']),
        <String>['create', '.', '--platforms=macos'],
      );
    });

    test('preserves all other create args and their order', () {
      final List<String> got = expandTvosPlatformArgs(<String>[
        '--suppress-analytics',
        'create',
        '--project-name',
        'foo_example',
        '--platforms=tvos',
        '--org',
        'com.example',
        '.',
      ]);
      expect(got, <String>[
        '--suppress-analytics',
        'create',
        '--project-name',
        'foo_example',
        '--org',
        'com.example',
        '.',
        '--platforms=ios',
        '--tvos-only',
      ]);
    });
  });
}
