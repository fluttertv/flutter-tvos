# `flutter-tvos plugin port` — design and implementation reference

This document is the canonical spec the implementation follows. It is split into
phases; each phase is independently shippable and testable.

> **Status snapshot**: Phases 1–3 implemented — scaffolding, verbatim native
> copy, and the Swift transformer (compatibility database, import stripping,
> method-handler stubbing) with `PORTING_REPORT.md` generation and the
> `--no-report` flag. Phases 4–7 follow the staging in §10. One deviation
> from §6.1: header-comment regeneration (§6.1.6) is **not** yet implemented
> — the porter preserves the source header verbatim. Anything else in this
> doc that is contradicted by the code on `main` should be treated as the
> doc being out of date — fix the doc.

---

## 1. Goals and non-goals

### Goals

- One-shot scaffolding: `flutter-tvos plugin port <source>` produces a complete
  `*_tvos` package that **builds**, passes `dart analyze`, and passes
  `dart test` out of the box.
- Federated layout: produces a sibling package that the original plugin (or
  consumers) depend on. The original is never modified.
- Conventions enforced: every output follows the FlutterTV plugin standards
  documented in `flutter-tvos/CLAUDE.md` and `packages/flutter_tvos/CLAUDE.md`.
- Reusable by three audiences:
  - **Us** — building out the FlutterTV plugin index.
  - **Plugin maintainers** — adding tvOS as a federated platform alongside
    existing iOS/macOS implementations.
  - **Third-party contributors** — porting a plugin they depend on without
    forking the upstream package.
- Honest about limits: emits a structured "manual review needed" report listing
  every iOS API the source uses that doesn't exist on tvOS, with replacement
  suggestions where one exists.

### Non-goals

- **No** automatic translation of UIKit/AppKit APIs to tvOS equivalents
  (LLM-territory; non-deterministic; produces silently-broken code). Unsupported
  method calls are stubbed with `FlutterMethodNotImplemented` and listed in the
  porting report. The human decides what to do.
- **No** publishing. The command writes to disk; pushing to git or pub.dev stays
  manual.
- **No** pure-Dart plugin port. Pure-Dart plugins federate through the platform
  interface and need no `*_tvos` package; the command detects this and exits
  with a friendly message.

---

## 2. CLI surface

```
flutter-tvos plugin port <source> [options]

Sources:
  <path>                     Local directory containing a plugin or *_ios/*_macos package.
  --from-pub <name>          Download a published package as the source.       [phase 6]
  --from-git <url> [--ref X] Clone a git repo and use it as the source.        [phase 6]

Options:
  --output, -o <dir>         Output directory. Default: sibling of <source>,
                             named `<plugin>_tvos`.
  --base-platform <ios|macos>
                             Which existing implementation to model the port on.
                             Default prefers `ios`, falls back to `macos`.
  --include-example          Add `example/tvos/` to the source plugin's example
                             app (writes to the source repo, never the *_tvos
                             package itself).                                   [phase 5]
  --dry-run                  Print everything that would happen, write nothing.
  --no-report                Skip writing PORTING_REPORT.md (still generates code).
  --license-holder "<text>"  Copyright holder line for new files.
  --org com.example          Bundle ID prefix for the example app
                             (only with --include-example).
  --force                    Overwrite the output directory if it already exists.
```

### Examples

```bash
# Local checkout, default everything
flutter-tvos plugin port ../url_launcher/packages/url_launcher_ios

# Custom output, also generate example/tvos/
flutter-tvos plugin port --from-pub shared_preferences_foundation \
                        --output ./shared_preferences_tvos \
                        --include-example

# Use macOS code as the base when iOS is missing/awkward
flutter-tvos plugin port ../path_provider/packages/path_provider_foundation \
                        --base-platform macos

# Dry run on a complex plugin to see what would need manual review
flutter-tvos plugin port --from-git https://github.com/foo/audio_session --dry-run
```

---

## 3. Output package layout

