//! Repro project for the 0.17.0 fork blocker (upstream zigtools/zls#3208).
//!
//! Zig 0.17 dropped `zig build --build-runner`, so zig-analyzer no longer
//! executes build.zig. This project checks the fallback still works:
//!
//! helix manual check:
//!   1. `hx test_bugs_features/build_blocker_3208/src/main.zig`
//!   2. hover over `helperValue` -> shows `u32` from helper.zig (relative import)
//!   3. goto-definition on `helperValue` -> jumps to src/helper.zig
//!   4. hover over `std` -> resolves to the Zig 0.17.0 std lib
//!   5. completions inside `@import("...")` list `std` and `builtin`
//!   6. no crash, no "import of file outside module path" diagnostic,
//!      and no hang on the `@import("my_module")` line (named modules
//!      report `.none` until a new configuration protocol lands)
//!
//! cli check:
//!   `zig build-exe test_bugs_features/build_blocker_3208/src/main.zig -fno-emit-bin`
//!   must exit 0 (the fixture itself is valid Zig 0.17 code, except the
//!   `my_module` line which is commented out so the file compiles).

const std = @import("std");
const builtin = @import("builtin");
const helper = @import("helper.zig");

// Named build.zig module: analyzer must stay silent, not crash.
// const my_module = @import("my_module");

pub fn main() void {
    const helperValue: u32 = helper.value;
    std.debug.print("helper={d} os={s}\n", .{ helperValue, @tagName(builtin.os.tag) });
}
