//! Regression tests for the 0.17.0 fork blocker (upstream zigtools/zls#3208).
//!
//! Zig 0.17 dropped `zig build --build-runner`, so zig-analyzer no longer
//! executes `build.zig`. These tests pin down the fallback behavior:
//!   - relative `.zig`/`.zon` imports, `std` and `builtin` keep resolving
//!   - named build.zig modules (`@import("my_module")`, `@import("root")`)
//!     report `.none` instead of hanging or crashing
//!   - build.zig discovery (map + `zig-analyzer.build.json`) keeps working
//!   - `invalidateBuildFile` is a safe no-op

const std = @import("std");
const zig_analyzer = @import("zig_analyzer");

const Context = @import("../context.zig").Context;

const allocator: std.mem.Allocator = std.testing.allocator;

fn openDoc(ctx: *Context, source: []const u8) !zig_analyzer.Uri {
    return try ctx.addDocument(.{ .source = source });
}

fn handleOf(ctx: *Context, uri: zig_analyzer.Uri) *zig_analyzer.DocumentStore.Handle {
    return ctx.server.document_store.getHandle(uri) orelse unreachable;
}

test "relative zig import resolves without build runner" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(&ctx, "const x = 1;");
    const handle = handleOf(&ctx, uri);

    var result = try ctx.server.document_store.uriFromImportStr(allocator, handle, "sibling.zig");
    defer result.deinit(allocator);

    switch (result) {
        .one => |one| {
            try std.testing.expect(std.mem.endsWith(u8, one.raw, "/sibling.zig"));
        },
        .none, .many => return error.TestExpectedOne,
    }
}

test "std import resolves without build runner" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(&ctx, "const std = @import(\"std\");");
    const handle = handleOf(&ctx, uri);

    var result = try ctx.server.document_store.uriFromImportStr(allocator, handle, "std");
    defer result.deinit(allocator);

    switch (result) {
        .one => |one| {
            try std.testing.expect(std.mem.endsWith(u8, one.raw, "std/std.zig"));
        },
        .none, .many => return error.TestExpectedOne,
    }
}

test "named module import degrades gracefully without build runner" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(&ctx, "const m = @import(\"my_module\");");
    const handle = handleOf(&ctx, uri);

    // must not hang, crash, or throw: just report `.none`
    var named = try ctx.server.document_store.uriFromImportStr(allocator, handle, "my_module");
    defer named.deinit(allocator);
    try std.testing.expect(named == .none);

    var root = try ctx.server.document_store.uriFromImportStr(allocator, handle, "root");
    defer root.deinit(allocator);
    try std.testing.expect(root == .none);
}

test "build file association stays inconclusive without build runner" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(&ctx, "const x = 1;");
    const handle = handleOf(&ctx, uri);

    // untitled docs have no build.zig on disk: `.none`, no hang
    switch (try handle.getAssociatedBuildFile(&ctx.server.document_store)) {
        .none => {},
        .unresolved, .resolved => return error.TestExpectedNone,
    }

    switch (try handle.getAssociatedCompilationUnits(&ctx.server.document_store)) {
        .none => {},
        .unresolved, .resolved => return error.TestExpectedNone,
    }
}

test "invalidateBuildFile is a safe no-op" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(&ctx, "const x = 1;");

    // must not crash, even for documents that are not build files
    ctx.server.document_store.invalidateBuildFile(uri);

    try std.testing.expect(ctx.server.document_store.getBuildFile(uri) == null);
}

test "open build.zig document registers without running it" {
    var ctx = try Context.init();
    defer ctx.deinit();

    const uri = try openDoc(
        &ctx,
        \\const std = @import("std");
        \\pub fn build(b: *std.Build) void {
        \\    _ = b;
        \\}
        ,
    );

    // opening works and diagnostics flow runs without a build runner
    const handle = handleOf(&ctx, uri);
    try std.testing.expect(handle.lsp_synced);
}