```
<plugin>_tvos/
├── CHANGELOG.md                  ← seeded with "0.0.1 - Initial tvOS support"
├── LICENSE                       ← copied from source if BSD/MIT/Apache, else our default
├── README.md                     ← templated, links back to the source plugin
├── analysis_options.yaml         ← `package:flutter_lints/flutter.yaml`
├── pubspec.yaml                  ← rewritten (§5)
├── lib/
│   └── <plugin>_tvos.dart        ← Dart `registerWith()` + base class extending the
│                                   platform interface
├── tvos/
│   ├── Classes/
│   │   ├── <PluginClass>Plugin.swift       (or .m/.h pair if source is ObjC)
│   │   └── <PluginClass>Plugin-Bridging-Header.h    (Swift only)
│   ├── Resources/                ← copied if source has any
│   └── <plugin>_tvos.podspec     ← podspec for tvOS 13+
├── test/
│   └── <plugin>_tvos_test.dart   ← golden test that registerWith() runs and the
│                                   platform interface identity is set correctly
├── PORTING_REPORT.md             ← generated; lists every TODO and iOS-only call site (§7)
└── .gitignore
```

If `--include-example` is set, the porter ALSO writes:

```
<source-or-its-app-package>/example/
└── tvos/                         ← created via `flutter-tvos create` in the existing example
                                    dir; only this directory is written. lib/, pubspec.yaml,
                                    ios/, etc. stay untouched.
```

---

## 4. Source detection and validation

Before any output is written, the porter validates and inspects the source:

| Check | Behaviour |
|---|---|
| Source dir exists, has `pubspec.yaml` | required; abort with message if not |
| `flutter.plugin` key present | required; pure-Dart packages → friendly message and exit 0 |
| `flutter.plugin.platforms.ios` or `.macos` exists | required; if neither, abort with "no native iOS/macOS implementation found" |
| Source is itself a `*_tvos` package | abort: "source already targets tvOS" |
| Source's package name | parse for naming the output (`url_launcher_ios` → `url_launcher_tvos`; `path_provider_foundation` → `path_provider_tvos`; `audio_session` → `audio_session_tvos`) |
| Plugin class name | read from `flutter.plugin.platforms.<platform>.pluginClass` |
| Dart plugin class | read from `flutter.plugin.platforms.<platform>.dartPluginClass` if present |
| Native source language | scan `ios/Classes/` (or `macos/Classes/`); decide Swift vs ObjC |
| Platform interface package | parse from imports in `lib/`; e.g. `url_launcher_platform_interface` |

The porter prints a one-screen summary of what it detected before writing
anything (interactive `Continue? [Y/n]` prompt; `--force` skips, `--dry-run`
stops here).

---

## 5. `pubspec.yaml` rewrite

| Field | Output |
|---|---|
| `name` | `<base>_tvos` (e.g. `url_launcher_tvos`) |
| `description` | append "tvOS implementation of …" |
| `version` | reset to `0.0.1` |
| `repository` / `homepage` | replaced with the FlutterTV org URL (or `--license-holder`-derived) |
| `environment.sdk` | copied unchanged |
| `environment.flutter` | copied unchanged |
| `dependencies.flutter` | copied unchanged |
| `dependencies.<plugin>_platform_interface` | copied unchanged (we depend on the same interface) |
| `dependencies` (others) | iOS-implementation-specific ones removed (e.g. a dep on `url_launcher_macos` would not carry over) |
| `dev_dependencies.flutter_lints` | copied unchanged |
| `flutter.plugin.platforms.ios` | dropped |
| `flutter.plugin.platforms.macos` | dropped |
| `flutter.plugin.platforms.tvos` | added with `pluginClass` (Swift class) and `dartPluginClass` |

The `dartPluginClass` line matters for federated registration. Without it, the
user-facing package needs `default_package: <plugin>_tvos`.

---

## 6. Native code rewriting

### 6.1 Swift transformer

1. **Imports**: kept; iOS-only frameworks (WebKit, SafariServices,
   LocalAuthentication, etc.) stripped.
2. **Class declaration**: copied as-is.
3. **`register(with:)`**: copied verbatim. Channel name unchanged so the tvOS
   impl listens on the SAME channel as the iOS impl — apps that import the
   user-facing plugin work without changes.
