# Flutter Custom Embedders Survey — draft answers (flutter-tvos), short version

## What is your custom embedder? Links?

flutter-tvos — Flutter for Apple TV (tvOS).

- Toolchain & runtime package: https://github.com/fluttertv/flutter-tvos
- Engine patch set: https://github.com/fluttertv/engine
- Plugin ports: https://github.com/fluttertv/plugins (pub.dev publisher: fluttertv.dev)
- Pre-built engine artifacts: https://github.com/fluttertv/engine-artifacts/releases

Strictly speaking it isn't a custom embedder. tvOS is a UIKit platform, so rather than writing a new embedder on the C API, we build Flutter's own iOS (Darwin) embedder for tvOS — applying ~16 small, mechanical patches (mostly `#if !TARGET_OS_TV` guards) on top of unmodified upstream flutter/flutter at each stable tag. No standing fork. The Flutter framework is unmodified; the CLI consumes flutter_tools as a library via DI overrides (the flutter-tizen / flutter-elinux pattern), not as a fork. The patches are deliberately kept small and upstreamable.

## Most significant frustrations?

- The engine treats iOS as a monolith: every stable adds new unguarded iOS-only API uses we must wrap in `TARGET_OS_TV` guards.
- The GN build hardcodes the iOS SDK family (SDK names, version-min flags, Swift triple) — patched on every sync.
- Dart VM needs platform-identity patches (`Platform.operatingSystem == "tvos"`).
- flutter_tools isn't a library: private-field churn breaks our subclasses each release; the `Plugin` class hardcodes six platform keys, so we reimplement plugin discovery for `tvos:`.
- Impeller shaders were precompiled iOS-only (we now build tvOS-native metallibs via a patch).

## Features you'd add, ranked?

1. Extension API for out-of-tree platforms in flutter_tools (incl. unknown plugin platform keys).
2. Treat Apple platform variants as a first-class axis in the engine and Dart VM — tvOS as one more value on the axes that already exist (`DART_HOST_OS_*` in the Dart VM, `is_ios`/`is_mac` in GN), with residual UIKit API differences expressed via the same `TARGET_OS_*` conditionals Apple's own SDKs use.
3. Parameterize the Apple SDK in the GN build.
4. Stable extension points in flutter_tools internals.
5. Documented contract for driving `gen_snapshot`/AOT out of tree.

## App developers' workflow frustrations?

Plugin coverage — most plugins are iOS-only and need federated `*_tvos` ports (we automate this with `flutter-tvos plugin port`). Plugin podspecs can't depend on the Flutter pod (it doesn't declare tvOS). Physical-device debugging is more fragile than iOS, though wireless hot reload/DevTools now work.

## How do developers build/debug/test?

Other: a standalone Dart CLI that uses flutter_tools as a library over an unmodified Flutter SDK (DI overrides via `runner.run(overrides:)`) — not a fork. Same UX as `flutter`: create, run with hot reload/DevTools, build, doctor, test, attach, plus `plugin port` and `upgrade`.

## Would a `flutter` CLI extension API help? Would you migrate?

Yes and yes — we'd also gladly co-design it and be its first reference consumer; our codebase is a ready inventory of the needed extension points. It must cover platform/device/build registration and plugin discovery for out-of-tree platform keys.

## Design system(s)?

Material + Cupertino + Other: Apple tvOS HIG (10-foot, focus-based UI). Our VM reports `Platform.isIOS == true` on tvOS, so Cupertino works out of the box.

## How well does Flutter adapt? Customizations needed?

Very well — the Flutter framework is unmodified. Because `Platform.isIOS` is `true` on tvOS (Apple TV is the same UIKit/Metal/Foundation family), Cupertino styling, the SF font, and iOS-style transitions all work out of the box. Customizations are concentrated in input and identity: a native Siri Remote / game-controller plugin in the engine that feeds events to `flutter/keyevent` in the macOS keymap (so the Focus/Shortcuts/Actions stack treats the remote like a keyboard) plus a focus-navigation Dart package; a `Platform.isTvOS` identity hook in the Dart VM; and a small accessibility focus-rectangle adaptation. iOS-only features (status bar, haptics, webview, camera) are guarded out as not applicable on a TV.

