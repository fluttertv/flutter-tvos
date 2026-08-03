# Review — engine PR #3: Add Flutter 3.44.3 patch set (fluttertv/engine)

**Verdict: APPROVE.** Low-risk repin. Every claim in the description was verified;
one wording imprecision in the rationale is worth a one-line fix but does not
affect correctness.

## What it does
Adds `flutter3.44.3/` (commit pin `e1fd963c` + 17 patches + 7 new source files),
bumping the tvOS patch baseline from 3.44.2 to 3.44.3.

## Verification

**The patch dir is byte-identical to 3.44.2 except the pin.** `diff -rq
flutter3.44.2 flutter3.44.3` reports exactly one differing file:
`flutter_commit.txt`. All 17 patches and all 7 `new_files/` sources are
unchanged. So the patch *content* was already reviewed in PR #2; the only new
risk is "right commit + patches still apply."

**Commit identity — CONFIRMED.** GitHub tag→SHA:
- `3.44.1` → `924134a4…`
- `3.44.2` → `c9a6c484…`
- `3.44.3` → `e1fd963c…` ✅ (commit msg: "[flutter-3.44-candidate.0] Sync
  engine.version… (#188178)", 2026-06-18)

**Dart unchanged from 3.44.2 — CONFIRMED.** `dart_revision` in `DEPS` is
`d684a576…` at both `c9a6c484` (3.44.2) and `e1fd963c` (3.44.3). SDK hash stable
→ no AOT `Invalid SDK hash`. `skia_revision` also unchanged
(`e9ed4fc9…`) → the Skia-internal patches are safe.

**Patches apply cleanly — CONFIRMED (by inspection of the 3.44.1→3.44.3 diff).**
The `flutter/flutter` compare (`924134a4…e1fd963c`, not truncated: 14 commits /
53 files) touches **none** of the 41 patched flutter/flutter paths. The only
`engine/src/...` files in the diff are the Impeller **GLES** backend (patches
touch only **Metal**), the APNG image-generator security fix, and an Android
`PlatformPlugin.java` (patches touch only `darwin/ios`). The rest is
`flutter_tools` Dart + `.ci.yaml` + `CHANGELOG`/`DEPS`. Consistent with a
routine stable hotfix.

## One nit (non-blocking)
The description says "the **3.44.1→3.44.3** source delta touches none of the
patched files." That's true for the flutter/flutter sources, but the **Dart
pin did move** in the 3.44.1→3.44.2 step (`fc3da898` → `d684a576`), so the
Dart-internal patches (`runtime/…`, `sdk/lib/io/platform.dart`) do **not** sit
on the same Dart base as 3.44.1. It doesn't matter for *applying* the patches
(the dir is identical to 3.44.2's, which already targets `d684a576`), but the
*reason* the repin is safe is "identical to 3.44.2 + 3.44.2→3.44.3 changed
nothing patched (Dart included)", not "nothing moved since 3.44.1". Suggest
rewording the rationale to baseline against **3.44.2**, matching the (correct)
Dart claim right next to it.