4. **`handle(_:result:)`**: every method case is scanned against the
   compatibility database (§6.3). Matches → original body commented with
   `// TODO(porter):`, `result(FlutterMethodNotImplemented); return` inserted,
   case recorded in the report.
5. **Supporting types/extensions**: copied verbatim with the same scan.
6. **Header comment**: replaced with FlutterTV BSD header + porter version stamp.

### 6.2 Objective-C transformer

Same logic on `.h` / `.m` pairs. UIKit `#import` lines kept;
`<WebKit/WebKit.h>`, `<SafariServices/...>`, `<LocalAuthentication/...>`
stripped. `+ (void)registerWithRegistrar:` copied as-is.

### 6.3 Compatibility database

`lib/plugin_porting/compatibility_database.dart` is a pure-data table:

```dart
const compatibilityDatabase = <ApiPattern>[
  ApiPattern(
    pattern: r'\bWKWebView\b|<WebKit/',
    severity: Severity.unsupported,
    note: 'WebKit is not available on tvOS. Apps that need in-app browsers '
          'typically use AVPlayerViewController for video URLs or omit the '
          'feature on tvOS.',
  ),
  ApiPattern(
    pattern: r'UIPasteboard',
    severity: Severity.unsupported,
    note: 'Clipboard is not available on tvOS.',
  ),
  ApiPattern(
    pattern: r'LAContext|LocalAuthentication',
    severity: Severity.unsupported,
    note: 'tvOS does not have biometric auth.',
  ),
  ApiPattern(
    pattern: r'UIImagePickerController',
    severity: Severity.unsupported,
    note: 'No camera or photo library on tvOS.',
  ),
  ApiPattern(
    pattern: r'MFMailComposeViewController|MFMessageComposeViewController',
    severity: Severity.unsupported,
    note: 'Mail/Messages composition is not available on tvOS.',
  ),
  ApiPattern(
    pattern: r'SFSafariViewController|SFAuthenticationSession',
    severity: Severity.unsupported,
    note: 'Use a native AVPlayer flow or external-only URLs.',
  ),
  ApiPattern(
    pattern: r'UIApplication\.open\([^)]*options',
    severity: Severity.partial,
    note: 'tvOS supports a narrower set of URL schemes than iOS. http(s) '
          'often works for AVPlayer-handled video; many app schemes are '
          'blocked by the OS. Test each scheme.',
  ),
  ApiPattern(
    pattern: r'UIDocumentPickerViewController',
    severity: Severity.unsupported,
    note: 'No filesystem UI on tvOS.',
  ),
  ApiPattern(
    pattern: r'UIFeedbackGenerator|UIImpactFeedbackGenerator|UINotificationFeedbackGenerator',
    severity: Severity.unsupported,
    note: 'No haptics on Apple TV.',
  ),
  ApiPattern(
    pattern: r'\bUIApplication\.shared\.statusBarStyle\b|setStatusBarHidden',
    severity: Severity.unsupported,
    note: 'No status bar on tvOS.',
  ),
  ApiPattern(
    pattern: r'CLLocationManager|<CoreLocation/',
    severity: Severity.unsupported,
    note: 'Location services are not available on tvOS.',
  ),
  ApiPattern(
    pattern: r'PHPhotoLibrary|<Photos/',
    severity: Severity.unsupported,
    note: 'No Photos library on tvOS.',
  ),
  // (extend as we encounter more in real plugins)
];
```

Each pattern has a regex, a severity (`unsupported` → fully stub; `partial` →
keep code but emit warning; `info` → just note), an optional replacement
snippet, and a human-readable note for the report. Adding patterns doesn't
touch parsing code — pure data.

### 6.4 Podspec generation

