# PR Review: fluttertv/engine#5 — Origin-sign tvOS engine artifacts (ITMS-91065)

**Repo:** fluttertv/engine · **Branch:** `itms91065-origin-signing` → `main`
**Author:** MAUstaoglu · **Date:** 2026-07-18
**Diff:** 2 files, +66 −1 (`build.sh`, `verify_artifacts.sh`)
**Reviewers:** 2 targeted agents (Apple codesign correctness · bash/release-gating) + lead manual pass.
Note: the loaded `review-pr` skill was the litert_demo variant (Flutter ML app); its checklists
don't apply to a shell/codesigning PR, so agents were retargeted to the actual subject.

## Verdict: REQUEST CHANGES

The build-side signing is correct and well-designed. **The verify gate has a hole that defeats
the PR's own purpose:** it announces "origin-signed" for any artifact carrying *any* valid
signature — including an ad-hoc signature — which is exactly the unsigned/mis-signed state that
ITMS-91065 rejects. Both reviewers found this independently. It is a one-block fix, not a redesign.

---

## Critical

### C1 · `verify_artifacts.sh` gate passes ad-hoc / wrong-cert signatures as "origin-signed"
Found independently by both reviewers.

```sh
&& codesign --verify --strict "$x" >/dev/null 2>&1 \
&& codesign --verify --strict "$x"/*/Flutter.framework >/dev/null 2>&1; then
    team=$(codesign -dvv "$x" 2>&1 | awk -F= '/^TeamIdentifier/{print $2; exit}')
    ok "$v engine is origin-signed (team ${team:-?})"
```

`codesign --verify --strict` checks signature **integrity**, not **origin**. An ad-hoc signature
(`codesign --sign -`), a linker-signed binary, or a signature by the wrong team all pass it. This
is the realistic CI failure mode: if `SIGNING_IDENTITY` is empty, or the runner has no keychain
access and codesign falls back to ad-hoc, `--verify --strict` still succeeds. `team` is extracted
but **never used in the boolean** — an artifact with `TeamIdentifier=not set` still prints
`ok "... (team ?)"`. The gate cannot catch the very regression (ITMS-91065) it exists to prevent.

**Fix** (gate on Authority + non-empty TeamIdentifier + Timestamp):
```sh
authority=$(codesign -dvv "$x" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')
team=$(codesign -dvv "$x" 2>&1 | awk -F= '/^TeamIdentifier/{print $2; exit}')
ts=$(codesign -dvv "$x" 2>&1 | awk -F= '/^Timestamp=/{print $2; exit}')
if [ -n "$team" ] && [ "$team" != "not set" ] \
   && [[ "$authority" == "Developer ID Application:"* ]] \
   && [ -n "$ts" ] && [ "$ts" != "none" ]; then
  ok "$v engine origin-signed (team $team, $authority)"
else
  bad "$v engine NOT properly origin-signed (team=${team:-?} authority=${authority:-?} ts=${ts:-?})"
fi
```

---

## Important

### I1 · standalone `Flutter.framework` is signed but never verified
`build.sh` signs both the xcframework's inner slices **and** a standalone `Flutter.framework`:
```sh
for fw in "$staging/$target/Flutter.xcframework"/*/Flutter.framework \
          "$staging/$target/Flutter.framework"; do   # <- standalone
```
`verify_artifacts.sh` checks only `Flutter.xcframework` and its inner slices — never
`$DIR/$v/Flutter.framework`. If the tvos_* variants **ship** that standalone framework and it is
what a downstream app embeds, a broken/missing signature on it passes both gates unnoticed.
**Confirm with the release layout:** if the standalone framework ships, add it to the verify loop;
if it's purely intermediate, don't sign it (currently wasted work + a false signal that it matters).

### I2 · `--timestamp` + `set -e` with no retry: a transient Apple TSA blip discards a multi-hour build
Signing runs *after* the multi-hour compile, and `--timestamp` makes a synchronous call to
`timestamp.apple.com`. Under `build.sh`'s `set -e` (line 37), a bare codesign failure inside the
`for` loop aborts the whole run with exit 1 — no retry. Apple's TSA has transient 5xx/timeouts, so
one network blip at the end loses hours. Fail-closed and recoverable, but expensive.
**Fix:** wrap codesign in retry-with-backoff (3 tries, linear/exponential sleep).

---

## Minor

- **M1 · `--signing-identity` with a missing value swallows the next flag.** `--signing-identity --publish`
  sets `SIGNING_IDENTITY="--publish"` and consumes `--publish`, so `PUBLISH` stays 0: the line-65
  gate never fires, the build runs, and codesign later gets identity `"--publish"` — a silent
  "not-publish" plus a confusing late failure. Validate the value exists and isn't another flag
  (`[ "${2#-}" = "$2" ]`). Also, passing `--signing-identity` as the last arg aborts with a bare
  `exit 1` and no message (shift failure under `set -e`) — add a diagnostic.
- **M2 · verify conflates "not built" with "not signed".** A missing variant directory falls to the
  same `bad "$v engine NOT origin-signed"`. Defensible for a full-release gate, but the message
  lies when the artifact simply wasn't built. Split into `MISSING` vs `present but NOT signed`.
- **M3 · empirically run hot reload/restart on a signed `tvos_debug_sim_arm64`** before merge. The
  Simulator app is a real macOS process where hardened runtime *is* enforced, and debug Dart VM uses
  JIT/W^X. In theory enforcement keys off the main executable (Runner.app), not the embedded
  framework, so signing the framework with `--options runtime` shouldn't break JIT — but this is the
  one variant where the theory should be confirmed by a real run, not reasoned about.

---

## Passed / confirmed correct (evidence, not filler)

- **`--options runtime` (hardened runtime) on the embedded tvOS frameworks** — correct. It's part of
  Apple's fixed procedure for signing a *vended SDK* (the "commonly-used third-party SDK" program
  behind ITMS-91065), matching flutter.dev and other XCFramework vendors. Inert on-device; not a defect.
- **Developer ID Application (not Apple Distribution)** — correct for a reusable SDK consumed by many
  downstream apps with different distribution certs. Apple Distribution is for the final `.ipa`.
- **inside-out signing order** (inner slices, then the xcframework wrapper) — correct; signing the
  wrapper last seals the inner hashes. Signing the `.xcframework` bundle itself is meaningful, not noise.
- **wrapper without `--options runtime`** — correct (it's not a Mach-O executable; the flag is a no-op there).
- **`set -e` neutralizes the silent-unsigned-publish risk at build level**, and `--publish` runs
  `verify_artifacts.sh` *before* `gh release create` (build.sh:405 → 416) — two gates before release.
- **glob mechanics and argument fail-closed direction** — verified empirically; `[ -d "$fw" ] || continue`
  correctly handles a non-matching glob; verify's glob is fail-closed under `set -uo pipefail`.

## Summary
- Critical: 1 · Important: 2 · Minor: 3
- **Recommendation: REQUEST CHANGES** — C1 alone means the release gate would green-light exactly the
  artifact ITMS-91065 rejects. All findings are localized fixes; the design is sound.
