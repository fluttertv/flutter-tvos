# PR Review: #11 — flutter-tvos v1.1.0 "the porter release"

**Repo:** fluttertv/flutter-tvos  
**Branch:** feat/plugin-port-tooling  
**Date:** 2026-05-25  
**Reviewers:** 7 agents (CLI layer, Dart/porter layer, Flutter architect, silent failure hunter, type design analyzer, general code reviewer, test coverage analyzer)  
**Layers affected:** CLI tool, plugin_porting/, build_targets, tvos_plugins, templates, tests

---

## Critical Issues

### C1. ObjC porter widens `#if !TARGET_OS_IOS` incorrectly — inverted logic
**File:** `lib/plugin_porting/objc_porter.dart`, Pass 1b  
The porter uses `replaceAll` unconditionally. `#if !TARGET_OS_IOS && SOME_OTHER` becomes `#if !(TARGET_OS_IOS || TARGET_OS_TV) && SOME_OTHER`, which silently excludes tvOS from macOS-only fallback paths. The plain `#if !TARGET_OS_IOS` case produces correct semantics by accident, but the compound `!TARGET_OS_IOS && X` pattern is wrong. Safe fix: do not widen lines containing `!TARGET_OS_IOS`; emit a `partial` finding for manual review instead.

### C2. `_packageRoot` — `TypeError` on malformed `rootUri` escapes all catch blocks
**File:** `lib/plugin_porting/source_fetcher.dart`, `_fetchPub`  
`(p['rootUri'] ?? '') as String` throws `TypeError` if JSON has a non-string type. This is not `SourceFetchError`, so it's not caught → raw stack trace to the user. Wrap `_packageRoot` call in try-catch converting `TypeError`/`StateError` to `SourceFetchError`.

### C3. Unreadable source files produce raw `FileSystemException` stack traces
**File:** `lib/plugin_porting/scaffolder.dart`, `_dartLibPlans` and native copy loop  
`readAsStringSync()` on symlink targets, permission-denied files, or broken paths throws `FileSystemException` not caught by `ScaffoldError` handler. Same in `source_analyzer.dart` `_derivePluginClass`. Wrap file-read loops in try-catch converting to `ScaffoldError`/`PluginSourceError`.

### C4. `git clone` stderr-only — stdout dropped, blank diagnostics on SSH failures
**File:** `lib/plugin_porting/source_fetcher.dart`, `_fetchGit`  
Error message includes only `r.stderr`. Some hosting providers write auth errors to stdout. Change to include both: `'stdout: ${r.stdout}\nstderr: ${r.stderr}'`.

### C5. `ApiPattern.stripImports` — Swift-only assumption invisible to ObjcPorter contributors
**File:** `lib/plugin_porting/compatibility_database.dart`  
ObjcPorter derives framework names by stripping the `import ` prefix (`imp.substring(7)`) from `stripImports` entries. An entry like `stripImports: ['#import <LocalAuthentication/LocalAuthentication.h>']` would silently produce wrong output with no test catching it. Rename field to `stripSwiftImports` or add a constructor `assert`.

### C6. No test: `#if !TARGET_OS_IOS` negation in ObjC porter
**File:** `test/general/plugin_port_objc_test.dart`  
The negation case (`#if !TARGET_OS_IOS`) and compound case (`#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR`) have zero test coverage. A refactor of Pass 1b could silently produce wrong tvOS guards.

### C7. No test: `dart pub get` non-zero exit code
**File:** `test/general/plugin_port_fetch_test.dart`  
Most common real-world failure (offline, private registry) has no coverage. A regression in the exit-code check produces a silent hang or Dart stack trace.

### C8. No test: idempotency of `#if os(iOS) || os(tvOS)` guard widening in Swift porter
**File:** `test/general/plugin_port_swift_test.dart`  
Input already containing `#if os(iOS) || os(tvOS)` is not tested. Removing the `t.contains('os(tvOS)')` guard would double-expand with no test to catch it.

---

## Important Issues

### I1. Temp dir leaked on non-`SourceFetchError` exceptions from `resolve()`
**File:** `lib/commands/plugin_port.dart`, `runCommand()`  
`tempWork` is only cleaned up in the `finally` of `_portResolvedSource`. If `resolve()` throws anything other than `SourceFetchError` (e.g. `ProcessException` from missing `git` binary), the outer `finally` is never reached. Fix: wrap the entire `tempWork` lifetime in one outer `try/finally`.

### I2. No `--pub-version` flag — always fetches latest version
**File:** `lib/plugin_porting/source_fetcher.dart`, `_fetchPub`  
`dart pub get` resolves `any`, so always gets the latest pub version. If a user's app pins `audioplayers_darwin: ^0.4.2`, the generated port is against the latest (e.g., `0.5.x`) and may be API-incompatible. `--from-git` has `--ref`; `--from-pub` has nothing equivalent.

