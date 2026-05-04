// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Pattern table mapping iOS / macOS APIs that don't exist on tvOS to their
/// status and human-readable explanation.
///
/// This is the data side of the Phase 3 Swift / Objective-C porter. The
/// transformer scans each line of a copied native source file against every
/// entry here and:
///   * `Severity.unsupported` → strips the matching import line if it's an
///     `import …`, otherwise stubs the enclosing `case "…":` body and
///     records a finding.
///   * `Severity.partial` → leaves the code in place and records a finding
///     so the report flags it for manual review.
///   * `Severity.info` → records a finding without modifying anything.
///
/// Adding patterns is intentionally pure-data: don't touch the porter or
/// the report emitter, just append to [compatibilityDatabase]. Patterns
/// are evaluated in declaration order; tightly-scoped patterns should
/// come before broader ones if a single line might match multiple entries
/// (today every entry is independent so order doesn't matter).
library;

/// How severely an API affects the port.
enum Severity {
  /// The API doesn't exist on tvOS. Code referencing it cannot compile or
  /// run; the porter stubs the enclosing handler with
  /// `result(FlutterMethodNotImplemented)` and records a finding.
  unsupported,

  /// The API compiles on tvOS but behaves differently or has a narrower
  /// surface (e.g. `UIApplication.open` accepts fewer URL schemes). Code
  /// is left in place; the report flags it so the user reviews each
  /// occurrence.
  partial,

  /// Worth flagging in the report but not enough to alter behaviour. Used
  /// for patterns where the user might want to know about a quirk but
  /// where leaving the code unchanged is the right default.
  info,
}

/// One iOS-API pattern in the compatibility database.
class ApiPattern {
  const ApiPattern({
    required this.name,
    required this.pattern,
    required this.severity,
    required this.note,
    this.stripImports = const <String>[],
  });

  /// Short, human-readable label that goes into the porting report
  /// (e.g. `WebKit`, `UIPasteboard`).
  final String name;

  /// Regex evaluated against each line of the source. We intentionally use
  /// String here (not RegExp) so the database is `const`-able. The porter
  /// compiles each entry once at startup.
  final String pattern;

  /// How the porter should react when [pattern] matches.
  final Severity severity;

  /// Multi-line note attached to each finding. Should explain why the API
  /// is unsupported and either suggest a tvOS replacement or explain why
  /// the feature must be omitted on tvOS.
  final String note;

  /// Optional list of import lines (without the trailing newline) that
  /// should be stripped from the file when [pattern] is detected. Lets
  /// us drop, e.g., `import WebKit` when any `WKWebView` reference is
  /// found in the file.
  ///
  /// The porter does an exact-line match against trimmed source lines,
  /// so each entry should be the literal `import` directive.
  final List<String> stripImports;
}

