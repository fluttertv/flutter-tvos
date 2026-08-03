# flutter-tvos — answers to three customer questions

---

## 1. Older Flutter versions

> **Q:** *is it possible to use older flutter versions. as mentioned before, we are still on 3.32.8*

We already support a range, not just the latest: **3.41.4 through 3.44.8**, each with published engine artifacts and a matching CLI release. Releases stay up permanently — pick the one matching your Flutter. Note that engine origin signing landed with 3.44.5; without it the App Store rejects apps with ITMS-91065, so 3.44.5 is the effective floor if you ship through the Store.

3.32.8 is below that range, but adding older versions is work we can do, not a design limit — the build is parameterised by Flutter commit, so each version is its own patch rebase, engine build and release.

- **Down to 3.35** — straightforward, the patch set rebases with little friction.
- **Below 3.35, including 3.32.8** — more involved, since upstream reorganised the Apple SDK build config between 3.32 and 3.35. We have prior work on 3.32.8 from an earlier round, which removes most of the uncertainty, but it needs updating to the current patch set and verifying on device.

Two things would help us scope it:

1. Is 3.32.8 a hard pin, or just where you are today?
2. Are you shipping through the App Store? That affects which versions are usable at all.

---

## 2. Engine coupling and your own changes

> **Q:** *I assume it is linked to your custom engine. And we cannot use our engine, because of different channel names etc*

Yes, it needs a patched engine — but it is a patch set applied to a stock Flutter tree, not a fork, and your own changes do not have to be lost.

The platform channels you are thinking of (`flutter/tv_remote`, `flutter/tv_remote_touches` for remote and touchpad input) are created by a plugin that ships inside that patch set. Nothing for you to match up by hand — the channels come with the engine artifacts you already download.

For your own engine modifications there are two ways we work, and we do both with other users today:

- **We integrate them.** Send us the diff, we review it and carry it in the patch set from then on. Your changes then ride along with every Flutter upgrade we do, at no ongoing cost to you — no fork to rebase on your side.
- **You contribute them directly.** We arrange access so you can open PRs against the patch set yourself. This one needs the access agreement in place first, so it is a next step rather than something immediate.

Either way the result is the same and it is the part that matters: one patch set over one tree, maintained by us, with your work inside it rather than alongside it.

A good starting point is `git diff --name-only` against your upstream base, plus a short note on what each change does. Our patches are concentrated in the Darwin embedder and the Metal backends, so that tells us straight away whether your work touches the same areas and how it would land.

---

## 3. Accessibility and the European Accessibility Act

> **Q:** *Did you implement the accessibility feature in the engine which are now mandatory for video apps in europe*

Partly, and I would rather be precise than reassuring here.

At the engine level the tvOS port wires Flutter's semantics tree into the platform accessibility system and does the focus-engine work that goes with it: a dedicated selection view the system tracks to draw the focus indicator, focus-environment handling so focus reaches Flutter content, and preservation of accessibility state around text input. On tvOS accessibility and focus are the same subsystem — hiding an element from accessibility also hides it from the focus engine — so this code sits on the critical path of ordinary remote navigation, not in a separate mode.

Being straight with you: VoiceOver behaviour on Apple TV is not currently part of our release verification matrix. The plumbing is in place and exercised, but end-to-end VoiceOver has not been formally demonstrated, and on a compliance question I would rather say that than imply more.

On the EAA itself, the requirements split across layers. Subtitle, SDH and audio-description tracks come from AVKit/AVPlayer, and our video player plugin keeps native caption and track behaviour intact. The controls your users press to turn those on live in your own Flutter UI and must be focus-reachable and announceable — that is the part the engine work enables. Conformance is assessed against EN 301 549 and is a property of your application, not of a toolchain.

If this is a hard requirement on your side, the useful next step is a joint verification pass: we test VoiceOver and focus navigation against your actual screens on device, and you get a written result rather than an assurance. Send us your requirement list and we will map it item by item — what the toolchain covers, what is yours, and where the gaps are.

---

## Internal notes (do not send)

**Q1.** Supported chain verified against published releases: artifacts `v1.0.0-flutter3.41.4` … `v1.0.1-flutter3.44.8`, CLI `v3.41.4-tvos.1.0.0` … `v3.44.8-tvos.1.4.3`. Artifacts `v1.0.0-*` (3.41.4–3.44.3) predate origin signing → ITMS-91065. Rebuilding them today with the current `build.sh` would fix that, since signing is now done at packaging and gated in `verify_artifacts.sh`.

The 3.32/3.35 boundary is upstream's unification of the Apple SDK build config into `build/config/darwin/`. Below it the layout is `build/config/ios/{ios_sdk.gni, ios_sdk.py}` + `build/mac/find_sdk.py`. Existing local patches in `Work/tv/flutter_3.32.8_build.patch` already do the substitution in that older layout (`SDKs = ['appletvos','appletvsimulator']`, `-mappletvsimulator-version-min=`), so the build half is solved — but those patches are from Oct–Nov 2025, before the current 17-patch structure, origin signing, tvOS-native metallibs and the on-device JIT fix. Embedder and Impeller halves would need reconciling.

Patch-target file check against upstream: 35/40 present at 3.35.0, 30/40 at 3.32.8.

**Q2.** Option "apply our patches on top of your own tree" is deliberately **not** offered — the patch set is not distributed. Only integration and contribution.

Direct-contribution access is gated on the co-authors agreement (§ 8 UrhG, joint holding) being signed first — it cannot be granted unilaterally. Present it as a next step, never as immediately available.

**Q3.** Engine a11y changes are largely *unblocking* rather than new features: `accessibility_bridge.mm` takes a simpler branch on tvOS, parts of `SemanticsObject` compile out under `#if !TARGET_OS_TV`, `AccessibilityFeatures.swift` gains tvOS 18 availability. The substantial work is focus plumbing — `FlutterViewController.mm` +166 lines, `FlutterTextInputPlugin.mm` +269. No VoiceOver test or verification exists anywhere in either repo.
