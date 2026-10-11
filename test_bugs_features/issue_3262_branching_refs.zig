//! Upstream zigtools/zls#3262: references miss branching-type members.
//!
//! status: fixed. rename on `Foo.a` now touches both `const a` decls.
//!
//! helix manual check:
//!   1. `hx test_bugs_features/issue_3262_branching_refs.zig`
//!   2. put cursor on the `a` in `Foo.a`, press `Space-r`, rename to `b`
//!   3. bug: only the first `const a` changed; fixed: both change + use site
//!   4. press `gr` on `Foo.a` -> picker lists 3 hits (2 decls + 1 use)
//!
//! nvim manual check (default 0.11 keys, adjust for your config):
//!   1. `nvim test_bugs_features/issue_3262_branching_refs.zig`
//!   2. on `Foo.a` press `grn`, type `b`, press `<CR>`
//!   3. both `const a` lines plus the use turn into `b`
//!   4. press `grr` on `Foo.a` -> quickfix lists 3 hits
//!
//! vscode manual check:
//!   1. open the file, right-click `a` in `Foo.a`
//!   2. `Rename Symbol` (`F2`), type `b`, press `<CR>`
//!   3. both decls plus the use update
//!   4. `Find All References` (`Shift+F12`) lists 3 hits
//!
//! automated check:
//!   `zig build test` runs `tests/lsp_features/references.zig:"branching type members"`

const Foo = if (true) struct {
    const a = 0;
} else struct {
    const a = 0;
};

pub fn main() void {
    _ = Foo.a;
}
