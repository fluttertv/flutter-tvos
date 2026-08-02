# Version selection for the flutter-tvos CLI

**Date:** 2026-08-02
**Status:** approved, ready for implementation planning

## Problem

`flutter-tvos` pins exactly one Flutter version per release. `bin/internal/flutter.version`
holds a commit SHA for the vendored SDK; `bin/internal/engine.version` holds the matching
prebuilt-engine tag. A user who needs a different Flutter version has no supported way to get
one — the only lever is editing both files by hand and hoping the CLI source still compiles.

The 3.32.8 engine patch set (fluttertv/engine#11) makes an older Flutter version viable for the
first time, which turns the missing lever into a blocker.

## Why the CLI source cannot simply span versions

The CLI imports ~75 **private** `package:flutter_tools/src/...` libraries. Upstream changes them
without notice. Measured against a real 3.32.8 checkout, the current source produces 21 analyzer
errors:

- 12 — `BuildCommand` takes 6 constructor parameters at 3.32.8 and 19 at 3.44; our subclass
  passes the 3.44 set.
- 7 — `src/ios/lldb.dart` does not exist before 3.35.
- 2 — `Device.isSupported` changed from `bool` to `Future<bool>`; `verboseHelp` moved.

So each supported Flutter version gets its own **release line**: the tag `v<flutter>-tvos.<tool>`
carries the CLI source ported to that version's `flutter_tools` API *and* the two pin files.
Version selection is therefore `git checkout <tag>` in the flutter-tvos repo — which is also the
answer Flutter itself gives. `flutter downgrade` refuses a version argument outright
("`flutter downgrade` does not support specifying a version") and links to a doc that instructs
`git checkout <tag>`. flutter-tizen, whose `shared.sh` ours mirrors, uses the same tag scheme
(`3.44.4-tizen.1.0.0`) and never automated the switch at all.

We are automating what upstream leaves manual. Nothing more novel than that.

## Where the version list comes from

**git tags**, filtered by the existing `releaseTagPattern`.

The tag is already the operative artifact: switching *is* a reset to a tag, so any other source
of truth is a claim *about* tags that can drift from them. Comparable tools bear this out:

| Design | Used by | Failure mode in practice |
|---|---|---|
| Committed static list | pyenv | Chronic staleness — a new version is invisible until the tool itself is updated. Worst reputation of the group. |
| Network manifest | nvm, fvm, rustup | Regional blocking (fvm added a GitHub mirror tier because the Google endpoint is blocked in China); offline means no list at all. |
| Releases API | some asdf plugins | 60 req/hr unauthenticated; asdf documents a `GITHUB_API_TOKEN` workaround. |
| git tags | flutter `upgrade`/`channel` | Needs network to see *new* tags; raw namespace needs filtering. Both already handled here. |

git tags also degrade best offline: previously fetched tags stay listable *and* checkout-able,
which no manifest or API gives. And git's tag store is the on-disk cache — no TTL file to
invalidate. Not subject to REST rate limits, since git smart-HTTP is a different path.

**The strongest counter-argument** is that tags carry no metadata and cannot be retracted. If a
release later needs to be marked broken, a tag name cannot say so, and deleting a published tag
does not remove it from checkouts that already fetched it. If that need materialises, adopt
fvm's shape — a small `versions.json` fetched raw from the default branch tip and used purely as
an *overlay* (yank/annotate) on the tag list, never as the enumeration source. That buys curation
without a second enumeration authority and without pyenv's staleness trap. Do not build it until
the need is real.

## Command surface

Flutter's surface minus `channel`, which is meaningless for us — we pin a commit, not a channel.

```
flutter-tvos versions            list release lines, marking the current one
flutter-tvos use <version>       switch to a version
flutter-tvos upgrade             switch to the newest version (existing behaviour)
flutter-tvos downgrade           return to the previous version
```

```
$ flutter-tvos versions
  3.44.7   v3.44.7-tvos.1.4.2   (current)
  3.44.6   v3.44.6-tvos.1.4.1
  3.32.8   v3.32.8-tvos.1.0.0

$ flutter-tvos use 3.32.8
Switching flutter-tvos 3.44.7 -> 3.32.8 ...
  Flutter SDK  edada7c (3.32.8)
  Engine       v1.0.1-flutter3.32.8
```

`use` is not a stock Flutter verb, but it is the honest one: the name matches the action in every
case, which `upgrade --to 3.32.8` (a downgrade named upgrade) and `version` (which users read as
"print the version") do not.

## Architecture

The tag logic currently lives inside `TvosUpgradeCommandRunner`. Three new consumers make it its
own unit, with one clear purpose: know about release tags and move the checkout between them.

```
lib/tvos_releases.dart       TvosReleases, TvosRelease  — tags; knows nothing about commands
lib/commands/versions.dart   TvosVersionsCommand        — prints the list
lib/commands/use.dart        TvosUseCommand             — switches
lib/commands/downgrade.dart  TvosDowngradeCommand       — switches to the recorded previous tag
lib/commands/upgrade.dart    TvosUpgradeCommand         — keeps its flow, delegates discovery
lib/tvos_tool_state.dart     previous tag, for downgrade
```

`TvosUpgradeCommand` is **not** rewritten on top of `use`. Its two-phase
`--continue` flow is already tested and working; the change is narrow — the tag
discovery it does inline moves into `TvosReleases`, and it keeps calling it for
"newest". Restructuring it to share `use`'s single-phase flow is a behaviour
change disguised as a refactor, and is out of scope.

```dart
class TvosReleases {
  Future<List<TvosRelease>> list({bool fetch = true});
  Future<TvosVersion> current();
  Future<TvosRelease> resolve(String selector);
  Future<bool> hasUncommittedChanges();
  Future<void> checkout(String hash);
}

class TvosRelease {
  final String tag;            // v3.32.8-tvos.1.0.0
  final String flutterVersion; // 3.32.8
  final String toolVersion;    // 1.0.0
  final String hash;           // peeled commit SHA
}
```

`releaseTagPattern` gains capture groups; today it only matches.

`ProcessUtils` stays injectable throughout, as `TvosUpgradeCommandRunner` already does, so git
interaction is testable without a repository.

### State for `downgrade`

A small `TvosToolState` over `Config('flutter_tvos_state')`, storing the tag we switched away
from. `Config` resolves to `~/.config/flutter/`, **outside** `bin/cache` — which matters, because
`shared.sh` deletes `bin/cache` on every version change. Stock `PersistentToolState` is keyed by
`Channel`, which we do not have, so it is the wrong container.

## Data flow

### Discovery

`git fetch --tags` on a best-effort basis, then `git tag -l --sort=-v:refname`, then the regex
filter. A failed fetch is a warning and falls back to locally known tags — it does not fail the
command. This mirrors Flutter's own freshness check, which reduces network errors to trace logs
so the tool never breaks offline.

An explicit `versions` or `use` always attempts a fresh fetch; the user asked *now*. No TTL cache
— `git fetch --tags` against an up-to-date repo costs a fraction of a second, and fvm and nvm
both fetch on every explicit listing.

### Resolution

- `3.32.8` — a bare Flutter version — resolves to the newest `v3.32.8-tvos.*`.
- `v3.32.8-tvos.1.0.0` — an exact tag — resolves to itself.
- Anything else is an error listing the candidates. No prefix guessing.

Annotated tags are peeled with `^{commit}` before comparison, as `fetchLatestReleaseVersion`
already does — `git rev-parse` on an annotated tag yields the tag object's SHA, not the commit's.

### Switching

1. Resolve the selector to a tag and commit.
2. Refuse if the checkout has uncommitted changes, unless `--force`. Fail closed if git cannot be
   queried.
3. If already on the target, say so and exit 0.
4. Record the current tag in `TvosToolState`.
5. `git reset --hard <hash>`.
6. Shell out to `bin/flutter-tvos precache --force`, then `bin/flutter-tvos doctor`.

Step 6 is where this **deliberately differs from `upgrade`**. `upgrade` finishes through a
round-trip: it re-invokes `bin/flutter-tvos upgrade --continue` so the *new* tool runs the second
half. `use` cannot do that, because it would require the line being switched *to* to understand
`use --continue`. Shelling out directly to `precache` and `doctor` depends only on commands every
line already has, including 3.32.8's.

Re-bootstrapping needs no new code. On the next invocation `bin/internal/shared.sh` sees
`flutter.version` changed and re-checks-out the vendored SDK (wiping `bin/cache`), then sees
`tool_revision()` changed and runs `pub get` plus a snapshot recompile. That machinery already
exists and is exercised by `upgrade`.

## Cleanup of existing commands

`executable.dart` registers `DowngradeCommand` and `ChannelCommand` unchanged, in a block
commented "Commands forwarded directly from flutter_tools — these have no tvOS-specific
behaviour". That is wrong for both: stock `DowngradeCommand` sets
`workingDirectory = Cache.flutterRoot` and runs `git reset --hard` there, and `Cache.flutterRoot`
is the **vendored SDK**. This is the exact hazard `TvosUpgradeCommand` was written to avoid for
`upgrade`.

The damage is bounded — the next invocation's `update_flutter()` restores the pin — but the user
gets a silent revert plus a multi-minute re-bootstrap for nothing.

- `downgrade` is overridden to move the flutter-tvos checkout back to the previous tag. With no
  recorded previous version it reports that there is nothing to go back to and points at
  `versions`.
- `channel` is unregistered.

## Error handling

| Situation | Behaviour |
|---|---|
| Unknown version | Error listing available versions |
| Uncommitted changes | Refuse; suggest commit/stash or `--force` |
| `git status` fails | Fail closed — never treat an unknown tree as clean |
| Fetch fails during `versions` | Warn, list locally known tags |
| Fetch fails, target unknown locally | Hard error — cannot check out what we do not have |
| Already on target | Report and exit 0 |
| Switch succeeded, `precache` failed | State plainly that the checkout is already on the new version; give the command to finish by hand |

## Testing

Unit tests follow `test/general/tvos_upgrade_test.dart`, driving git through a fake
`ProcessUtils` so no repository is needed.

- `releaseTagPattern` — capture groups; rejects non-release tags.
- `resolve` — bare version picks the newest match; exact tag; unknown selector throws listing
  candidates; a version with no tvOS release is distinguished from a malformed selector.
- `list` — sorted newest-first; fetch failure yields a warning plus local tags; non-release tags
  filtered out.
- `use` — already-on-target is a no-op; dirty tree refused and `--force` overrides; previous tag
  recorded; `git reset --hard` invoked with the peeled commit.
- `downgrade` — no recorded state gives a helpful error; recorded state resolves to the right
  target.
- `versions` output marks exactly one line current, and none when HEAD is untagged.

`executable.dart` registration is asserted: `versions` and `use` present, `channel` absent.

## Consequences for the 3.32.8 port

The 3.32.8 release line must include `versions` and `use`. Without them a user who switches to
3.32.8 cannot switch back with the tool, only by hand — the trap this design exists to remove.
This is additional scope on the CLI port beyond the 21 analyzer errors.

## Out of scope

- Parallel installs of several versions side by side. One checkout, one active version — the
  flutter model. Users wanting concurrent versions clone twice.
- Per-project version pinning (an `.fvmrc` equivalent).
- A curation/yank manifest. Revisit only if a release actually has to be withdrawn.
