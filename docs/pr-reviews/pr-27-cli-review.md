# Review — CLI PR #27: Release 1.3.2 — Flutter 3.44.3 (fluttertv/flutter-tvos)

**Verdict: APPROVE.** `dev` → `main` promotion. The version bump is mechanical;
the only genuinely new logic is the `precache` rewrite and the `create` guard,
both of which are correct. Findings are nits, not blockers.

## Scope
Carries everything already reviewed/merged on `dev` (platform-identity AOT fix
#24, RCU configure retry, profile-SDK fix) plus the new-since-last-review parts:
3.44.3 engine bump, `precache` scoping, `create` usage guard, plugin docs
→ 1.1.2, plugin `tvos/.gitignore`.

## New logic reviewed

### `precache` rewrite (`lib/commands/precache.dart`) — CORRECT
Replaces `super.runCommand()` with a hand-driven cache pass so a tvOS embedder
fetches only `{universal, informative}` + the tvOS engine set, not Android/iOS/
web/macOS. Compared line-by-line against stock `PrecacheCommand.runCommand` in
the pinned SDK:

- `lock()`, `force`→`clearStampFiles()`, `all-platforms`, `use-unsigned-mac-
  binaries`, the `android` umbrella mapping — all replicated faithfully.
- **Dropped `cache.platformOverrideArtifacts = …`** — *correct to drop.* That
  field only feeds `ignorePlatformFiltering` (cache.dart:913), which can only
  *expand* what downloads (bypass host-platform filtering). The override passes
  an explicit `requiredArtifacts` set; replicating it would partially undermine
  the "download less" goal. Harmless omission.
- **Dropped the `if (!isUpToDate()) …` gate** — *correct to drop, and called out
  in the commit.* `isUpToDate()` checks every registered artifact incl. the
  platforms we skip, so it's ~always false (and would print a misleading
  "Already up-to-date."). `updateAll`→`_collectArtifactsToUpdate` is per-artifact
  idempotent, so no redundant downloads.
- `selectRequiredArtifacts` extracted as a pure `@visibleForTesting` fn with a
  solid table-driven test (default set, `--ios`, `--android` umbrella, lone
  child flag, feature-gating, `--all-platforms`, disabled-iOS). Good coverage.
- `wasParsed` guarded by `options.containsKey` so a future `DevelopmentArtifact`
  with no precache flag can't throw. Nice defensive touch.

`--force` ordering is fine: the tvOS branch **physically deletes**
`tvosArtifactDirectory` before its own `updateAll`, so the tvOS engine re-fetches
regardless of the later `clearStampFiles()`.

### `create` guard (`lib/commands/create.dart`) — CORRECT
Hoists stock `CreateBase.validateOutputDirectoryArg()` ahead of the tvOS path's
`argResults!.rest.first` read, so no-output-dir prints usage + exits 2 instead
of `Bad state: No element`. `validateOutputDirectoryArg` does exactly that
(`throwToolExit(…, exitCode: 2)`) for empty and >1 cases. Verified in the SDK.

### `displayName => 'tvOS Engine'` (`lib/tvos_cache.dart`) — cosmetic, safe
Only affects the `[i/N] <displayName>` header for multi-download artifacts
(cache.dart:802). Plus the `_treeLine` nesting — pure presentation.

### gitignore / docs / version bumps — trivially correct.

## Nits (non-blocking)
1. `clearStampFiles()` runs *after* the tvOS `updateAll`, so it also clears the
   tvOS stamp just written. Harmless (the dir was already deleted+refetched in
   the tvOS branch, and stamp clearing only affects the *next* run), but
   slightly redundant — could move the `force` handling before the tvOS branch
   for symmetry.
2. The `create` no-args test was dropped (transitively invokes Pub in CI). Fair
   tradeoff — the fix is a single stock call — but the no-output-dir path now
   has no regression test. Low risk.

## Not independently re-run
Did not execute the 262-test suite locally (needs the bundled SDK + pub get).
Verified every changed line statically; relied on the PR's reported green CI for
the full run. 27 test files present incl. the new `tvos_precache_test.dart`.
