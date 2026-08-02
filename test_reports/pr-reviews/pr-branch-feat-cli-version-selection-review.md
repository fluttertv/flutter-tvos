# Review: `feat/cli-version-selection` — CLI version selection

**Branch:** `feat/cli-version-selection` (no PR open yet)
**Date:** 2026-08-02
**Reviewers:** 8 agents (6 domain-specific + 2 general). Copilot second opinion **unavailable** — the CLI exceeded its 5-minute budget without returning; this is an 8-agent review, not 9.
**Diff reviewed:** `git diff f25fda9...HEAD -- lib test` — 15 files, ~1700 insertions
**Areas touched:** git interaction, version resolution, command registration, tool state, tests

> The repo's `review-pr` skill is written for `litert_demo` — native ML runtime lifecycles,
> camera frame loops, KV-cache sizing, HuggingFace tokens. None of that exists in this CLI.
> The skill's *process* was followed (parallel agents, dedup, severity, report); its
> checklists were replaced with ones matching this change's actual failure classes.

## Verdict

**REQUEST CHANGES → resolved.** Four critical defects were found and fixed on the branch
(`8558d69`). All were reproduced before being believed. The suite is 318 green, the analyzer
is back at its 157-issue baseline with zero issues in new code, and the commands were
exercised live.

Remaining findings are logged below as follow-ups; none blocks a PR.

## Critical — all fixed in `8558d69`

### 1. `git reset --hard` destroyed committed-but-unpushed work

`lib/tvos_releases.dart` `checkout()`, reached from `use` and `downgrade`.

The dirty-tree guard runs `git status -s`, which reports **worktree** state and is silent
about the branch pointer. `git reset --hard` on an attached HEAD rewrites that pointer.
Reproduced on a scratch repo: `main` carrying a local commit, `git status -s` empty, guard
passes, reset runs, commit reachable from zero branches.

A contributor on `main` with unpushed work — or any user whose `main` is simply ahead of the
last release tag, the normal state between releases — loses it silently. The recovery line
did not help: it also named a tag, which would pin `main` there rather than restore it.

