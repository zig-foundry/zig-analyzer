# Roadmap

Tracks the fork from `zigtools/zls`: what works and which upstream bugs apply here. Zig version: 0.17.0.

## Features

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
| build runner integration (upstream #3208) | not started |
| `zls` refs rename to `zig-analyzer` (config, settings, CLI, build) | done |
| release workflow + install script | done |
| CI (build + coverage on 0.17.0) | done |

## Bugs

| Bug | Status |
| :--- | :--- |
| diagnostic `source` mismatch (`zig_analyzer` vs `zig-analyzer`) | done |
| build config loading stubbed out (`DocumentStore.zig:1165`, `Server.zig:28`) | not started |
| rename misses `asm` operands (upstream #3222) | not started |
| folding breaks on anon struct param (upstream #3254) | not started |
| references miss branching-type members (upstream #3262) | not started |
| no completion for optional / ptr struct params (upstream #3259) | not started |
| wrong diagnostic when module named `build.zig` (upstream #3249) | not started |
| branching type keeps `noreturn` (upstream #3210) | not started |
| missing docs on root-module / error hover (upstream #3248, #3247) | not started |
| `for` + `break` typed as `noreturn` (upstream #3272) | not started |

## Performance

| Item | Status |
| :--- | :--- |
| 20s completion on `c` imports (upstream #3251) | not started |
| workspace symbol / trigram index bench | not started |