```ruby
Pod::Spec.new do |s|
  s.name                = '<plugin>_tvos'
  s.version             = '0.0.1'
  s.summary             = 'tvOS implementation of <plugin>.'
  s.description         = <<-DESC
                          tvOS implementation of <plugin>.
                          DESC
  s.homepage            = 'https://github.com/fluttertv/<plugin>_tvos'
  s.license             = { :file => '../LICENSE' }
  s.author              = { 'FlutterTV' => 'noreply@fluttertv.dev' }
  s.source              = { :path => '.' }
  s.source_files        = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.platform            = :tvos, '13.0'
  s.swift_version       = '5.0'
  # Critical: do NOT use `s.dependency 'Flutter'`. The Flutter pod doesn't
  # declare tvOS support. We pick up Flutter.framework via search paths.
  s.xcconfig            = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"',
    'OTHER_SWIFT_FLAGS'      => '$(inherited) -DTARGET_OS_TV',
  }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
```

The podspec is identical for every plugin we port; only the name/summary/version
vary. It's a mustache template.

---

## 7. Compatibility report (`PORTING_REPORT.md`)

Generated alongside the package every run. Skeleton:

```markdown
# <plugin>_tvos — porting report

Generated by `flutter-tvos plugin port` on YYYY-MM-DD.

Source: `<plugin>` <version> (path: ...)
Base platform: ios|macos (Swift|ObjC)
Output: `./<plugin>_tvos`

## Summary
| Status | Count |
|---|---|
| Methods ported as-is | N |
| Methods stubbed (iOS-only) | N |
| Compile errors expected | 0 |
| Manual review items | N |

## Methods
### `<methodName>` ✓ ported
…

### `<methodName>` ⚠️ partial
Source: ...
Note: ...

### `<methodName>` ✗ stubbed
Source: ...
Reason: ...
Suggested action: ...

## Imports removed
- `import WebKit` (Classes/X.swift:5)
- `import SafariServices` (Classes/X.swift:6)

## Manual review items
1. ...
```

---

## 8. `--include-example` mode

Most plugin authors test changes via the plugin's example app. Adding `tvos/` to
that app makes our port immediately runnable.

1. Locate `<source>/example/`.
2. Verify `example/lib/main.dart` exists and `example/pubspec.yaml` declares
   `flutter` as a dependency.
3. Run `flutter-tvos create --org com.example.<plugin>example .` from inside
   `example/`. That produces `tvos/` using our existing template (icons,
   Info.plist, pbxproj, etc.) without touching `lib/`, `ios/`, etc.
4. Edit `example/pubspec.yaml` to add `dependency_overrides` for the original
   plugin's `*_ios` and our new `*_tvos`.
5. Append a one-line note to `example/README.md`: "On tvOS: `flutter-tvos run`."

The example app stays the original example. We don't fork it. We add tvOS as
another platform to the same app.

---

## 9. Tests

The porter is a code generator over a known schema, so it tests cleanly with
golden files.