## Attempted to upstream patches?

Not yet — and to be candid, that's only because we assumed PRs for an unsupported platform would be declined, so we haven't filed any issues or PRs (no links to share). The patch set was deliberately structured to be upstreamable for exactly this moment. Upstreaming the engine-level delta is our explicit goal and we're ready to do the work ourselves, as an incremental ladder where each step is inert for existing platforms: extend the Dart VM's existing `DART_HOST_OS_*` axis with tvOS → generalize the Apple SDK axis in the GN build → per-subsystem API-availability conditionals in the Darwin shell (the idiom Apple's own SDKs use) → the `tvos:` plugin key. We'd also stand up CI building tvOS against upstream main to prove the guards don't rot. Tell us the preferred form (design doc or a small probe PR) and we'll start.

## Extending federated plugins to your platform?

The federated model works well (`url_launcher` → `url_launcher_tvos` with a `tvos:` key). Pain: the SDK ignores unknown platform keys (we reimplement discovery/registrant generation), podspecs can't depend on the Flutter pod, and iOS implementations often use tvOS-unavailable APIs — we automate porting with a compatibility database.

## Current Flutter version?

3.44.1 (we track stable).

## Time to update to a new stable?

Patch release: ~1 day. Minor/major jump: 2–5 engineer-days (reconcile patches, rebuild 6 engine variants, verify on simulator + device, publish).

## Effort matrix

Tooling: Medium. Embedder: Medium. Engine patches: High (dominant cost). Plugins: Low.

## What can Flutter do to help you stay current?

Let the engine-level tvOS delta live in the tree as a best-effort platform — we contribute and maintain that code, no Google resources or guarantees asked; the toolchain, artifacts, and plugin ecosystem stay on us. Extending the existing platform axes + parameterizing the Apple SDK in GN alone would shrink our patch set to near zero (and help future visionOS work).

## Update process?

gclient sync at the new stable tag → apply/regenerate patches → fix newly unguarded iOS APIs → build 6 engine variants, publish artifacts → re-pin CLI, run ~240 tests, smoke-test on simulator + Apple TV → release.

## How often does upstream break you? Detection?

Practically every major stable release (new unguarded APIs, build refactors, flutter_tools private-API churn); patch releases are usually painless. Detected via compile failures during the port + our test suite + manual device verification. CI against upstream main is the gap we want to close.

## Engine artifacts?

Custom build of the engine (upstream + our patch set, no standing fork), published as pre-built zips on GitHub Releases — app developers only download them.

## Custom engine/Dart patches?

Yes, ~16: Dart VM tvOS identity, Skia/Perfetto guards, GN build (tvOS SDKs, Swift triple), Impeller `@available` + tvOS-native metallibs, `TARGET_OS_TV` guards in the Darwin shell, plus new files (Siri Remote plugin, accessibility focus view, lldb debug hook).

## Do you use the embedder API? Missing features?

No — deliberately. tvOS doesn't need a custom embedder; it needs the iOS embedder to compile for tvOS. A C-API embedder would duplicate the UIKit work and break the ObjC/Swift plugin ecosystem. The only "missing feature" is that the iOS embedder isn't officially buildable for other Apple UIKit platforms — that's what we'd like to fix upstream.

## Keeping platform channels up-to-date?

Easy — reusing the iOS embedder, we inherit all standard channels. We add two of our own for the TV remote; both ends live in our packages and version together.

## Impeller migration? Skia removal concerns?

Fully on Impeller (Metal). Needed tvOS `@available` guards and tvOS-native metallib compilation (patch). Skia removal is fine — Apple TV GPUs are Metal-capable. Only ask: keep Impeller shader build targets parameterizable by Apple SDK.

## Software renderer?

No — no use case, all Apple TVs support Metal.

## Merged threads?

Inherited from the iOS embedder with the 3.44 engine; no tvOS-specific issues observed.

## Contact?

denisov.shureg@gmail.com · GitHub: @DenisovAV. Please reach out — we'd genuinely welcome a conversation about upstreaming the engine-level tvOS delta. We're committed to maintaining the tvOS toolchain and plugin ecosystem long-term; with the platform delta upstream, that investment stands on much firmer ground for everyone who ships Flutter apps on Apple TV.



flutter-tvos — Flutter for Apple TV (tvOS).
  
- Toolchain & runtime package: https://github.com/fluttertv/flutter-tvos
- Engine patch set: https://github.com/fluttertv/engine
- Plugin ports: https://github.com/fluttertv/plugins (pub.dev publisher: fluttertv.dev)
- Pre-built engine artifacts: https://github.com/fluttertv/engine-artifacts/releases

Strictly speaking it isn't a custom embedder. tvOS is a UIKit platform, so rather than writing a new embedder on the C API, we build Flutter's own iOS (Darwin) embedder for tvOS — applying ~16 small, mechanical patches on top of unmodified upstream flutter/flutter at each stable tag. No standing fork. The Flutter framework is unmodified; the CLI consumes flutter_tools as a library via DI overrides (the flutter-tizen / flutter-elinux pattern), not as a fork. The patches are deliberately kept small and upstreamable.



- The engine treats iOS as a monolith: every stable adds new unguarded iOS-only API uses we must wrap in TARGET_OS_TV guards.
- The GN build hardcodes the iOS SDK family (SDK names, version-min flags, Swift triple) — patched on every sync. 
- The Dart VM needs platform-identity patches so Platform.operatingSystem returns "tvos".
- flutter_tools isn't consumable as a library: private-field churn breaks our subclasses each release, and the Plugin class hardcodes the six platform keys, so we reimplement plugin discovery to honor tvos:.
- Impeller shaders were precompiled iOS-only — we now build tvOS-native metallibs via a patch.




1. An extension API for out-of-tree platforms in flutter_tools (incl. unknown plugin platform keys like tvos:). Today platforms are hardcoded; a decoupled, pluggable architecture would let anyone register their own platform/device/build pipeline through an official API. It would also enable on-demand SDK downloads — developers fetch tvOS (or any out-of-tree) artifacts only when they need them, instead of a bloated default setup. A real win for the core SDK footprint, not just for us. We'd gladly co-design this and be its first reference consumer.
2. Treat Apple platform variants as a first-class axis in the engine and Dart VM — tvOS as one more value on the axes that already exist (DART_HOST_OS_* in the Dart VM, is_ios/is_mac in GN), with residual UIKit API differences expressed via the same TARGET_OS_* conditionals Apple's own SDKs use. This removes ~90% of our patches.
3. Parameterize the Apple SDK in the GN build (SDK name, version-min flags, Swift triple) so building for tvOS needs no source patches. Also paves the way for visionOS / Catalyst.
4. Stable extension points in flutter_tools internals so out-of-tree wrappers survive releases.
5. A documented contract for driving gen_snapshot / AOT out of tree.
6. Official recognition for community platforms — a listing as an ecosystem project, a mention, or similar. Not an engineering ask, but it's what lets streaming companies and enterprises trust an out-of-tree platform enough to bet production on it. Without some "officially acknowledged" signal, a community repo stays hard to adopt at scale.




- Plugin coverage is the #1 friction. Most native plugins are iOS-only and need a federated *_tvos port. We lower this with flutter-tvos plugin port — it scaffolds a port from any iOS/macOS plugin, flagging tvOS-unavailable APIs via a built-in compatibility database — plus a curated index of 11 ready ports. Still, "is the plugin I need available?" is the first question every app developer asks.
- Plugin podspecs can't depend on the Flutter pod (it doesn't declare tvOS), so they pick up Flutter.framework via a FRAMEWORK_SEARCH_PATHS workaround instead of s.dependency 'Flutter' — a sharp edge for anyone hand-writing a podspec.
- On-device debugging is more fragile than iOS. Hot reload, hot restart, and DevTools do work over a wireless Apple TV, but the launch path (devicectl + lldb attach over the CoreDevice tunnel, an Xcode-debugger fallback, and mDNS VM-service discovery) has more failure modes than USB-tethered iOS, and a slow network can hit the lldb attach timeout.



