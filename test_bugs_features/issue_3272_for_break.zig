//! Upstream zigtools/zls#3272: `for` + `break` typed as `noreturn`.
//!
//! helix manual check:
//!   1. `hx test_bugs_features/issue_3272_for_break.zig`
//!   2. hover over `x` -> bug: `noreturn`, fixed: `u32`
//!   3. completions on `x.` (after changing the print to a use site) follow `u32`
//!
//! cli check: `zig run test_bugs_features/issue_3272_for_break.zig`
//! prints `x = 4`, proving the type is `u32` at runtime.

const std = @import("std");

pub fn main() !void {
    const S = struct {
        x: u32,
    };
    const ses: []const S = &.{ .{ .x = 1 }, .{ .x = 2 }, .{ .x = 3 }, .{ .x = 4 } };
    const x = for (ses) |s| {
        if (s.x == 4) break s.x;
    } else {
        return;
    };
    std.debug.print("x = {d}\n", .{x});
}