Fixed by `git checkout --force --detach`. Identical worktree, no ref touched. Verified
`rev-parse HEAD` (used by `shared.sh`'s `tool_revision`) and `describe --exact-match` both
work detached.

`upgrade` still uses `reset --hard` — see follow-ups.

### 2. The recovery command was word-wrapped into a command that lies

`lib/commands/use.dart`.

The stranding message went through `throwToolExit` → `printError`, which wraps to terminal
width (`shouldWrap: wrap ?? _outputPreferences.wrapText`). At 80 columns the line breaks, and
pasting it runs `git -C <path> ... --hard` with no revision: git resets to HEAD, **exits 0**,
and prints a reassuring `HEAD is now at …`. The user believes they recovered. They did not.
With the 40-char hash fallback — the untagged-HEAD case, i.e. the one with no breadcrumb —
the line breaks for any repo path over 17 characters.

The test could not have caught it: `BufferLogger.test()` defaults to `wrapText: false`.

Fixed: printed with `wrap: false`, and **unconditionally the moment the checkout moves**
rather than from the failure path, so a Ctrl-C, a dropped session, or a process that cannot
be spawned cannot take it away. A regression test now uses a logger configured to wrap at 40
columns.

### 3. `downgrade <version>` silently ignored the argument

`lib/commands/downgrade.dart`.

`runCommand` never inspected `argResults!.rest`. The command inherits `--force` from
`TvosUseCommand`, so `flutter-tvos downgrade 3.32.8 --force` skipped the dirty-tree guard,
discarded uncommitted work, and reset to the **recorded** tag rather than the one typed.
`use` trains users that a version goes on the command line, which makes this a likely mistake
rather than an exotic one. Stock `flutter downgrade` refuses positionals explicitly.

Fixed: refuses with exit code 2 and points at `flutter-tvos use <version>`.

### 4. A failing `git tag -l` produced a crash report instead of a tool exit

`lib/tvos_releases.dart` `list()`.

The only git call in the class without a catch. `ProcessException` escaped to flutter's
runner, which — since git *is* installed — routed it to `Oops; flutter has exited
unexpectedly`, a crash-report file, and an invitation to file a bug against flutter/flutter.
Triggered by anything git refuses to read: dubious ownership under another uid, or a checkout
with no `.git`, which `shared.sh` explicitly supports via its shasum fallback.

A regression: the pre-delegation `upgrade` wrapped fetch + tag-list + rev-parse in one catch.

Fixed, and the fetch warning no longer asserts a cause. It previously said "Could not reach
the flutter-tvos remote" for any non-zero exit — in this very checkout that is provably false
(the failure is a local `v1.0.0` tag conflict) and the message contradicted the git output
printed on the next line.

## Test defects — fixed

**Mutation testing found the suite blind to the invariant the feature exists to protect.**
`FakeCommand.workingDirectory` is ignored when null, and none of the 79 stubs set it. A
mutation redirecting `git reset --hard` **into the vendored `flutter/` SDK** passed every
test — verbatim the hazard `TvosUpgradeCommand` and `TvosDowngradeCommand` exist to prevent.
28 stubs now pin it.

**The real-git sort test was toothless.** Every component in its fixture was single-digit, so
`--sort=-refname` produced byte-identical output: it passed under a sort with no version
semantics at all, which is precisely what it was written to rule out. Fixed with 10-vs-9
pairs. Neither case is hypothetical — upstream Flutter has shipped 3.7.10 through 3.7.12, and
our tool version is at 1.4.2.

Coverage added for gaps that survived mutation: `--force` actually overriding the guard (the
error message advertised a flag nothing tested); the bootstrap call order, where moving the
`--version` probe after `precache` silently destroys the broken-toolchain vs failed-download
distinction; a precache failure reported as itself; `requireFetch`; the `git tag -l` failure;
and the wrapping regression.

## Also fixed

- **Dead code with a second authority for the tag grammar.** `latestReleaseTag` and
  `releaseTagPattern` had no production caller after the delegation but were kept alive by
  five tests, so the suite reported green coverage over a regex that ships to nobody while
  the live one lived elsewhere. Both agreed today; two authorities and a suite that stays
  green when only one changes is the hazard. Removed.
- **An escaped interpolation printed the literal `$e`** instead of the exception, on the
  highest-stakes error path in the feature. Self-inflicted during an earlier fix; caught by
  the analyzer's `unused_catch_clause` and by review.
- **Stale comments** describing `reset --hard` after the migration, and an internal
  "Task 8" planning reference in a doc comment.
- **A leftover `zz_probe_test.dart`** an implementation agent left untracked in `test/general`
  — it ran as part of the suite and printed probe output into it.
- `_bootstrapOrStranded` narrowed from `on Exception` to `on ProcessException`, matching what
  its own comment claims to guard.

## Follow-ups — not blocking

| | Finding |
|---|---|
| **1** | `upgrade` still uses `reset --hard` and has the same branch-clobbering exposure as critical #1. Out of scope here (its two-phase flow and tests are untouched by this branch), but the same class of user is affected. |
| **2** | `versions` marks nothing current when HEAD is on the *older* tool release of a Flutter version — the collapsed list keeps the newest tag and compares full tags. Four of nine tagged Flutter versions have two tool releases, so this is the ordinary state of anyone who has not upgraded within their line. |
| **3** | `git fetch --tags` will not update a re-pointed tag (`would clobber existing tag`, which this checkout hits today). A user who fetched a release that was later re-tagged silently stays on the withdrawn commit. `--force` or `--prune-tags` closes it. |
| **4** | The dirty-tree guard counts untracked files, which `checkout --force` would never touch. This checkout has three. Being blocked by files that were never at risk pushes users toward `--force`, which is all-or-nothing. |
| **5** | `upgrade` never records a previous tag, so `downgrade` after an `upgrade` jumps to whatever an earlier `use` recorded, while its help says it returns where you came from. |
| **6** | `use`/`versions`/`downgrade` do not set `shouldUpdateCache => false`, so they force an artifact update before running — including on a half-built toolchain, which is exactly when `versions` is most needed. Stock `UpgradeCommand` sets it. |
| **7** | `TvosToolState` write failures are trace-only, so losing `downgrade` is invisible; and `globals.fs` is an `ErrorHandlingFileSystem` that converts EACCES/ENOSPC to `ToolExit`, not `FileSystemException`, so the "never throws" contract does not hold in production for those cases. |
| **8** | `resolve()`'s "No release matches" is stated as fact even when the fetch failed and the list is known stale. |
| **9** | `git describe` flag order differs between `TvosReleases.current()` and `upgrade.dart`, and each test file stubs its own — so the suite actively forbids making them consistent. `upgrade.dart:161-193` is a near-duplicate of `current()` the refactor left behind. |
| **10** | Docs: `doc/commands.md` lists `downgrade` under "Not supported" — this branch ships it. `versions` and `use` appear in neither `doc/commands.md` nor `README.md`, so the feature is undiscoverable from either. |
| **11** | `versions` does not override `invocation`, so `flutter-tvos help versions` prints `Usage: flutter versions`. |

## Verified clean

- **Step ordering** — the already-on-target check precedes the dirty-tree guard, as the spec
  is emphatic about, and a fake-process test makes an out-of-order refactor fail rather than
  pass silently.
- **Fail-closed on unqueryable `git status`** — no path returns `false`; a missing git binary
  is safer still, since `ErrorHandlingProcessManager` exits before the catch is reached.
- **`^{commit}` peeling** at every site. The repo genuinely mixes tag kinds —
  `v3.41.9-tvos.1.0.1` is lightweight, `v3.44.0-tvos.1.1.0` is annotated and its `rev-parse`
  differs from its `^{commit}` — so dropping it would be a live bug.
- **State in `.git/`, never `~/.config`** — implemented, tested, and the only `.config`
  mention in `lib/` is the comment explaining why not.
- **`channel` unregistered, `downgrade` overridden** — asserted by a registration test that
  checks `runtimeType`, so a stock command cannot sneak back in.
- **Shallow clones** — not a problem; `git fetch --tags` deepens as needed and every
  subsequent operation succeeds.
- **Coupling surface shrank**, 75 → 73 private `flutter_tools/src/…` libraries. No new
  private import was added.
- **Registration equivalence** — mechanical diff of the extracted `tvosCommands()` against
  the previous inline closure shows only the four intended deltas.
- **Stream discipline** — warnings to stderr, the list to stdout, so `versions > list.txt`
  yields a clean pipeable list.

## Summary

- Critical: **4** — all fixed
- Test defects: **2 classes** — all fixed
- Follow-ups: **11** — none blocking
- Suite: 318 passing. Analyzer: 157, the pre-change baseline, none in new code.
- Recommendation: **APPROVE** for PR, with follow-ups 1, 2, 3 and 10 worth doing before
  the feature is announced to users.