A standalone Dart CLI that depends on flutter_tools as a library over an unmodified Flutter SDK, swapping in tvOS implementations through Flutter's DI (runner.run(overrides:)) — the flutter-tizen / flutter-elinux pattern, not a fork. Same UX as flutter: create, run (hot reload + DevTools), build, doctor, test, attach, plus plugin port and upgrade.




Yes and yes — we'd also gladly co-design it and be its first reference consumer; our codebase is a ready inventory of the needed extension points. It must cover platform/device/build registration and plugin discovery for out-of-tree platform keys.



Very well — the Flutter framework is unmodified. Because `Platform.isIOS` is `true` on tvOS (Apple TV is the same UIKit/Metal/Foundation family), Cupertino styling, the SF font, and iOS-style transitions all work out of the box. Customizations are concentrated in input and identity: a native Siri Remote / game-controller plugin in the engine that feeds events to `flutter/keyevent` in the macOS keymap (so the Focus/Shortcuts/Actions stack treats the remote like a keyboard) plus a focus-navigation Dart package; a `Platform.isTvOS` identity hook in the Dart VM; and a small accessibility focus-rectangle adaptation. iOS-only features (status bar, haptics, webview, camera) are guarded out as not applicable on a TV.




Not yet — and to be candid, that's only because we assumed PRs for an unsupported platform would be declined, so we haven't filed any issues or PRs (no links to share). The patch set was deliberately structured to be upstreamable for exactly this moment. Upstreaming the engine-level delta is our explicit goal and we're ready to do the work ourselves, as an incremental ladder where each step is inert for existing platforms: extend the Dart VM's existing `DART_HOST_OS_*` axis with tvOS → generalize the Apple SDK axis in the GN build → per-subsystem API-availability conditionals in the Darwin shell (the idiom Apple's own SDKs use) → the `tvos:` plugin key. We'd also stand up CI building tvOS against upstream main to prove the guards don't rot. Tell us the preferred form (design doc or a small probe PR) and we'll start.




The federated model works well (`url_launcher` → `url_launcher_tvos` with a `tvos:` key). Pain: the SDK ignores unknown platform keys (we reimplement discovery/registrant generation), podspecs can't depend on the Flutter pod, and iOS implementations often use tvOS-unavailable APIs — we automate porting with a compatibility database.




3.44.1 (we track stable)



Patch release: ~1 hour. Minor/major jump: a few hours or a bit more if something goes wrong :) reconcile patches, rebuild 6 engine variants, verify on simulator + device, publish).