| Test file | Coverage |
|---|---|
| `test/general/plugin_port_pubspec_test.dart` | pubspec rewriting: name derivation, platform key removal/addition, version reset, dependency filtering |
| `test/general/plugin_port_swift_test.dart` | Swift transformer: import filtering, method-handler stubbing, header replacement; mixed Swift+ObjC cases |
| `test/general/plugin_port_objc_test.dart` | ObjC transformer: same shape as Swift, exercising `#import` handling |
| `test/general/plugin_port_compat_db_test.dart` | regex database: each pattern has at least one positive test (matches the API call) and one negative (similar-but-allowed API doesn't match) |
| `test/general/plugin_port_e2e_test.dart` | end-to-end against `test/fixtures/`: `url_launcher_ios`, `shared_preferences_foundation`, `path_provider_foundation`, hand-rolled ObjC fixture, pure-Dart no-op fixture |

Goldens live under `test/fixtures/<plugin>/expected/`. Updating goldens uses
`dart test --update-goldens` (we wire that flag).

---

## 10. Implementation phases

Each phase is shippable on its own. Each ends with green CI.

### Phase 1 — scaffolding only (mechanical, no porting logic)

- `flutter-tvos plugin port <path>` works for a hand-picked plugin.
- Generates pubspec, podspec, empty Swift file, README, CHANGELOG, LICENSE,
  analysis_options, lib stub, test stub, gitignore.
- No iOS-source reading; user fills in `Classes/<X>Plugin.swift` themselves.
- Tests: pubspec rewriting, golden output for one fixture plugin.

**Deliverable**: working scaffold for `url_launcher_tvos` that compiles when the
user pastes their iOS Swift code in.

### Phase 2 — read the source plugin

- Detection step (§4): parse pubspec, locate plugin class, identify source
  language.
- Friendly summary printed before write.
- Pass through native source files **verbatim** to output (still no porting
  logic).

**Deliverable**: removes the "create empty Swift file" step. User runs the
command and gets their iOS Swift code in `tvos/Classes/`.

### Phase 3 — compatibility database + Swift transformer

- The database (§6.3) seeded with 12–15 patterns.
- Swift transformer applies it: comment out, insert stubs, regenerate header.
- `PORTING_REPORT.md` written with detected items.
- Tests: per-pattern unit tests + end-to-end against `url_launcher_ios`.

**Deliverable**: real porting; `url_launcher_ios` produces a buildable package
with stubbed unsupported methods.

### Phase 4 — Objective-C transformer

- Same logic as Swift, applied to `.h`/`.m` pairs.
- One e2e test against an ObjC fixture plugin.

**Deliverable**: ObjC plugins are first-class.

### Phase 5 — `--include-example`

- Generates `example/tvos/` via existing `flutter-tvos create` template.
- Updates `example/pubspec.yaml` `dependency_overrides`.
- e2e test runs `flutter-tvos build tvos --simulator --debug` against the
  generated example.

**Deliverable**: example apps that run on the tvOS simulator after porting.

### Phase 6 — `--from-pub` and `--from-git`

- Download/clone, then run normal port flow.
- Caching of pub downloads.
- Tests against locally-served pub server.

**Deliverable**: command works without requiring the user to clone anything
first.

### Phase 7 — polish

- `--dry-run` honest about every write.
- Interactive prompt with `--force` bypass.
- Bash/zsh tab completion.
- Documentation in CLAUDE.md and this file.
- Update `README.md` with "How to add tvOS support to your plugin".
- Internal validation: port at least three real plugins (url_launcher,
  shared_preferences, path_provider) and add them to our plugin index.

**Deliverable**: shippable v1.

---

## 11. File-by-file plan

| File | New / Modified | Purpose |
|---|---|---|
| `lib/commands/plugin.dart` | new | Top-level `flutter-tvos plugin` `Command` container with `port` as subcommand. Mirrors how stock Flutter does `flutter pub …`. |
| `lib/commands/plugin_port.dart` | new | The `port` subcommand. Owns argument parsing, source detection, orchestration. |
| `lib/plugin_porting/source_analyzer.dart` | new | Reads source pubspec, locates plugin class, scans `ios/` or `macos/`. |
| `lib/plugin_porting/pubspec_rewriter.dart` | new | Pubspec mutation logic (§5). |
| `lib/plugin_porting/podspec_writer.dart` | new | Mustache rendering of the podspec template. |
| `lib/plugin_porting/swift_porter.dart` | new | Swift transformer (§6.1) — phase 3+. |
| `lib/plugin_porting/objc_porter.dart` | new | ObjC transformer (§6.2) — phase 4+. |
| `lib/plugin_porting/compatibility_database.dart` | new | Pattern table (§6.3) — phase 3+. |
| `lib/plugin_porting/report_emitter.dart` | new | Builds `PORTING_REPORT.md` — phase 3+. |
| `lib/plugin_porting/example_extender.dart` | new | `--include-example` flow (§8) — phase 5+. |
| `lib/plugin_porting/templates/` | new dir | Mustache templates: pubspec, podspec, README, CHANGELOG, gitignore, analysis_options, lib stub, test stub. |
| `lib/executable.dart` | modified | Register `TvosPluginCommand`. |
| `test/fixtures/` | new dir | Tarball-style fixtures for e2e tests. |
| `test/general/plugin_port_*.dart` | new | Unit + e2e tests (§9). |
| `flutter-tvos/CLAUDE.md` | modified | Add `## Plugin Porting` section. |
| `docs/PLUGIN_PORTING.md` | new | This document. |
| `README.md` | modified | New "Add tvOS support to your plugin" section. |

---

## 12. Edge cases

| Edge case | Handling |
|---|---|
| Source has both `ios/` and `macos/` and they differ | `--base-platform` chooses; default ios. |
| Source is a monorepo (`packages/foo`, `packages/foo_ios`) | Accept either; resolve to the package with native code. |
| Source uses Swift Package Manager in addition to CocoaPods | We only generate a podspec; SPM support is a follow-up. |
| Swift + ObjC bridging header | Copy verbatim; reference from podspec via `s.preserve_paths`. |
| Resources (xib, assets) | Copy verbatim into `tvos/Resources/`. tvOS supports them. |
| `@available(iOS 16.0, *)` annotations | Rewrite to `@available(tvOS 16.0, *)`. Pattern in compat DB. |
| `#if !TARGET_OS_OSX` guards | Keep guards; add `#if !TARGET_OS_TV` clones where iOS code wouldn't fit. |
| Pure-Dart plugin (no native code) | Detect, exit 0 with friendly message. |
| Source already has `tvos/` | Refuse with `"target already has a tvOS implementation; use --force to overwrite"`. |
| Pigeon / FFI plugins | FFI plugins ship native code through CocoaPods anyway; podspec generation is the same. Pigeon-generated Swift goes through the Swift transformer. |
| Multiple plugin classes | Port the primary, list secondaries in the report. |
| Plugin's purpose is something tvOS doesn't support (e.g. `image_picker_ios`) | Run normally; report flags every method as stubbed. The output package builds and registers; every call returns `FlutterMethodNotImplemented`. Sometimes that's exactly what you want. |
| `*_macos` source | Same flow; macOS APIs are MUCH closer to tvOS than iOS in many cases — fewer report items. Often preferred. |

---

## 13. What the user does after running

1. `cd <plugin>_tvos`
2. Read `PORTING_REPORT.md` top-to-bottom.
3. For each `✗ stubbed` method: decide between leaving the stub (apps get
   `MissingPluginException` if they call it on tvOS, surfacing the limitation
   cleanly) or implementing a tvOS equivalent if there's an obvious one.
4. `flutter-tvos build tvos --simulator --debug` from `example/` to verify the
   registrant compiles.
5. With `--include-example`, run `flutter-tvos run` to launch on a real Apple TV.
6. Commit, push, optionally PR upstream or publish under their own org.

The porting report ends with a checklist they can tick through.

---

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Compatibility DB goes stale as Apple ships tvOS APIs | Tag entries with `tvosSinceVersion`; flag entries that may now be supported. Quarterly re-review. |
| User assumes the port "just works" without reading the report | Final stdout line: `Manual review required. Read PORTING_REPORT.md before publishing.` |
| Regex-based porting misses obfuscated API usage | Acknowledge in docs; report is best-effort. Compensate with thorough fixtures + ask PR reviewers to read the report. |
| Plugin authors may not want to host `*_tvos` themselves | README clear: pubspec `homepage` can point at FlutterTV org or their own. No lock-in. |

---

## 15. Definition of done (per phase)

| Phase | Done when |
|---|---|
| 1 | `flutter-tvos plugin port <fixture>` produces a buildable scaffold (empty Swift body), `dart analyze lib test` clean, golden test passes |
| 2 | Same command copies the iOS Swift code verbatim into `tvos/Classes/` |
| 3 | Same command stubs `closeWebView` and `launchInWebView` automatically; `PORTING_REPORT.md` lists both; e2e test green |
| 4 | A hand-rolled ObjC fixture ports identically; e2e test green |
| 5 | `--include-example` produces a runnable example app; e2e test invokes `flutter-tvos build tvos --simulator --debug` and asserts the build succeeds |
| 6 | `--from-pub` and `--from-git` work end-to-end |
| 7 | Docs published, README updated, command appears in `--help`, used internally to port at least 3 real plugins, results in our plugin index |

---

## 16. Out of scope (for now)

- Auto-publishing to pub.dev.
- PR generation against upstream (`--upstream-pr`) — interesting follow-up.
- Pigeon regeneration for tvOS-specific output.
- macOS port (the inverse direction).
