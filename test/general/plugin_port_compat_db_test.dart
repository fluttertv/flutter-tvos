// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/plugin_porting/compatibility_database.dart';

import '../src/common.dart';

/// For every entry in [compatibilityDatabase], one line of Swift that should
/// match (a real use of the API) and one that should NOT (a similarly named
/// but allowed symbol). Keyed by [ApiPattern.name]. The test fails if a
/// pattern is added without a corresponding sample — a deliberate guard so
/// the database can't grow untested.
const Map<String, ({String positive, String negative})> _samples =
    <String, ({String positive, String negative})>{
  'WebKit': (
    positive: 'let webView = WKWebView(frame: .zero)',
    negative: 'let view = MyWebViewContainer()',
  ),
  'SafariServices': (
    positive: 'let vc = SFSafariViewController(url: url)',
    negative: 'let vc = SafariLikeController()',
  ),
  'UIPasteboard': (
    positive: 'UIPasteboard.general.string = value',
    negative: 'let p = CustomPasteboard()',
  ),
  'LocalAuthentication': (
    positive: 'let context = LAContext()',
    negative: 'let label = makeLabel()',
  ),
  'UIImagePicker': (
    positive: 'let picker = UIImagePickerController()',
    negative: 'let picker = ColorPickerController()',
  ),
  'CoreLocation': (
    positive: 'let manager = CLLocationManager()',
    negative: 'let manager = LocationServiceManager()',
  ),
  'Photos': (
    positive: 'PHPhotoLibrary.shared().performChanges({})',
    negative: 'let lib = AppPhotoStore()',
  ),
  'MailCompose': (
    positive: 'let mc = MFMailComposeViewController()',
    negative: 'let mc = MailDraftController()',
  ),
  'DocumentPicker': (
    positive: 'let dp = UIDocumentPickerViewController(forOpeningContentTypes: [])',
    negative: 'let dp = FileBrowserController()',
  ),
  'Haptics': (
    positive: 'let gen = UIImpactFeedbackGenerator(style: .medium)',
    negative: 'let gen = ScoreGenerator()',
  ),
  'StatusBar': (
    positive: 'app.setStatusBarHidden(true, with: .fade)',
    negative: 'updateStatusLabel(text)',
  ),
  'BackgroundFetch': (
    positive: 'BGTaskScheduler.shared.register(forTaskWithIdentifier: id)',
    negative: 'let task = AsyncWorkTask()',
  ),
  'UIApplication.open': (
    positive: 'UIApplication.shared.open(url, options: [:], completionHandler: nil)',
    negative: 'UIApplication.shared.canOpenURL(url)',
  ),
  'StoreKit': (
    positive: 'SKPaymentQueue.default().add(payment)',
    negative: 'let q = JobPaymentQueue()',
  ),
};

void main() {
  group('compatibilityDatabase', () {
    testWithoutContext('every entry has a unique name', () {
      final Set<String> names =
          compatibilityDatabase.map((ApiPattern p) => p.name).toSet();
      expect(names.length, compatibilityDatabase.length,
          reason: 'duplicate ApiPattern.name would shadow report findings');
    });

    testWithoutContext('every entry has a positive and negative sample', () {
      for (final ApiPattern p in compatibilityDatabase) {
        expect(
          _samples.containsKey(p.name),
          isTrue,
          reason:
              'No test sample for new pattern "${p.name}". Add one to _samples.',
        );
      }
    });

    testWithoutContext('every regex compiles', () {
      for (final ApiPattern p in compatibilityDatabase) {
        expect(() => RegExp(p.pattern), returnsNormally,
            reason: '${p.name} has an invalid regex');
      }
    });

    for (final ApiPattern p in compatibilityDatabase) {
      testWithoutContext('${p.name}: matches a real use, ignores look-alikes', () {
        final RegExp re = RegExp(p.pattern);
        final ({String negative, String positive}) s = _samples[p.name]!;
        expect(re.hasMatch(s.positive), isTrue,
            reason: '${p.name} regex should match: ${s.positive}');
        expect(re.hasMatch(s.negative), isFalse,
            reason: '${p.name} regex should NOT match: ${s.negative}');
      });
    }

    testWithoutContext('unsupported entries carry an explanatory note', () {
      for (final ApiPattern p in compatibilityDatabase) {
        expect(p.note.trim(), isNotEmpty, reason: '${p.name} has no note');
        if (p.severity == Severity.unsupported) {
          // Unsupported entries should explain the tvOS situation, not just
          // name the API — the note is surfaced verbatim in the report.
          expect(p.note.length, greaterThan(20), reason: '${p.name} note too thin');
        }
      }
    });
  });
}