1. Let the engine-level tvOS delta live in the tree as a best-effort platform. We contribute and maintain that code — no Google resources, CI capacity, or guarantees asked; the toolchain, artifacts, and plugin ecosystem stay on us. Just generalizing the existing axes (the Dart VM's DART_HOST_OS_*, GN's is_ios/is_mac) to treat tvOS as one more value, plus parameterizing the Apple SDK in GN, would shrink our patch set to near zero — and pave the way for future Apple platforms like visionOS.
2. A stable extension contract in flutter_tools (the out-of-tree platform API, plus protected/public extension points instead of private fields). Today the riskiest part of every upgrade isn't the engine patches — it's private-field churn in flutter_tools breaking our DI subclasses.
3. Don't break what we can't see coming. We'd run our own CI building tvOS against upstream main to catch regressions early; an upstream signal (or simply carrying the inert axes) means most breakage never reaches us in the first place.





It's largely scripted, not manual. For the engine: gclient sync upstream flutter/flutter at the new stable tag, then build_tvos_engine.sh applies the whole patch set (Dart VM, Skia, Perfetto, GN build, Darwin-shell guards) and builds every variant — device debug/profile/release, simulator, host tools, gen_snapshot — and package_artifacts.sh zips them for release. The only manual step is reconciling any patch that no longer applies after a major upstream refactor (and fixing newly unguarded iOS APIs, surfaced by compile failures). For the toolchain: re-pin flutter.version + engine.version, fix any flutter_tools API changes, CI runs the test suite (~190 cases) + dart analyze, then we smoke-test the example app on simulator + a physical Apple TV and tag a release. End users update with one command — flutter-tvos upgrade (re-pins Flutter + engine artifacts together).




