<!--
  ⚠️ Base branch: PRs must target `dev`, not `main`.
  `main` only receives release merges from `dev`. If your PR targets `main`,
  edit the base branch (Edit button next to the PR title) before requesting review.
-->

## What does this PR do?

<!-- A clear description of the change and the motivation behind it.
     Link related issues: "Fixes #123" / "Part of #123". -->

## How was it tested?

<!-- Check all that apply and describe the setup (tvOS/Xcode versions, device model). -->

- [ ] `flutter/bin/dart test test/` passes
- [ ] `flutter/bin/dart analyze lib/` is clean
- [ ] Verified on tvOS **simulator**
- [ ] Verified on a **physical Apple TV**

## Checklist

- [ ] This PR targets the **`dev`** branch (not `main`)
- [ ] Added an entry to `CHANGELOG.md` under **`[Unreleased]`** (user-visible changes only; no version bump — maintainers assign versions at release)
- [ ] Added or updated tests covering the change (or explained below why none are needed)
- [ ] If the change touches generated plugin registrants or app templates: **both** the ObjC and Swift variants are updated
- [ ] No changes under `flutter/` or `engine_artifacts/` (managed directories — see CONTRIBUTING.md)

## Notes for reviewers

<!-- Anything that needs extra attention: trade-offs, follow-ups, areas you're unsure about. -->
