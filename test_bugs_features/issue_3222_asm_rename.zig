//! Upstream zigtools/zls#3222: rename misses `asm` operands.
//!
//! status: fixed. rename `bar` -> `dummy` now rewrites all 3 uses.
//!
//! helix/nvim manual check:
//!   1. `hx/nvim test_bugs_features/issue_3222_asm_rename.zig`
//!   2. put cursor on any `bar`, trigger lsp rename to `dummy`
//!   3. all `bar` turn into `dummy`, including the operand `(bar)`

pub fn main() void {
    var bar: u64 = 5;
    const refr = bar + 4;
    _ = refr;
    asm volatile (
        \\ mov $5, %rax
        : [ret] "={rax}" (bar),
    );
}