Practically every major stable release breaks something — new unguarded iOS-only APIs in the Darwin shell, GN/build refactors that invalidate a patch, or flutter_tools private-API churn that breaks our DI subclasses.
Patch releases are usually painless. Detection is automated where it can be: the patch-apply step fails loudly on a broken patch, CI runs dart test + dart analyze on every push/PR (CLI only today), and run_tvos_tests.sh exercises the engine on a real device/simulator. The remaining gap — which we want to close — is scheduled CI building the tvOS engine against upstream main, so engine-side breakage surfaces weeks ahead of a stable release instead of during the port





Yes — 15 patch files plus 7 new source files, all applied on top of unmodified upstream:

- Dart VM: tvOS host-OS identity (Platform.operatingSystem == "tvos"), process/execvp guards, and enabling the existing iOS virtual-memory / JIT + lldb-attach (NOTIFY_DEBUGGER_ABOUT_RX_PAGES) paths for tvOS.
- Skia / Perfetto: Metal-availability and small platform guards.
- GN build system: tvOS SDKs (darwin_sdk.gni/.py), Swift target triple (apple-tvos), appletvsimulator version-min flags.
- Impeller: tvOS @available gates plus tvOS-native metallib compilation.
- Darwin shell: #if !TARGET_OS_TV guards across iOS-only APIs (headers, lifecycle, accessibility, UIPress), and the GameController/MediaPlayer wiring for the remote.
- New source files (additive, not patches): FlutterTvRemotePlugin (+ _Internal / Protocol) for Siri Remote, game-controller and media input, and FlutterAccessibilitySelectionView for the tvOS focus rectangle.

Every patch is small and mechanical by design — most are preprocessor guards — so they're structured to become upstream PRs.





No — deliberately. We don't touch the C embedder API (embedder.h) at all. tvOS doesn't need a custom embedder; it needs the existing iOS (Darwin) embedder to compile for tvOS. Going through the C API would mean re-implementing the UIKit integration, lifecycle, accessibility, text input and platform views the iOS embedder already provides, and would break the ObjC/Swift FlutterPlugin API the entire iOS plugin ecosystem (and our *_tvos ports) depends on. So the only "missing feature" is upstream support for building the iOS embedder for other Apple UIKit platforms — which is exactly what we'd like to fix upstream rather than route around.





Easy. By reusing the iOS embedder we inherit every standard channel (keyboard, text input, platform, lifecycle, accessibility) and its evolution for free — there's nothing for us to keep in sync. We add two of our own — flutter/tv_remote and flutter/tv_remote_touches — for Siri Remote / game-controller input, and reuse the stock flutter/keyevent channel (macOS keymap) so the remote drives the normal Focus/Shortcuts/Actions stack. Both ends of our channels live in our own repos (native in the engine patch set, Dart in flutter_tvos) and version together, so there's no engine↔plugin protocol skew.





Fully on Impeller (Metal). Needed tvOS `@available` guards and tvOS-native metallib compilation (patch). Skia removal is fine — Apple TV GPUs are Metal-capable. Only ask: keep Impeller shader build targets parameterizable by Apple SDK.



No — no use case, all Apple TVs support Metal.




Inherited from the iOS embedder with the 3.44 engine; no tvOS-specific issues observed.



denisov.shureg@gmail.com