### I3. `_walkPluginDependencies` called twice per build — double YAML parse
**File:** `lib/tvos_plugins.dart`  
Both `_discoverTvosPlugins` and `recommendTvosPluginsToInstall` independently call `_walkPluginDependencies`. All plugin pubspecs are parsed twice on every `run`/`build`/`test` invocation. Extract the call and pass the result to both consumers.

### I4. Missing-plugin warning fires on every hot-reload cycle
**File:** `lib/tvos_plugins.dart`, `ensureReadyForTvosTooling`  
No session deduplication. Users with a missing `*_tvos` plugin see the same warning on every `run` iteration. A simple session-static `Set<String>` or pubspec-mtime guard would suppress repeats.

### I5. `renderTvosRunner` silently skips when template is missing
**File:** `lib/commands/tvos_runner.dart`  
`!templateDir.existsSync()` returns `false` silently — user runs `flutter-tvos create`, gets no `tvos/` directory, no error. Emit `logger.printWarning('tvos/ template not found — your flutter-tvos installation may be incomplete.')`.

### I6. `ExamplePorter.port()` `FileSystemException` escapes `SourceFetchError` catch
**File:** `lib/commands/plugin_port.dart`, `_generateExample`  
Internal file-copy operations in `ExamplePorter` throw `FileSystemException`, not caught by the `on SourceFetchError` block. Add `on FileSystemException` handler that logs a warning and skips example generation.

### I7. `build()` override — unguarded `writeAsStringSync` for native_assets.json stub
**File:** `lib/build_targets/application.dart`, `TvosCopyFlutterBundle.build()`  
If the build dir is read-only, the write throws `FileSystemException` uncaught. Wrap in try-catch with `throwToolExit(...)`.

### I8. `_pubspecVersion` `readAsLinesSync()` unguarded — TOCTOU `FileSystemException`
**File:** `lib/commands/plugin_port.dart`, `_pubspecVersion`  
File existence checked with `existsSync()` then read synchronously — race possible; also `FileSystemException` from permissions escapes all catches. Wrap read in try-catch returning `null`.

### I9. `file://` URIs in `_walkPluginDependencies` stored verbatim — silent plugin drop
**File:** `lib/tvos_plugins.dart`  
`file:///absolute/path` passed directly to `globals.fs.file()` produces a broken path. Decode via `Uri.parse(rootUri).toFilePath()`. Add `printTrace` for unrecognised URI schemes.

### I10. `SwiftPorter`/`ObjcPorter` instantiated inside `Scaffolder.scaffold()` — blocks unit testing
**File:** `lib/plugin_porting/scaffolder.dart`  
Direct instantiation prevents injecting controlled porter outputs in tests. Accept optional `SwiftPorter?` and `ObjcPorter?` constructor parameters with real instances as defaults.

### I11. `_pubspecVersion` fallback `'0.0.0'` produces unresolvable `^0.0.0` constraint
**File:** `lib/commands/plugin_port.dart`, `_generateExample`  
For packages without a version field, generated example pubspec has `basePlugin: ^0.0.0`. `pub get` fails to resolve. Fall back to `any` instead of `'0.0.0'`.

### I12. `AVAudioSessionOptions` severity `unsupported` — symbols exist on tvOS 17+
**File:** `lib/plugin_porting/compatibility_database.dart`  
`unsupported` means "cannot compile." The note explicitly says `.allowBluetooth`/`.allowBluetoothA2DP` exist from tvOS 17.0. Should be `partial` to allow already-gated code to pass through. Similarly `StatusBar` severity should be `partial` (compiles, no visible effect).

### I13. `_CompiledPattern` duplicated in both `swift_porter.dart` and `objc_porter.dart`
**File:** both porter files  
Identical private class. Move to `porting_result.dart` (shared contract module).

### I14. Swift porter: `@available` with two clauses on one line — second clause not widened
**File:** `lib/plugin_porting/swift_porter.dart`, Pass 1d  
Outer `line.contains('tvOS ')` guard skips the whole line when any clause already has tvOS, missing the second non-tvOS clause. Drop outer guard; rely on inner per-clause check.

### I15. Swift porter `#if(os(iOS))` (no space) not widened
**File:** `lib/plugin_porting/swift_porter.dart`, Pass 1b  
`startsWith('#if ')` misses the no-space variant `#if(os(iOS))`. ObjC porter handles both forms. Rare but a real inconsistency in correctness claims.

### I16. `@available` regex can't span newlines — multi-line attributes silently skipped
**File:** `lib/plugin_porting/swift_porter.dart`  
`[^)]*` doesn't cross newlines. Multi-line `@available` (seen in Pigeon-generated code) bypasses widening → tvOS compiler error.

### I17. `_scrubReferencesToDropped` doesn't handle `part` directives
**File:** `lib/plugin_porting/scaffolder.dart`  
Regex matches `import`/`export` only. A `part 'src/foo_io.dart'` pointing to a dropped file survives in output → broken package.

