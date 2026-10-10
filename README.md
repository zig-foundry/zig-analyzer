<img src="https://raw.githubusercontent.com/zigtools/zls/master/.github/assets/zls-opt.svg" alt="zig-analyzer Logo" width=200>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# zig-analyzer

`zig-analyzer` is an implementation of the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) for [Zig](https://ziglang.org/) written in Zig. It provides developers with IDE features in their editor.

## About This Fork

This project started as a fork of [ZLS](https://github.com/zigtools/zls). We are continuing development independently under the [Zig Foundry](https://github.com/zig-foundry) project to focus on:

- Faster indexing and search speeds
- Lower memory usage during large builds
- New editor features and experimental tools

We still respect and follow upstream Zig changes, but development here moves at its own pace.

---

## Installation

### Build From Source

> [!WARNING]
> `zig-analyzer` targets [Zig master](https://ziglang.org/download/). Make sure your Zig compiler is up to date before building.

```bash
git clone --recurse-submodules https://github.com/zig-foundry/zig-analyzer.git
cd zig-analyzer
zig build -Doptimize=ReleaseSafe

```

The compiled binary will be placed in `zig-out/bin/`.

When upgrading Zig, make sure to update `zig-analyzer` too so both stay in sync.

---

## Features

`zig-analyzer` supports most language features, including simple type function support, payload capture type resolution, custom packages, and others. Support for comptime and semantic analysis is work in progress.

Supported LSP features:

* Completions
* Hover
* Diagnostics and build-on-save
* Go to definition/declaration
* Workspace symbols and document symbols
* Find references and rename symbol
* Formatting based on `zig fmt`
* Semantic tokens highlighting
* Inlay hints
* Code actions

---

## Credits & Thanks

This project exists thanks to the original work done by the [ZLS contributors](https://github.com/zigtools/zls/graphs/contributors). We thank everyone who built and maintained ZLS over the years.
