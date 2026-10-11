# Roadmap

Tracks the fork from `zigtools/zls`: what works and which upstream bugs apply here.

Zig version: 0.17.0.

Upstream state pulled 2026-10-11 via `gh issue list --repo zigtools/zls`
(162 open issues).

> **NOTE:**
> Status here is about zig-analyzer.

## Features (done)

| Feature | Status |
| :--- | :--- |
| completions | done |
| hover | done |
| goto definition / declaration | done |
| references | done |
| rename | done |
| document symbols | done |
| workspace symbols | done |
| semantic tokens | done |
| inlay hints | done |
| signature help | done |
| folding range | done |
| selection range | done |
| diagnostics (ast, ast-check, style, autofix) | done |
| code actions | done |
| build runner removal for 0.17.0 (upstream #3208: `--build-runner` gone, runner deleted, discovery + fallbacks kept) | done |
| `zls` refs rename to `zig-analyzer` (config, settings, CLI, build) | done |
| release workflow + install script | done |
| CI (build + coverage on 0.17.0) | done |

## Feature requests (upstream, not started)

| Request | Status |
| :--- | :--- |
| suggest dependencies and modules within build dependencies (upstream #3236, blocked on protocol) | not started |
| schema docs on hover + file completions for manifests (upstream #3233) | not started |
| reference counter as code lens (upstream #3230) | not started |
| `textDocument/hover` on `string_literal`s (upstream #2532) | not started |
| warnings for incorrect identifier casing (upstream #2485) | not started |
| selection range in hover (upstream #2460) | not started |
| primitive-type cast helpers (upstream #2361) | not started |
| auto-insert semicolon on newline (upstream #2347) | not started |
| move-to-file action (upstream #2335) | not started |
| doctest in hover popup (upstream #2322) | not started |
| hover verbosity level via proposed VS Code API (upstream #2318) | not started |
| code action that simplifies variable init (upstream #2098) | not started |
| type hint comment directives (upstream #2050) | not started |
| code action to create file (upstream #1941) | not started |
| per-project local config (upstream #1687) | not started |
| configurable snippets (upstream #1682) | not started |
| size/alignment/padding in type tooltips (upstream #1677) | not started |
| configurable autofix instead of on/off (upstream #1641) | not started |
| format-string support (upstream #1555) | not started |
| all computed error variants for `anyerror` catch captures (upstream #577) | not started |
| config for alternative build systems (upstream #357) | not started |
| auto-import (upstream #74) | not started |

## Enhancements (upstream, not started)

| Enhancement | Status |
| :--- | :--- |
| better `else` autocomplete in switch (upstream #3264) | not started |
| organize-imports everywhere-gating (upstream #3258) | not started |
| semantic token type for try/catch (upstream #3253) | not started |
| custom formatter config (upstream #3246) | not started |
| code action for doc-test stub (upstream #3244) | not started |
| built-in function examples (upstream #3235) | not started |
| naming convention consistency for lint/refactor (upstream #3234) | not started |
| document symbols outline for Zig + ZON (upstream #3232) | not started |
| dim unused private symbols (upstream #3231) | not started |
| unify `Analyser.Type` / `InternPool.Index` printing (upstream #3220) | not started |
| language features for imported zon (upstream #3212) | not started |
| tag mutable-item fields `mutable` (upstream #2649) | not started |
| enum_literal completion as error completion on error switch (upstream #2624) | not started |
| incremental compilation by default for build-on-save check (upstream #2617, blocked on protocol) | not started |
| synthesize check step for build-on-save (upstream #2616, blocked on protocol) | not started |
| symbol references inside std (upstream #2614, blocked on protocol) | not started |
| symbol references across build modules (upstream #2613, blocked on protocol) | not started |
| rust-analyzer runnables extension (upstream #2577) | not started |
| config file subdir on macOS (upstream #2563) | not started |
| test-driven completion (upstream #2544) | not started |
| MultiArrayList type info (upstream #2529) | not started |
| deprecate `semantic_tokens` for `augmentsSyntaxTokens` (upstream #2527) | not started |
| drop `textDocument/semanticTokens/full` (upstream #2483) | not started |
| error type in hover dialog (upstream #2471) | not started |
| vertical function completion (upstream #2452) | not started |
| signatureHelp for structs/tuples (upstream #2428) | not started |
| goto-def for `extern fn` (upstream #2424) | not started |
| declutter resolved type in hover (upstream #2367) | not started |
| auto-empty zls.log (upstream #2292) | not started |
| highlight references in format strings (upstream #2245) | not started |
| organize-imports: drop dup/unused (upstream #2240) | not started |
| infer `anytype` for fns like `std.mem.zeroInit` (upstream #2223) | not started |
| no inlay hints in `zig fmt: off` areas (upstream #2174) | not started |
| unused errors as warnings (upstream #2154) | not started |
| method detect by first-arg type (upstream #2137) | not started |
| more custom semantic token types/modifiers (upstream #2106) | not started |
| organize-imports placement flexibility (upstream #2100) | not started |
| comprehension via zig compilation system (upstream #2069, blocked on protocol) | not started |
| langref keyword hover (upstream #2062) | not started |
| suggest unimplemented methods in autocomplete (upstream #2053) | not started |
| better `typeDefinition` on functions (upstream #2052) | not started |
| reference-trace build-on-save locations (upstream #2018, blocked on protocol) | not started |
| no diagnostics for sema-dependent items (upstream #2017) | not started |
| no parens for function-pointer autocomplete (upstream #2012) | not started |
| no type completions for primitives (upstream #1995) | not started |
| inference through type-holding structs (upstream #1993) | not started |
| sort completions by result-location type (upstream #1845) | not started |
| `textDocument/rangeFormatting` support (upstream #1815) | not started |
| completion sort-by-name (upstream #1792) | not started |
| nested config options (upstream #1780) | not started |
| completion + goto for comptime-struct values (upstream #1724) | not started |
| constant functions as functions (upstream #1587) | not started |
| inlay hints for struct init (upstream #1531) | not started |
| chained autofixes (upstream #1490) | not started |
| type detection for if-expressions (upstream #1341) | not started |
| useful hover/goto fallback (upstream #1338) | not started |
| jump to absolute package source (upstream #1259) | not started |
| autofix for braceless ifs/loops/switch (upstream #1203) | not started |
| opt-in telemetry (upstream #1167) | not started |
| `type` resolution from call refs (upstream #1105) | not started |
| function/block scope in documentSymbol (upstream #825) | not started |
| code actions + autofix meta (upstream #689) | not started |

## Bugs

| Bug | Status |
| :--- | :--- |
| diagnostic `source` mismatch (`zig_analyzer` vs `zig-analyzer`) | done |
| build config loading stubbed out (was `DocumentStore.zig:1165`, `Server.zig:28`; runner removed, `@compileError` markers deleted, `build_files` map + associated config + no-op invalidate kept) | done |
| rename misses `asm` operands (upstream #3222; fixed: `referenceNode` scans non-arrow output operand tokens) | done |
| folding breaks on anon struct param (upstream #3254; fixed: skip param-list fold when inline container closes on `)` line) | done |
| references miss branching-type members (upstream #3262; fixed: expand `either` variants in reference scan + multi-seed field-access targets) | done |
| no completion for optional / ptr struct params (upstream #3259) | not started |
| wrong diagnostic when module named `build.zig` (upstream #3249) | not started |
| branching type keeps `noreturn` (upstream #3210; fixed with #3272 via `Type.fromEither` peer merge) | done |
| missing docs on root-module / error hover (upstream #3248, #3247) | not started |
| `for` + `break` typed as `noreturn` (upstream #3272; fixed: collect `else` + all `break` operands into `Type.fromEither`) | done |
| Nix `FileNotFound` with BSP-patched Zig (upstream #3271) | not started |
| bad `.Function` type on instantiated-namespace method call (upstream #3257) | not started |
| dot completion drops generic call binding (upstream #3205) | not started |
| completion assumes usage (upstream #3204) | not started |
| no enum branch-name autocomplete on switch (upstream #3202) | not started |
| no field completion for param structs (upstream #3196) | not started |
| module unresolved if absent from root.zig (upstream #3194, blocked on protocol) | not started |
| multiple modules break `@import` (upstream #3183, blocked on protocol) | not started |
| symlinks break `@import` (upstream #3182, blocked on protocol) | not started |
| no option to disable build runner (upstream #3176, stale post-removal) | not started |
| optional-pointer struct init unresolved (upstream #3160) | not started |
| addImport modules fail on atomic distros (upstream #2657, blocked on protocol) | not started |
| cross-file refs on file structs fail (upstream #2612) | not started |
| semantic tokens flicker theme on invalid code (upstream #2607) | not started |
| pointer inlay hint incomplete (upstream #2603) | not started |
| comptime-built types lack hints/completion (upstream #2583) | not started |
| runner chokes on dep-cache extras (upstream #2573, stale post-removal) | not started |
| misleading runner error on failed step (upstream #2572, stale post-removal) | not started |
| fn-pointer const not highlighted (upstream #2548) | not started |
| goto-def broken with Vim+ALE (upstream #2536) | not started |
| comptime-enum autocomplete broken (upstream #2515) | not started |
| missing/irrelevant `error.` completions (upstream #2499) | not started |
| `.zig`-suffixed module import fails (upstream #2472) | not started |
| MemoryPool methods lack hover/goto (upstream #2464) | not started |
| methods unrecognized in own file (upstream #2403) | not started |
| enum/union fn completions missing in slices (upstream #2393) | not started |
| no enum/decl-literal completion in switch target (upstream #2341) | not started |
| loadBuildConfiguration hangs on windows (upstream #2340, stale post-removal) | not started |
| invalid decl-literal usage with enums (upstream #2333) | not started |
| no completions after declarations on import (upstream #2283) | not started |
| build-on-save broken in subprojects (upstream #2276, stale post-removal) | not started |
| peer type `S` vs `??S` wrong (upstream #2273) | not started |
| no inference past 2 usage layers (upstream #2205) | not started |
| build-on-save diagnostics on missing import (upstream #2196, stale post-removal) | not started |
| camel_case warning lacks code action (upstream #2153) | not started |
| duplicated compile errors with build-on-save (upstream #2129, stale post-removal) | not started |
| multiline-fn hover formatting (upstream #2107) | not started |
| monorepo picks wrong root build.zig (upstream #2061, blocked on protocol) | not started |
| check diagnostics miss full type span (upstream #2060) | not started |
| goto-declaration fails on aliasing (upstream #2054) | not started |
| confusing inlay hints for unknown arrays (upstream #1886) | not started |
| inlay hints miss `self` param (upstream #1885) | not started |
| garbled `@cInclude` comments (upstream #1787) | not started |
| wrong hint on optional-orelse-error RHS (upstream #1728) | not started |
| autofix unused-param breaks empty fn (upstream #1725) | not started |
| format-on-save re-enabled after crash (upstream #1646) | not started |
| nested structs lack completion popup (upstream #1549) | not started |
| no switch-case completion in containers (upstream #1535) | not started |
| struct-init completion in nested struct (upstream #1525) | not started |
| `_` handling question (upstream #1390) | not started |
| bad inference on comptime-known slice (upstream #1230) | not started |
| semantic highlight shifts on active token (upstream #1144) | not started |
| global-var lint ignores file-structs (upstream #1117) | not started |
| completions die on recoverable error (upstream #1112) | not started |
| duplicate type definitions (upstream #1041) | not started |
| stall + leak on newline/comment replace (upstream #788) | not started |
| multi-folder workspace issues (upstream #705) | not started |
| no UTF-8 BOM handling (upstream #225) | not started |
| XDG_CONFIG_HOME ignored on macOS (upstream #3273) | not started |

## Blocked on new build-config protocol

`supports_build_system = false` until Zig's configure/make split gets a stable
consumer protocol (upstream #3208). These need it:
#3236, #3194, #3183, #3182, #2657, #2617, #2616, #2614, #2613, #2069,
#2061, #2018. Stale runner-era reports kept for history:
#3176, #2573, #2572, #2340, #2276, #2196, #2129.

## Performance

| Item | Status |
| :--- | :--- |
| 20s completion on `c` imports (upstream #3251) | not started |
| redundant work on large files (upstream #2237) | not started |
| perf measurement/tracking standard (upstream #1522) | not started |
| workspace symbol / trigram index bench | not started |

## Crash

| Crash | Status |
| :--- | :--- |
| pending file-io crash on windows (upstream #3193) | not started |
| coc.nvim connection drop (upstream #2068) | not started |

## Tracking (upstream, no action)

| Item | Status |
| :--- | :--- |
| release ZLS 0.17.0 (upstream #3267) | tracked |
| 0.17 release question (upstream #3274) | tracked |
| Zig AST parser limits (upstream #2346) | tracked |

## zig-analyzer 0.17.0 release

Scope: cut a stable tag on Zig 0.17.0.

Rule: `build.zig.zon` moves from `0.17.0-dev` to `0.17.0`.
Builds run with Zig 0.17.0 on all targets.

`supports_build_system = false` ships in this release.
Release notes list the blocked IDs from the section above.

### Release blockers (bugs)

| Bug | Status |
| :--- | :--- |
| wrong diagnostic when module named `build.zig` (upstream #3249) | planned |
| goto-declaration fails on aliasing (upstream #2054) | planned |
| cross-file refs on file structs fail (upstream #2612) | planned |
| methods unrecognized in own file (upstream #2403) | planned |
| MemoryPool methods lack hover/goto (upstream #2464) | planned |
| check diagnostics miss full type span (upstream #2060) | planned |
| no completion for optional / ptr struct params (upstream #3259) | planned |
| no field completion for param structs (upstream #3196) | planned |
| no enum branch-name autocomplete on switch (upstream #3202) | planned |
| no completions after declarations on import (upstream #2283) | planned |
| completions die on recoverable error (upstream #1112) | planned |
| Nix `FileNotFound` with BSP-patched Zig (upstream #3271) | planned |
| no UTF-8 BOM handling (upstream #225) | planned |
| XDG_CONFIG_HOME ignored on macOS (upstream #3273) | planned |

### Release blockers (crash + performance)

| Item | Status |
| :--- | :--- |
| pending file-io crash on windows (upstream #3193) | planned |
| coc.nvim connection drop (upstream #2068) | planned |
| stall + leak on newline/comment replace (upstream #788) | planned |
| 20s completion on `c` imports (upstream #3251) | planned |
| redundant work on large files (upstream #2237) | planned |

### Release chores

| Chore | Status |
| :--- | :--- |
| bump `.version` from `0.17.0-dev` to `0.17.0` in `build.zig.zon` | planned |
| fix README warning block (says Zig master, code pins 0.17.0) | planned |
| write release notes with `supports_build_system = false` + blocked IDs | planned |
| close stale runner-era reports as wontfix (#3176, #2573, #2572, #2340, #2276, #2196, #2129) | planned |
| verify `schema.json` and `install.sh` modes (`--dev`, `--local`, `--github`, `--uninstall`, `--prefix`, `--optimize`) | planned |
| verify 5 release archives (linux x2, macos x2, windows x1) + checksums | planned |
| editor smoke pass: helix, nvim, vscode, coc.nvim connect check | planned |
| run repro files (`issue_3222`, `issue_3254`, `issue_3272`, `issue_3262_branching_refs`) | planned |

### Deferred to 0.17.1

| Item | Status |
| :--- | :--- |
| all feature requests in the table above (none needed for parity) | deferred |
| all enhancements in the table above (polish work) | deferred |
| blocked-on-protocol work (needs Zig configure/make split) | deferred |
| perf benches (#1522, trigram bench) unless #3251 reproduces badly | deferred |