### I18. No test: nested `#if` + `@available` combined widening
**File:** `test/general/plugin_port_swift_test.dart`  
Pass 1b and Pass 1d are independent but no test verifies they compose correctly.

### I19. No test: already-guarded `TARGET_OS_TV` input for ObjC porter
**File:** `test/general/plugin_port_objc_test.dart`  
Idempotency of ObjC `#if` directive widening is untested.

### I20. `TvosAppScaffold` has zero test coverage
**File:** `lib/commands/tvos_app_scaffold.dart`  
~200 lines of scaffold logic, no tests. Idempotency guard (`_put`) and template rendering untested.

---

## Minor Issues

### M1. `FindingAction.taggedWithTodo` defined but never emitted — dead code or undocumented placeholder
**File:** `lib/plugin_porting/porting_result.dart`

### M2. `PortingResult.strippedImports` redundant — derivable from `findings.where(importStripped)`
**File:** `lib/plugin_porting/porting_result.dart`

### M3. `args.contains('create')` matches anywhere in arg list — positionally imprecise
**File:** `lib/tvos_platform_args.dart`  
Use `args.isNotEmpty && args[0] == 'create'` or similar positional check.

### M4. `category = 'Tools'` on subcommand — upstream doesn't categorize subcommands
**File:** `lib/commands/plugin_port.dart`

### M5. Native-assets empty-manifest format is a hardcoded string literal — fragile if Flutter changes schema
**File:** `lib/build_targets/application.dart`

### M6. Warning fires on `dev_dependency` path-override `_tvos` packages (false negative only)
**File:** `lib/tvos_plugins.dart`  
`depGraph` only contains packages with `flutter.plugin:` block. A `path:`-override `*_tvos` package as dev dependency might not appear.

### M7. `scaffold()` `deleteSync(recursive: true)` for `--force` unguarded
**File:** `lib/plugin_porting/scaffolder.dart`

### M8. `source_analyzer.dart` — non-map YAML produces `TypeError` past `YamlException` catch
**File:** `lib/plugin_porting/source_analyzer.dart`  
Change catch to `on Object` and re-throw as `PluginSourceError`.

### M9. `template.render()` in `tvos_runner.dart` unguarded — partial output dir on disk error
**File:** `lib/commands/tvos_runner.dart`

### M10. `// ignore: avoid_unused_constructor_parameters` on `verboseHelp` — forward it instead
**File:** `lib/commands/plugin.dart`

### M11. `ReportEmitter`: `manualReviewCount` computed from separate traversal — can diverge from rendered items
**File:** `lib/plugin_porting/report_emitter.dart`

### M12. `SourceSpec.derivedName` uses `split('/')` — breaks for Windows backslash paths
**File:** `lib/plugin_porting/source_fetcher.dart`  
Low risk (macOS-only tooling) but assumption is implicit.

### M13. `ExamplePorter.port()`: generated example depends on `$base: any` → may trigger flutter-tvos "missing tvOS support" warning
**File:** `lib/plugin_porting/native_skeleton.dart`

### M14. No test: `ReportEmitter` with multiple `PortingResult` items — aggregation logic untested
**File:** `test/general/` — all report tests pass single-item lists.

---

## Passed Checks

- Engine-only separation: no `dart.library.*` or `#if` compile-time checks in any new Dart file. ✓
- `expandTvosPlatformArgs` is pure with no I/O — registration order safe. ✓
- `-allowProvisioningUpdates` correctly gated on `!buildInfo.simulator`. ✓
- `SourceSpec` mutual-exclusivity enforced at parse time via private constructor. ✓
- Compat DB: `stripSwiftImports` entries not causing false positives. ✓
- `FLTAssetsPath` key name verified correct against Flutter engine source. ✓
- `SwiftPorter`/`ObjcPorter` are stateless across calls — thread-safe. ✓
- `ReportEmitter` is a pure stateless renderer — correct design. ✓
- All new Dart files use `MemoryFileSystem.test()` for isolation. ✓
- Compat DB test enforces positive+negative sample per pattern. ✓

---

## Summary

| Severity | Count |
|---|---|
| Critical | 8 |
| Important | 20 |
| Minor | 14 |

**Recommendation: REQUEST CHANGES**

Must-fix before merge (top 5):
1. **C1** `objc_porter.dart` — `#if !TARGET_OS_IOS` inverted logic in compound guards
2. **C5** `compatibility_database.dart` — `stripImports` Swift assumption silent for ObjC
3. **I1** `plugin_port.dart` — temp dir leak on non-`SourceFetchError` from `resolve()`
4. **I16** `swift_porter.dart` — multi-line `@available` silently skipped
5. **I17** `scaffolder.dart` — `part` directives not scrubbed → broken output package
