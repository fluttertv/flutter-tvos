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

git tags also degrade best offline: previously fetched tags stay listable and the checkout itself
succeeds, which no manifest or API gives. And git's tag store is the on-disk cache — no TTL file
to invalidate. Not subject to REST rate limits, since git smart-HTTP is a different path.

That offline claim has a limit worth stating plainly, because it is easy to over-promise: the
`git reset` works offline, but the re-bootstrap that follows runs `pub get` for the target
version's dependency set. `shared.sh` tries `pub get --offline` before the online one, so
switching *back* to a version whose dependencies are already in the pub cache generally works
offline; switching to one never used on that machine does not. Offline switching is a
best-effort property of previously-used versions, not a guarantee.

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
  3.44.5   v3.44.5-tvos.1.4.0
  3.32.8   v3.32.8-tvos.1.0.0

$ flutter-tvos use 3.32.8
Switching flutter-tvos 3.44.7 -> 3.32.8 ...
  Flutter SDK  edada7c (3.32.8)
  Engine       v1.0.1-flutter3.32.8
```

**One line per Flutter version, showing its newest tool release.** This is not a corner case to
leave unspecified: four of the nine Flutter versions currently tagged (`3.41.9`, `3.44.0`,
`3.44.1`, `3.44.5`) have two tool releases each. Collapsing to the newest matches how `use 3.44.5`
resolves, so the list shows exactly what a bare selector would pick. `versions --all` lists every
release tag ungrouped, for when the tool version matters.

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

The previous tag is written to **`.git/flutter-tvos-previous`** inside the checkout being
switched.

Three constraints pick that location, and only it satisfies all three. The file must survive
`git reset --hard` (so not a tracked path), must survive `shared.sh` deleting `bin/cache` on every
version change (so not there), and must be **per-checkout**. The third is what rules out
`~/.config/flutter/`, the obvious choice: this design tells users who want concurrent versions to
clone twice, and a single global state file would have `downgrade` in one clone jump to wherever
the other clone last came from. `.git/` is outside the worktree, is never committed, and exists
once per clone.

Stock `PersistentToolState` is both global and keyed by `Channel`, which we do not have, so it is
the wrong container on two counts.

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
2. If already on the target, say so and exit 0. **Before** the dirty-tree check, not after — a
   user with local edits who names the version they are already on should not be refused an
   operation that would do nothing.
3. Refuse if the checkout has uncommitted changes, unless `--force`. Fail closed if git cannot be
   queried.
4. Record the current tag in `.git/flutter-tvos-previous`.
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

### Stranding, and how the switch stays escapable

Step 5 is the point of no return, and the design has to be honest about what lies past it. The
re-bootstrap in step 6 compiles the *target* line's source. If that source does not compile — a
defect in a freshly ported line, a `pub get` that cannot resolve, a Dart SDK mismatch — there is
no working snapshot afterwards, so `flutter-tvos use <previous>` cannot run. The user is stranded
on a version they cannot leave with the tool, which is precisely the situation this feature
exists to remove.

This is not a remote edge case. It is likeliest exactly when someone first switches to a
newly-ported old line, because that is the least-exercised source in the repo.

Two requirements follow.

**The failure must name its own undo.** When the step-6 bootstrap fails, print the literal
recovery command with the previous tag already substituted:

```
Switched to 3.32.8, but the toolchain failed to build for it.
Your checkout is on v3.32.8-tvos.1.0.0; the flutter-tvos command will not work
until this is resolved.

To return to the version you came from:
  git -C /path/to/flutter-tvos reset --hard v3.44.7-tvos.1.4.2
```

The previous tag comes from `.git/flutter-tvos-previous`, which survives precisely because it
lives outside the worktree — the reason for that location, not an incidental benefit.

**The message must come from the outer process.** The stranded tool cannot print it, so `use`
runs step 6 as a subprocess and reports the failure itself rather than delegating to a
`--continue` round-trip. This is a second, independent reason for the `precache`/`doctor`
shell-out described above; even if every line understood `use --continue`, the round-trip would
put the error message in the mouth of the process that just failed to exist.

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
| Already on target | Report and exit 0, checked before the dirty-tree guard |
| Switch succeeded, `precache` failed | State plainly that the checkout is already on the new version; give the command to finish by hand |
| Switch succeeded, target toolchain will not build | Print the literal `git reset --hard <previous-tag>` recovery line — see "Stranding" above |

## Testing

Unit tests follow `test/general/tvos_upgrade_test.dart`, driving git through a fake
`ProcessUtils` so no repository is needed.

- `releaseTagPattern` — capture groups; rejects non-release tags.
- `resolve` — bare version picks the newest match; exact tag; unknown selector throws listing
  candidates; a version with no tvOS release is distinguished from a malformed selector.
- `list` — fetch failure yields a warning plus local tags; non-release tags filtered out;
  collapses to one entry per Flutter version at its newest tool release, with `--all` ungrouped.
- `use` — already-on-target is a no-op **even with a dirty tree**, pinning the step ordering;
  dirty tree otherwise refused and `--force` overrides; previous tag recorded before the reset;
  `git reset --hard` invoked with the peeled commit.
- `downgrade` — no recorded state gives a helpful error; recorded state resolves to the right
  target.
- `versions` output marks exactly one line current, and none when HEAD is untagged.
- Bootstrap failure after a switch prints the recovery command containing the previous tag.

One ordering test does not use a fake: `git tag -l --sort=-v:refname` must place
`v3.44.5-tvos.1.4.0` above `v3.44.5-tvos.1.3.3` and `v3.44.7-*` above `v3.44.6-*`. Both `upgrade`
(already shipped) and `resolve` assume this ordering and neither pins it, while git's
`versionsort.suffix` configuration can change how a `-tvos.N` suffix is ranked. Run it against a
temporary repository with the tags created, so the assumption is verified rather than trusted.

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