/// The database. Append-only; existing entries should not be removed when
/// a tvOS API gap closes — instead set the severity to [Severity.info] and
/// note the version it became available, so users porting on older OS
/// targets still see the warning.
const List<ApiPattern> compatibilityDatabase = <ApiPattern>[
  ApiPattern(
    name: 'WebKit',
    pattern: r'\bWKWebView\b|\bWKNavigationDelegate\b|\bWKWebViewConfiguration\b',
    severity: Severity.unsupported,
    note:
        'WebKit is not available on tvOS. Apps that need to render web content '
        'typically either use AVPlayer for video URLs (https://developer.apple.com/'
        'documentation/avfoundation/avplayer) or omit the feature on tvOS. '
        'Hand off the URL to `UIApplication.shared.open(url)` for the rare '
        'cases where another app on the device claims it.',
    stripImports: <String>['import WebKit'],
  ),
  ApiPattern(
    name: 'SafariServices',
    pattern: r'\bSFSafariViewController\b|\bSFAuthenticationSession\b|\bASWebAuthenticationSession\b',
    severity: Severity.unsupported,
    note:
        'SafariServices and AuthenticationServices web auth APIs are not '
        'available on tvOS. For OAuth-style flows, use a device-pairing model '
        '(QR code on TV, browser on phone) rather than an in-app browser.',
    stripImports: <String>[
      'import SafariServices',
      'import AuthenticationServices',
    ],
  ),
  ApiPattern(
    name: 'UIPasteboard',
    pattern: r'\bUIPasteboard\b',
    severity: Severity.unsupported,
    note:
        'tvOS has no pasteboard. The system focus engine handles text input '
        'through a virtual keyboard; copy/paste is not a user-facing concept. '
        'Stubbing copy/paste handlers is safe — apps that exercise them on '
        'tvOS should branch on `Platform.isTvOS` and disable the UI.',
  ),
  ApiPattern(
    name: 'LocalAuthentication',
    pattern: r'\bLAContext\b|\bLAPolicy\b',
    severity: Severity.unsupported,
    note:
        'tvOS has no biometric authentication. Use a remote-pairing flow if '
        'you need user identity (e.g. a sign-in code displayed on the TV that '
        'the user enters in a phone app).',
    stripImports: <String>['import LocalAuthentication'],
  ),
  ApiPattern(
    name: 'UIImagePicker',
    pattern: r'\bUIImagePickerController\b|\bPHPickerViewController\b',
    severity: Severity.unsupported,
    note:
        'tvOS has no camera and no Photos library. Plugins that surface those '
        'features should be no-ops or return errors on tvOS — your iOS users '
        'have phones for this.',
    stripImports: <String>['import PhotosUI'],
  ),
  ApiPattern(
    name: 'CoreLocation',
    pattern: r'\bCLLocationManager\b|\bCLLocation\b',
    severity: Severity.unsupported,
    note:
        'tvOS does not expose location services. The framework header still '
        'exists but every API call returns errors. If location is critical to '
        'your plugin, consider falling back to IP-geolocation via a network '
        'call (Dart-side, not a native plugin concern).',
    stripImports: <String>['import CoreLocation'],
  ),
  ApiPattern(
    name: 'Photos',
    pattern: r'\bPHPhotoLibrary\b|\bPHAsset\b|\bPHFetchResult\b',
    severity: Severity.unsupported,
    note:
        'No Photos library on tvOS. See `UIImagePicker` for the same reason.',
    stripImports: <String>['import Photos'],
  ),
  ApiPattern(
    name: 'MailCompose',
    pattern: r'\bMFMailComposeViewController\b|\bMFMessageComposeViewController\b',
    severity: Severity.unsupported,
    note:
        'tvOS has no mail or messages composition UI. Shell out to a phone '
        'companion app or omit the feature.',
    stripImports: <String>[
      'import MessageUI',
    ],
  ),
  ApiPattern(
    name: 'DocumentPicker',
    pattern: r'\bUIDocumentPickerViewController\b|\bUIDocumentInteractionController\b',
    severity: Severity.unsupported,
    note: 'No filesystem UI on tvOS. Apps cannot present a file browser.',
  ),
  ApiPattern(
    name: 'Haptics',
    pattern: r'\bUIFeedbackGenerator\b|\bUIImpactFeedbackGenerator\b'
        r'|\bUINotificationFeedbackGenerator\b|\bUISelectionFeedbackGenerator\b',
    severity: Severity.unsupported,
    note: 'No haptic feedback on Apple TV remotes. The Siri Remote does not '
        'vibrate.',
  ),
  ApiPattern(
    name: 'StatusBar',
    pattern: r'\bsetStatusBarHidden\b|\bstatusBarStyle\b|\bstatusBarOrientation\b',
    severity: Severity.unsupported,
    note:
        'tvOS has no status bar. Setters compile (UIApplication has the '
        'declarations) but have no visible effect; the porter strips them so '
        'callers do not silently rely on broken behaviour.',
  ),
  ApiPattern(
    name: 'BackgroundFetch',
    pattern: r'\bBGTaskScheduler\b|\bBGAppRefreshTask\b|\bUIBackgroundModes\b',
    severity: Severity.unsupported,
    note:
        'tvOS does not run background tasks the way iOS does — the OS '
        'aggressively reaps Apple TV apps when not in foreground. Background '
        'work has to happen via the foreground UI or a network-side service.',
    stripImports: <String>['import BackgroundTasks'],
  ),
  // ---------------------------------------------------------------------
  // `partial` entries — these compile on tvOS but behave differently or
  // have a narrower API surface. Don't strip imports or stub method
  // bodies; just flag for manual review.
  // ---------------------------------------------------------------------
  ApiPattern(
    name: 'UIApplication.open',
    pattern: r'UIApplication\.shared\.open\(',
    severity: Severity.partial,
    note:
        'tvOS supports a much narrower set of URL schemes than iOS. http(s) '
        'URLs that hand off to AVPlayer-handled video usually work; most '
        'app schemes are blocked by the OS and `open(_:options:completionHandler:)` '
        'returns false. Test each URL scheme your plugin advertises.',
  ),
  ApiPattern(
    name: 'StoreKit',
    pattern: r'\bSKPaymentQueue\b|\bSKProduct\b|\bSKReceiptRefreshRequest\b',
    severity: Severity.partial,
    note:
        'StoreKit exists on tvOS but with a different transaction surface — '
        'subscriptions, family-sharing, and consumable purchases all work, '
        'but UI elements (`SKStoreProductViewController`, '
        '`SKStoreReviewController`) behave differently or are missing. '
        'Audit each StoreKit call site by hand.',
  ),
];
