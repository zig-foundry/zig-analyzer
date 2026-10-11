//! A thread-safe container for all document related state like zig source files including `build.zig`.

const std = @import("std");
const builtin = @import("builtin");
const Uri = @import("Uri.zig");
const analysis = @import("analysis.zig");
const offsets = @import("offsets.zig");
const log = std.log.scoped(.store);
const lsp = @import("lsp");
const Ast = std.zig.Ast;
const BuildAssociatedConfig = @import("BuildAssociatedConfig.zig");
const tracy = @import("tracy");
const DocumentScope = @import("DocumentScope.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
const TrigramStore = @import("TrigramStore.zig");

const DocumentStore = @This();

io: std.Io,
allocator: std.mem.Allocator,
/// the DocumentStore assumes that `config` is not modified while calling one of its functions.
config: Config,
mutex: std.Io.Mutex = .init,
wait_group: if (supports_build_system) std.Io.Group else void = if (supports_build_system) .init else {},
handles: Uri.ArrayHashMap(*Handle.Future) = .empty,
/// Every known `build.zig`, found by walking up from open documents.
/// The map is always live: discovering build files only reads
/// `zig-analyzer.build.json`, it never executes `build.zig`.
/// (Executing it needed the removed build runner.)
build_files: Uri.ArrayHashMap(*BuildFile) = .empty,
diagnostics_collection: *DiagnosticsCollection,
builds_in_progress: std.atomic.Value(i32) = .init(0),
transport: ?*lsp.Transport = null,
lsp_capabilities: struct {
    supports_work_done_progress: bool = false,
    supports_semantic_tokens_refresh: bool = false,
    supports_inlay_hints_refresh: bool = false,
} = .{},

/// Whether build.zig files are executed to resolve modules, dependencies and compilation units.
/// Disabled on purpose: Zig 0.17 removed the `--build-runner` flag when the build
/// system was split into a separate configure and make phase (upstream issue
/// https://github.com/zigtools/zls/issues/3208). Upstream ZLS removed the build
/// runner instead of porting it, and this fork follows that decision.
/// `@import` of relative `.zig`/`.zon` files, `std` and `builtin` keep working.
/// Named modules from `build.zig` (`@import("my_module")`, `@import("root")`)
/// cannot be resolved until a new configuration protocol is implemented.
pub const supports_build_system = false;

pub const Config = struct {
    environ_map: *const std.process.Environ.Map,
    zig_exe_path: ?[]const u8,
    zig_lib_dir: ?std.Build.Cache.Directory,
    builtin_path: ?[]const u8,
    global_cache_dir: ?std.Build.Cache.Directory,
    wasi_preopens: switch (builtin.os.tag) {
        .wasi => std.process.Preopens,
        else => void,
    },
};

/// Represents a `build.zig`
pub const BuildFile = struct {
    uri: Uri,
    /// this build file may have an explicitly specified path to builtin.zig
    builtin_uri: ?Uri = null,
    /// config options extracted from zig-analyzer.build.json
    build_associated_config: ?std.json.Parsed(BuildAssociatedConfig) = null,
    impl: struct {
        mutex: std.Io.Mutex = .init,
    } = .{},

    /// Returns whether the `Uri` is a dependency of the given `BuildFile`.
    /// Always returns `.unknown`: without a build runner there is no module graph
    /// to check membership against (see `supports_build_system`).
    /// Callers treat `.unknown` as "cannot prove association", same as before
    /// when the build config had not been resolved yet.
    ///
    /// **Thread safe** takes an exclusive lock
    fn isAssociatedWith(
        build_file: *BuildFile,
        uri: Uri,
        store: *DocumentStore,
    ) error{ Canceled, OutOfMemory }!union(enum) {
        unknown,
        no,
        /// Stores the `root_source_file`. Caller owns returned memory.
        yes: []const u8,
    } {
        _ = build_file;
        _ = uri;
        _ = store;
        return .unknown;
    }

    fn deinit(self: *BuildFile, allocator: std.mem.Allocator) void {
        self.uri.deinit(allocator);
        if (self.builtin_uri) |builtin_uri| builtin_uri.deinit(allocator);
        if (self.build_associated_config) |cfg| cfg.deinit();
    }
};

/// Represents a Zig source file.
pub const Handle = struct {
    uri: Uri,
    tree: Ast,
    /// List of every file that has been `@Import`ed. Does not include imported modules.
    file_imports: []const Uri,
    /// `true` if the document has been directly opened by the client i.e. with `textDocument/didOpen`
    /// `false` indicates the document only exists because it is a dependency of another document
    /// or has been closed with `textDocument/didClose`.
    lsp_synced: bool,
    document_scope: Lazy(DocumentScope, DocumentStoreContext) = .unset,
    trigram_store: Lazy(TrigramStore, TrigramStoreContext) = .unset,

    /// private field
    impl: struct {
        store: *DocumentStore,
        lock: std.Io.Mutex = .init,
        has_tree_and_source: bool,

        associated_build_file: AssociatedBuildFile.State = .init,
        associated_compilation_units: GetAssociatedCompilationUnitsResult = .unresolved,
    },

    pub fn getDocumentScope(self: *Handle) error{OutOfMemory}!*const DocumentScope {
        return try self.document_scope.get(self);
    }

    pub const AssociatedBuildFile = union(enum) {
        /// The Handle has no associated build file (build.zig).
        none,
        /// The associated build file (build.zig) has not been resolved yet.
        unresolved,
        /// The associated build file (build.zig) has been successfully resolved.
        resolved: Resolved,

        pub const Resolved = struct {
            build_file: *BuildFile,
            root_source_file: []const u8,
        };

        const State = union(enum) {
            /// The initial state. The associated build file (build.zig) is resolved lazily.
            init,
            /// The associated build file (build.zig) has been requested but has not yet been resolved.
            unresolved: struct {
                /// The build files are ordered in decreasing priority.
                potential_build_files: []const *BuildFile,
                /// to avoid checking build files multiple times, a bitset stores whether or
                /// not the build file should be skipped because it has previously been
                /// found to be "unassociated" with the handle.
                has_been_checked: std.bit_set.Dynamic,
            },
            /// The Handle has no associated build file (build.zig).
            none,
            /// The associated build file (build.zig) has been successfully resolved.
            resolved: Resolved,

            fn deinit(state: *State, allocator: std.mem.Allocator) void {
                switch (state.*) {
                    .init, .none => {},
                    .unresolved => |*unresolved| {
                        allocator.free(unresolved.potential_build_files);
                        unresolved.has_been_checked.deinit(allocator);
                    },
                    .resolved => |resolved| {
                        allocator.free(resolved.root_source_file);
                    },
                }
                state.* = undefined;
            }
        };
    };

    /// Returns the associated build file (build.zig) of the handle.
    ///
    /// `DocumentStore.build_files` is guaranteed to contain this Uri.
    /// Uri memory managed by its build_file
    pub fn getAssociatedBuildFile(self: *Handle, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!AssociatedBuildFile {
        try self.impl.lock.lock(document_store.io);
        defer self.impl.lock.unlock(document_store.io);

        const unresolved = switch (self.impl.associated_build_file) {
            .init => blk: {
                const potential_build_files = try document_store.collectPotentialBuildFiles(self.uri);
                errdefer document_store.allocator.free(potential_build_files);

                if (potential_build_files.len == 0) {
                    self.impl.associated_build_file = .none;
                    return .none;
                }

                var has_been_checked: std.bit_set.Dynamic = try .initEmpty(document_store.allocator, potential_build_files.len);
                errdefer has_been_checked.deinit(document_store.allocator);

                self.impl.associated_build_file = .{ .unresolved = .{
                    .has_been_checked = has_been_checked,
                    .potential_build_files = potential_build_files,
                } };

                break :blk &self.impl.associated_build_file.unresolved;
            },
            .unresolved => |*unresolved| unresolved,
            .none => return .none,
            .resolved => |resolved| return .{ .resolved = resolved },
        };

        var has_missing_build_config = false;

        var it = unresolved.has_been_checked.iterator(.{
            .kind = .unset,
            .direction = .reverse,
        });
        while (it.next()) |i| {
            const build_file = unresolved.potential_build_files[i];
            switch (try build_file.isAssociatedWith(self.uri, document_store)) {
                .unknown => {
                    has_missing_build_config = true;
                    continue;
                },
                .no => {
                    // the build file should be skipped in future calls.
                    unresolved.has_been_checked.set(i);
                    continue;
                },
                .yes => |root_source_file| {
                    // log.debug("Resolved build file of '{s}' as '{s}' root={s}", .{ self.uri.raw, build_file.uri.raw, root_source_file });
                    errdefer comptime unreachable;
                    self.impl.associated_build_file.deinit(document_store.allocator);
                    self.impl.associated_build_file = .{
                        .resolved = .{
                            .build_file = build_file,
                            .root_source_file = root_source_file,
                        },
                    };
                    return .{ .resolved = self.impl.associated_build_file.resolved };
                },
            }
        }

        if (has_missing_build_config) {
            // when build configs are missing we keep the state at .unresolved so that
            // future calls will retry until all build config are resolved.
            // Then will have a conclusive result on whether or not there is a associated build file.
            return .unresolved;
        }

        self.impl.associated_build_file.deinit(document_store.allocator);
        self.impl.associated_build_file = .none;
        return .none;
    }

    pub const GetAssociatedCompilationUnitsResult = union(enum) {
        /// The Handle has no associated compilation unit.
        none,
        /// The associated compilation unit has not been resolved yet.
        unresolved,
        /// The associated compilation unit has been successfully resolved to a list of root module.
        resolved: []const []const u8,

        fn deinit(result: *GetAssociatedCompilationUnitsResult, allocator: std.mem.Allocator) void {
            switch (result.*) {
                .none, .unresolved => {},
                .resolved => |root_source_files| {
                    allocator.free(root_source_files);
                },
            }
            result.* = undefined;
        }
    };

    /// Returns the root source file of the root module of the given handle. Same as `@import("root")`.
    /// Always resolves to `.none` or `.unresolved`: without a build runner there is
    /// no compilation graph to search (see `supports_build_system`).
    pub fn getAssociatedCompilationUnits(self: *Handle, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!GetAssociatedCompilationUnitsResult {
        switch (self.impl.associated_compilation_units) {
            .unresolved => {},
            else => return self.impl.associated_compilation_units,
        }
        switch (try self.getAssociatedBuildFile(document_store)) {
            // Without a module graph every build file association stays inconclusive,
            // report `.unresolved` so callers fall back to file-based resolution.
            .unresolved => return .unresolved,
            .none => {
                self.impl.associated_compilation_units = .none;
                return .none;
            },
            // `getAssociatedBuildFile` never resolves while `supports_build_system`
            // is disabled, but keep the arm so this keeps compiling if a new
            // configuration protocol lands.
            .resolved => return .unresolved,
        }
    }

    fn refresh(
        handle: *Handle,
        /// Old state will be moved into this handle to be deallocated after returning.
        old_handle: *Handle,
        /// Takes ownership.
        text: [:0]const u8,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        const tracy_zone = tracy.traceNamed(@src(), "Handle.refresh");
        defer tracy_zone.end();

        const mode: Ast.Mode = if (std.mem.eql(u8, std.Io.Dir.path.extension(handle.uri.raw), ".zon")) .zon else .zig;
        var new_tree = try parseTree(allocator, text, mode);
        errdefer new_tree.deinit(allocator);

        var new_file_imports: std.ArrayList(Uri) = .empty;
        errdefer new_file_imports.deinit(allocator);

        try collectImports(
            allocator,
            handle.uri,
            &new_tree,
            &new_file_imports,
        );

        const file_imports = try new_file_imports.toOwnedSlice(allocator);
        errdefer file_imports.deinit(allocator);

        errdefer comptime unreachable;

        if (handle.impl.has_tree_and_source) {
            old_handle.tree = handle.tree;
            old_handle.impl.has_tree_and_source = true;
        }

        handle.tree = new_tree;
        old_handle.file_imports = handle.file_imports;
        handle.file_imports = file_imports;
        handle.impl.has_tree_and_source = true;

        old_handle.document_scope = handle.document_scope;
        handle.document_scope = .unset;
        old_handle.trigram_store = handle.trigram_store;
        handle.trigram_store = .unset;
    }

    fn parseTree(allocator: std.mem.Allocator, new_text: [:0]const u8, mode: Ast.Mode) error{OutOfMemory}!Ast {
        const tracy_zone = tracy.traceNamed(@src(), "Ast.parse");
        defer tracy_zone.end();

        var tree = try Ast.parse(allocator, new_text, .{
            .mode = mode,
        });
        errdefer tree.deinit(allocator);

        // remove unused capacity
        var nodes = tree.nodes.toMultiArrayList();
        try nodes.setCapacity(allocator, nodes.len);
        tree.nodes = nodes.slice();

        // remove unused capacity
        var tokens = tree.tokens.toMultiArrayList();
        try tokens.setCapacity(allocator, tokens.len);
        tree.tokens = tokens.slice();
        return tree;
    }

    fn collectImports(
        allocator: std.mem.Allocator,
        uri: Uri,
        tree: *const Ast,
        file_imports: *std.ArrayList(Uri),
    ) error{OutOfMemory}!void {
        const tracy_zone = tracy.trace(@src());
        defer tracy_zone.end();

        const parsed_uri = uri.toStdUri();

        const node_tags = tree.nodes.items(.tag);
        for (node_tags, 0..) |tag, i| {
            const node: Ast.Node.Index = @fromBackingInt(@intCast(i));

            switch (tag) {
                .builtin_call,
                .builtin_call_comma,
                .builtin_call_two,
                .builtin_call_two_comma,
                => {},
                else => continue,
            }
            const name = offsets.tokenToSlice(tree, tree.nodeMainToken(node));

            if (std.mem.eql(u8, name, "@import")) {
                try file_imports.ensureUnusedCapacity(allocator, 1);

                var buffer: [2]Ast.Node.Index = undefined;
                const params = tree.builtinCallParams(&buffer, node).?;
                if (params.len < 1) continue;
                if (tree.nodeTag(params[0]) != .string_literal) continue;

                var import_string = offsets.tokenToSlice(tree, tree.nodeMainToken(params[0]));
                import_string = import_string[1 .. import_string.len - 1];

                if (!std.mem.endsWith(u8, import_string, ".zig")) continue;

                const import_uri = try Uri.resolveImport(allocator, uri, parsed_uri, import_string);
                file_imports.appendAssumeCapacity(import_uri);
                continue;
            }
        }
    }

    /// A handle that can only be deallocated. Keep in sync with `deinit`.
    const dead: Handle = .{
        .uri = undefined,
        .tree = undefined,
        .file_imports = &.{},
        .lsp_synced = undefined,
        .impl = .{
            .store = undefined,
            .has_tree_and_source = false,
        },
    };

    /// Caller must free `Handle.uri` if needed.
    /// Keep in sync with `dead`.
    fn deinit(self: *Handle, allocator: std.mem.Allocator) void {
        const tracy_zone = tracy.trace(@src());
        defer tracy_zone.end();

        if (self.impl.has_tree_and_source) {
            allocator.free(self.tree.source);
            self.tree.deinit(allocator);
        }
        self.document_scope.deinit(allocator);
        self.trigram_store.deinit(allocator);
        for (self.file_imports) |uri| uri.deinit(allocator);
        allocator.free(self.file_imports);

        self.impl.associated_build_file.deinit(allocator);
        self.impl.associated_compilation_units.deinit(allocator);

        self.* = undefined;
    }

    const Future = struct {
        event: std.Io.Event,
        handle: Handle,
        err: ?ReadFileError,

        pub fn await(f: *Future, io: std.Io) ReadFileError!*Handle {
            try f.event.wait(io);
            return f.err orelse return &f.handle;
        }
    };

    fn Lazy(comptime T: type, comptime Context: type) type {
        return struct {
            mutex: std.Io.Mutex,
            value: ?T,

            const LazyResource = @This();

            pub const unset: LazyResource = .{
                .mutex = .init,
                .value = null,
            };

            pub fn deinit(lazy: *LazyResource, allocator: std.mem.Allocator) void {
                const value: *T = if (lazy.value) |*value| value else return;
                Context.deinit(value, allocator);
                lazy.value = undefined;
            }

            pub fn get(lazy: *LazyResource, handle: *Handle) error{OutOfMemory}!*const T {
                const tracy_zone = tracy.traceNamed(@src(), "Lazy(" ++ @typeName(T) ++ ").get");
                defer tracy_zone.end();

                const store = handle.impl.store;
                const io = store.io;

                lazy.mutex.lockUncancelable(io);
                defer lazy.mutex.unlock(io);
                if (lazy.value == null) {
                    lazy.value = try Context.create(handle, store.allocator);
                }
                return &lazy.value.?;
            }

            pub fn getOrNull(lazy: *LazyResource, handle: *Handle) ?*const T {
                const tracy_zone = tracy.traceNamed(@src(), "Lazy(" ++ @typeName(T) ++ ").getOrNull");
                defer tracy_zone.end();

                const store = handle.impl.store;
                const io = store.io;
                handle.impl.lock.lockUncancelable(io);
                defer handle.impl.lock.unlock(io);
                return if (lazy.value) |*value| value else null;
            }

            pub fn getCached(lazy: *LazyResource) *const T {
                return &lazy.value.?;
            }
        };
    }

    const DocumentStoreContext = struct {
        fn create(handle: *Handle, allocator: std.mem.Allocator) error{OutOfMemory}!DocumentScope {
            var document_scope: DocumentScope = try .init(allocator, &handle.tree);
            errdefer document_scope.deinit(allocator);

            // remove unused capacity
            document_scope.extra.shrinkAndFree(allocator, document_scope.extra.items.len);
            try document_scope.declarations.setCapacity(allocator, document_scope.declarations.len);
            try document_scope.scopes.setCapacity(allocator, document_scope.scopes.len);

            return document_scope;
        }
        fn deinit(document_scope: *DocumentScope, allocator: std.mem.Allocator) void {
            document_scope.deinit(allocator);
        }
    };

    const TrigramStoreContext = struct {
        fn create(handle: *Handle, allocator: std.mem.Allocator) error{OutOfMemory}!TrigramStore {
            return try .init(allocator, &handle.tree);
        }
        fn deinit(trigram_store: *TrigramStore, allocator: std.mem.Allocator) void {
            trigram_store.deinit(allocator);
        }
    };
};

pub const HandleIterator = struct {
    store: *DocumentStore,
    i: usize = 0,

    pub fn next(it: *HandleIterator) ?*Handle {
        it.store.mutex.lockUncancelable(it.store.io);
        defer it.store.mutex.unlock(it.store.io);
        while (true) {
            defer it.i += 1;
            switch (std.math.order(it.i, it.store.handles.count())) {
                .lt => {},
                .eq => return null,
                .gt => unreachable, // handle count decreased
            }
            return it.store.handles.values()[it.i].await(it.store.io) catch continue;
        }
    }
};

pub const ErrorMessage = struct {
    loc: offsets.Loc,
    code: []const u8,
    message: []const u8,
};

pub fn deinit(self: *DocumentStore) void {
    if (supports_build_system) {
        self.wait_group.cancel(self.io);
    }

    for (self.handles.keys(), self.handles.values()) |uri, future| {
        if (future.await(self.io)) |handle| handle.deinit(self.allocator) else |_| {}
        uri.deinit(self.allocator);
        self.allocator.destroy(future);
    }
    self.handles.deinit(self.allocator);

    for (self.build_files.values()) |build_file| {
        build_file.deinit(self.allocator);
        self.allocator.destroy(build_file);
    }
    self.build_files.deinit(self.allocator);

    self.* = undefined;
}

/// Returns a handle to the given document
/// **Thread safe** takes a shared lock
/// This function does not protect against data races from modifying the Handle
pub fn getHandle(self: *DocumentStore, uri: Uri) ?*Handle {
    const future = future: {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        break :future self.handles.get(uri) orelse return null;
    };
    return future.await(self.io) catch return null;
}

const ReadFileError = std.mem.Allocator.Error || std.Io.Cancelable || std.Io.File.OpenError || std.Io.File.Reader.Error || error{StreamTooLong};

/// Must satisfy `uri.isFileScheme()`.
fn readFile(self: *DocumentStore, uri: Uri) ReadFileError![:0]u8 {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const file_path = uri.toFsPath(self.allocator) catch |err| switch (err) {
        error.UnsupportedScheme => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer self.allocator.free(file_path);

    const dir, const sub_path = blk: {
        if (builtin.target.cpu.arch.isWasm() and !builtin.link_libc) {
            for (self.config.wasi_preopens.map.keys()[3..], 3..) |name, i| {
                const preopen_dir: std.Io.Dir = .{ .handle = @intCast(i) };
                const preopen_path = std.mem.trimEnd(u8, name, "/");

                if (!std.mem.startsWith(u8, file_path, preopen_path)) continue;
                if (!std.mem.startsWith(u8, file_path[preopen_path.len..], "/")) continue;

                break :blk .{ preopen_dir, std.mem.trimStart(u8, file_path[preopen_path.len..], "/") };
            }
        }
        break :blk .{ std.Io.Dir.cwd(), file_path };
    };

    return try dir.readFileAllocOptions(
        self.io,
        sub_path,
        self.allocator,
        .limited(std.zig.max_src_size),
        .of(u8),
        0,
    );
}

/// Returns a handle to the given document
/// Will load the document from disk if it hasn't been already
/// **Thread safe** takes an exclusive lock
/// This function does not protect against data races from modifying the Handle
pub fn getOrLoadHandle(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!?*Handle {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (!uri.isFileScheme()) return self.getHandle(uri);
    return self.createAndStoreDocument(
        uri,
        .uri,
        .{
            .lsp_synced = false,
            .override = false,
            .load_build_file_behaviour = .never,
        },
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => return null,
    };
}

/// **Thread safe** takes a shared lock
/// This function does not protect against data races from modifying the BuildFile
pub fn getBuildFile(self: *DocumentStore, uri: Uri) ?*BuildFile {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.build_files.get(uri);
}

/// invalidates any pointers into `DocumentStore.build_files`
/// **Thread safe** takes an exclusive lock
/// This function does not protect against data races from modifying the BuildFile
fn getOrLoadBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!*BuildFile {
    if (self.getBuildFile(uri)) |build_file| return build_file;

    const new_build_file: *BuildFile = blk: {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const gop = try self.build_files.getOrPut(self.allocator, uri);
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer self.build_files.swapRemoveAt(gop.index);

        gop.value_ptr.* = try self.allocator.create(BuildFile);
        errdefer self.allocator.destroy(gop.value_ptr.*);

        gop.value_ptr.*.* = try self.createBuildFile(uri);
        gop.key_ptr.* = gop.value_ptr.*.uri;
        break :blk gop.value_ptr.*;
    };

    // this code path is only reached when the build file is new

    self.invalidateBuildFile(new_build_file.uri);

    return new_build_file;
}

/// Opens a document that is synced over the LSP protocol (`textDocument/didOpen`).
/// **Not thread safe**
pub fn openLspSyncedDocument(self: *DocumentStore, uri: Uri, text: []const u8) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.getHandle(uri)) |handle| {
        if (handle.lsp_synced) {
            log.warn("Document already open: {s}", .{uri.raw});
        }
    }

    const duped_text = try self.allocator.dupeSentinel(u8, text, 0);
    _ = self.createAndStoreDocument(
        uri,
        .{ .text = duped_text },
        .{
            .lsp_synced = true,
            .override = true,
            .load_build_file_behaviour = .load_but_dont_update,
        },
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => unreachable,
    };
}

/// Closes a document that has been synced over the LSP protocol (`textDocument/didClose`).
/// **Not thread safe**
pub fn closeLspSyncedDocument(self: *DocumentStore, uri: Uri) void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const handle_index = self.handles.getIndex(uri) orelse {
        log.warn("Document not found: {s}", .{uri.raw});
        return;
    };
    defer self.handles.swapRemoveAt(handle_index);

    const handle_uri = self.handles.keys()[handle_index];
    defer handle_uri.deinit(self.allocator);

    const handle_future = self.handles.values()[handle_index];
    defer self.allocator.destroy(handle_future);

    if (handle_future.await(self.io)) |handle| {
        if (!handle.lsp_synced) {
            log.warn("Document already closed: {s}", .{uri.raw});
        }
        handle.deinit(self.allocator);
    } else |_| {}
}

/// Updates a document that is synced over the LSP protocol (`textDocument/didChange`).
/// Takes ownership of `new_text` which has to be allocated with this DocumentStore's allocator.
/// **Not thread safe**
pub fn refreshLspSyncedDocument(self: *DocumentStore, uri: Uri, new_text: [:0]const u8) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.getHandle(uri)) |old_handle| {
        if (!old_handle.lsp_synced) {
            log.warn("Document modified without being opened: {s}", .{uri.raw});
        }
    } else {
        log.warn("Document modified without being opened: {s}", .{uri.raw});
    }

    _ = self.createAndStoreDocument(
        uri,
        .{ .text = new_text },
        .{
            .lsp_synced = true,
            .override = true,
            .load_build_file_behaviour = .only_update,
        },
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => unreachable,
    };
}

/// Refreshes a document from the file system, unless said document is synced over the LSP protocol.
/// **Not thread safe**
pub fn refreshDocumentFromFileSystem(self: *DocumentStore, uri: Uri, should_delete: bool) error{ Canceled, OutOfMemory }!bool {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (should_delete) {
        const index = self.handles.getIndex(uri) orelse return false;
        const handle_future = self.handles.values()[index];
        const handle = handle_future.await(self.io) catch return false;
        if (handle.lsp_synced) return false;
        self.handles.swapRemoveAt(index);
        handle.uri.deinit(self.allocator);
        handle.deinit(self.allocator);
        self.allocator.destroy(handle_future);
    } else {
        if (self.getHandle(uri)) |handle| {
            if (handle.lsp_synced) return false;
        } else return false;
        if (uri.isFileScheme()) return false;
        _ = self.createAndStoreDocument(
            uri,
            .uri,
            .{
                .lsp_synced = false,
                .override = true,
                .load_build_file_behaviour = .only_update,
            },
        ) catch |err| switch (err) {
            error.Canceled, error.OutOfMemory => |e| return e,
            else => return false,
        };
    }

    return true;
}

/// Invalidates a build file.
/// Currently a no-op: there is no build runner to re-run while
/// `supports_build_system` is disabled. Kept so callers in `Server` keep
/// working unchanged when a new configuration protocol lands.
/// **Thread safe** takes a shared lock
pub fn invalidateBuildFile(self: *DocumentStore, build_file_uri: Uri) void {
    _ = self;
    _ = build_file_uri;
}

const LoadDirectoryError = error{UnsupportedScheme} || std.mem.Allocator.Error || std.Io.Dir.OpenError;

pub fn loadDirectoryRecursive(store: *DocumentStore, directory_uri: Uri) LoadDirectoryError!usize {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const workspace_path = try directory_uri.toFsPath(store.allocator);
    defer store.allocator.free(workspace_path);

    var workspace_dir = try std.Io.Dir.cwd().openDir(store.io, workspace_path, .{ .iterate = true });
    defer workspace_dir.close(store.io);

    var walker = try workspace_dir.walk(store.allocator);
    defer walker.deinit();

    const getOrLoadHandleVoid = struct {
        fn getOrLoadHandleVoid(
            s: *DocumentStore,
            uri: Uri,
            did_out_of_memory: *std.atomic.Value(bool),
        ) std.Io.Cancelable!void {
            _ = s.getOrLoadHandle(uri) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.OutOfMemory => did_out_of_memory.store(true, .release),
            };
            uri.deinit(s.allocator);
        }
    }.getOrLoadHandleVoid;

    var group: std.Io.Group = .init;
    var did_out_of_memory: std.atomic.Value(bool) = .init(false);

    var file_count: usize = 0;
    while (try walker.next(store.io)) |entry| {
        if (entry.kind == .directory) {
            // Keep in sync with `loadTrigramStores`
            if (std.mem.startsWith(u8, entry.basename, ".") or
                std.mem.eql(u8, entry.basename, "zig-cache") or
                std.mem.eql(u8, entry.basename, "zig-pkg"))
            {
                walker.leave(store.io);
            }
            continue;
        }
        if (!std.mem.eql(u8, std.Io.Dir.path.extension(entry.basename), ".zig")) continue;

        file_count += 1;

        const path = try std.Io.Dir.path.join(store.allocator, &.{ workspace_path, entry.path });
        defer store.allocator.free(path);

        const uri: Uri = try .fromPath(store.allocator, path);
        errdefer comptime unreachable;

        group.async(store.io, getOrLoadHandleVoid, .{ store, uri, &did_out_of_memory });
    }
    try group.await(store.io);

    if (did_out_of_memory.load(.acquire)) return error.OutOfMemory;

    return file_count;
}

pub fn loadTrigramStores(
    store: *DocumentStore,
    filter_uris: []const std.Uri,
) error{ OutOfMemory, Canceled }![]*DocumentStore.Handle {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var handles: std.ArrayList(*DocumentStore.Handle) = .empty;
    errdefer handles.deinit(store.allocator);

    var it: HandleIterator = .{ .store = store };
    while (it.next()) |handle| {
        const uri = handle.uri.toStdUri();

        var component_it = std.Io.Dir.path.componentIterator(uri.path.percent_encoded);
        const skip = while (component_it.next()) |component| {
            // Keep in sync with `loadDirectoryRecursive`
            if (std.mem.startsWith(u8, component.name, ".")) break true;
            if (std.mem.eql(u8, component.name, "zig-cache")) break true;
            if (std.mem.eql(u8, component.name, "zig-pkg")) break true;
        } else false;
        if (skip) continue;

        for (filter_uris) |filter_uri| {
            if (!std.ascii.eqlIgnoreCase(uri.scheme, filter_uri.scheme)) continue;
            if (std.mem.startsWith(u8, uri.path.percent_encoded, filter_uri.path.percent_encoded)) break;
        } else continue;
        try handles.append(store.allocator, handle);
    }

    const loadTrigramStore = struct {
        fn loadTrigramStore(
            handle: *DocumentStore.Handle,
            did_out_of_memory: *std.atomic.Value(bool),
        ) void {
            _ = handle.trigram_store.get(handle) catch |err| switch (err) {
                error.OutOfMemory => {
                    did_out_of_memory.store(true, .release);
                    return;
                },
            };
        }
    }.loadTrigramStore;

    var group: std.Io.Group = .init;
    var did_out_of_memory: std.atomic.Value(bool) = .init(false);

    for (handles.items) |handle| {
        const has_trigram_store = handle.trigram_store.getOrNull(handle) != null;
        if (has_trigram_store) continue;
        group.async(store.io, loadTrigramStore, .{ handle, &did_out_of_memory });
    }
    try group.await(store.io);

    if (did_out_of_memory.load(.acquire)) return error.OutOfMemory;

    return try handles.toOwnedSlice(store.allocator);
}

pub fn isBuildFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri.raw, "/build.zig");
}

pub fn isBuiltinFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri.raw, "/builtin.zig");
}

pub fn isInStd(uri: Uri) bool {
    // TODO: Better logic for detecting std or subdirectories?
    return std.mem.find(u8, uri.raw, "/std/") != null;
}

/// looks for a `zig-analyzer.build.json` file in the build file directory
/// has to be freed with `json_compat.parseFree`
fn loadBuildAssociatedConfiguration(io: std.Io, allocator: std.mem.Allocator, build_file: BuildFile) !std.json.Parsed(BuildAssociatedConfig) {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const build_file_path = try build_file.uri.toFsPath(allocator);
    defer allocator.free(build_file_path);
    const config_file_path = try std.Io.Dir.path.resolve(allocator, &.{ build_file_path, "..", "zig-analyzer.build.json" });
    defer allocator.free(config_file_path);

    const file_buf = try std.Io.Dir.cwd().readFileAlloc(
        io,
        config_file_path,
        allocator,
        .limited(16 * 1024 * 1024),
    );
    defer allocator.free(file_buf);

    return try std.json.parseFromSlice(
        BuildAssociatedConfig,
        allocator,
        file_buf,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
}

/// Checks if the build.zig file is accessible in dir.
fn buildDotZigExists(io: std.Io, dir_path: []const u8) std.Io.Cancelable!bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{}) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return false,
    };
    defer dir.close(io);
    dir.access(io, "build.zig", .{}) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return false,
    };
    return true;
}

/// Walk down the tree towards the uri. When we hit `build.zig` files
/// add them to the list of potential build files.
/// `build.zig` files higher in the filesystem have precedence.
/// See `Handle.getAssociatedBuildFile`.
/// Caller owns returned memory.
fn collectPotentialBuildFiles(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }![]*BuildFile {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (isInStd(uri)) return &.{};

    var potential_build_files: std.ArrayList(*BuildFile) = .empty;
    errdefer potential_build_files.deinit(self.allocator);

    const path = uri.toFsPath(self.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedScheme => return &.{},
    };
    defer self.allocator.free(path);

    var it = std.Io.Dir.path.componentIterator(path);
    _ = it.last();
    var did_check_root = false;
    while (true) {
        const dir_path = if (it.previous()) |comp| comp.path else blk: {
            if (did_check_root) break :blk null;
            did_check_root = true;
            break :blk it.root();
        } orelse break;
        if (!try buildDotZigExists(self.io, dir_path)) continue;

        const build_path = try std.Io.Dir.path.join(self.allocator, &.{ dir_path, "build.zig" });
        defer self.allocator.free(build_path);

        try potential_build_files.ensureUnusedCapacity(self.allocator, 1);

        const build_file_uri: Uri = try .fromPath(self.allocator, build_path);
        defer build_file_uri.deinit(self.allocator);

        const build_file = try self.getOrLoadBuildFile(build_file_uri);
        potential_build_files.appendAssumeCapacity(build_file);
    }
    // The potential build files that come first should have higher priority.
    //
    // `build.zig` files that are higher up in the filesystem are more likely
    // to be the `build.zig` of the entire project/package instead of just a
    // sub-project/package.
    std.mem.reverse(*BuildFile, potential_build_files.items);

    return try potential_build_files.toOwnedSlice(self.allocator);
}

fn createBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!BuildFile {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var build_file: BuildFile = .{
        .uri = try uri.dupe(self.allocator),
    };

    errdefer build_file.deinit(self.allocator);

    if (loadBuildAssociatedConfiguration(self.io, self.allocator, build_file)) |cfg| {
        build_file.build_associated_config = cfg;

        if (cfg.value.relative_builtin_path) |relative_builtin_path| blk: {
            const build_file_path = build_file.uri.toFsPath(self.allocator) catch break :blk;
            const absolute_builtin_path = try std.Io.Dir.path.resolve(self.allocator, &.{ build_file_path, "..", relative_builtin_path });
            defer self.allocator.free(absolute_builtin_path);
            build_file.builtin_uri = try .fromPath(self.allocator, absolute_builtin_path);
        }
    } else |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.FileNotFound => {},
        else => {
            log.debug("Failed to load config associated with build file {s} (error: {})", .{ build_file.uri.raw, err });
        },
    }

    log.info("Loaded build file '{s}'", .{build_file.uri.raw});

    return build_file;
}

const FileSource = union(enum) {
    text: [:0]const u8,
    /// Must satisfy `uri.isFileScheme()`.
    uri,
};

const CreateAndStoreOptions = struct {
    lsp_synced: bool,
    override: bool,
    load_build_file_behaviour: enum { load_but_dont_update, only_update, never },
};

/// **Thread safe** takes an exclusive lock
fn createAndStoreDocument(
    store: *DocumentStore,
    uri: Uri,
    /// Takes ownership.
    /// `file_source == .text` implies `options.lsp_synced == true`.
    file_source: FileSource,
    options: CreateAndStoreOptions,
) ReadFileError!*Handle {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    std.debug.assert(!(options.lsp_synced and !options.override));
    std.debug.assert(!(options.lsp_synced and file_source == .uri));

    switch (file_source) {
        .text => {},
        .uri => std.debug.assert(uri.isFileScheme()),
    }
    errdefer switch (file_source) {
        .text => |text| store.allocator.free(text),
        .uri => {},
    };

    // Register opened `build.zig` files so their `zig-analyzer.build.json`
    // (builtin path override, build options) is honored. Nothing executes
    // the build file: `invalidateBuildFile` is a no-op while there is no
    // build runner (see `supports_build_system`).
    if (options.lsp_synced and isBuildFile(uri) and !isInStd(uri)) {
        switch (options.load_build_file_behaviour) {
            .load_but_dont_update => {
                _ = try store.getOrLoadBuildFile(uri);
            },
            .only_update => {
                store.invalidateBuildFile(uri);
            },
            .never => {},
        }
    }

    const handle_future: *Handle.Future = handle_future: {
        try store.mutex.lock(store.io);
        defer store.mutex.unlock(store.io);

        const gop = try store.handles.getOrPut(store.allocator, uri);

        var previous_err: ?ReadFileError = null;
        if (gop.found_existing) {
            if (gop.value_ptr.*.await(store.io)) |old_handle| {
                if (!options.override) return old_handle;
                gop.value_ptr.*.event.reset();
                old_handle.lsp_synced = options.lsp_synced;
                break :handle_future gop.value_ptr.*;
            } else |err| {
                const retry = switch (err) {
                    error.Canceled => true,
                    else => file_source == .text,
                };
                if (options.override and !retry) return err;
                previous_err = err;
            }
        } else {
            errdefer store.handles.swapRemoveAt(gop.index);

            gop.key_ptr.* = try uri.dupe(store.allocator);
            errdefer gop.key_ptr.*.deinit(store.allocator);

            gop.value_ptr.* = try store.allocator.create(Handle.Future);
            errdefer store.allocator.destroy(gop.value_ptr.*);
        }
        gop.value_ptr.*.* = .{
            .event = .unset,
            .handle = .{
                .uri = gop.key_ptr.*,
                .tree = undefined,
                .file_imports = &.{},
                .lsp_synced = options.lsp_synced,
                .impl = .{
                    .store = store,
                    .has_tree_and_source = false,
                },
            },
            .err = previous_err,
        };
        break :handle_future gop.value_ptr.*;
    };
    defer handle_future.event.set(store.io);

    const text: [:0]const u8 = switch (file_source) {
        .text => |text| text,
        .uri => store.readFile(uri) catch |err| {
            const should_log = err != error.Canceled and err != error.FileNotFound;
            if (should_log) log.err("failed to read document '{s}': {}", .{ uri.raw, err });
            handle_future.handle = undefined;
            handle_future.err = err;
            return err;
        },
    };

    var old_handle: Handle = .dead;
    Handle.refresh(
        &handle_future.handle,
        &old_handle,
        text,
        store.allocator,
    ) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("failed to read document '{s}': {}", .{ uri.raw, err });
            handle_future.handle = undefined;
            handle_future.err = err;
            return err;
        },
    };
    old_handle.deinit(store.allocator);

    handle_future.err = null;
    return &handle_future.handle;
}

pub const UriFromImportStringResult = union(enum) {
    none,
    one: Uri,
    many: []const Uri,

    pub fn deinit(result: *UriFromImportStringResult, allocator: std.mem.Allocator) void {
        switch (result.*) {
            .none => {},
            .one => |uri| uri.deinit(allocator),
            .many => |uris| {
                for (uris) |uri| uri.deinit(allocator);
                allocator.free(uris);
            },
        }
    }
};

/// takes the string inside a @import() node (without the quotation marks)
/// and returns it's uri
/// caller owns the returned memory
/// **Thread safe** takes a shared lock
pub fn uriFromImportStr(
    self: *DocumentStore,
    allocator: std.mem.Allocator,
    handle: *Handle,
    import_str: []const u8,
) error{ Canceled, OutOfMemory }!UriFromImportStringResult {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (std.mem.endsWith(u8, import_str, ".zig") or std.mem.endsWith(u8, import_str, ".zon")) {
        const parsed_uri = handle.uri.toStdUri();
        return .{ .one = try Uri.resolveImport(allocator, handle.uri, parsed_uri, import_str) };
    }

    if (std.mem.eql(u8, import_str, "std")) {
        const zig_lib_dir = self.config.zig_lib_dir orelse return .none;

        const std_path = try zig_lib_dir.join(allocator, &.{ "std", "std.zig" });
        defer allocator.free(std_path);

        return .{ .one = try .fromPath(allocator, std_path) };
    }

    if (std.mem.eql(u8, import_str, "builtin")) {
        // A `build.zig` may point at its own generated `builtin.zig` through
        // `zig-analyzer.build.json` (`relative_builtin_path`). Honor that
        // before falling back to the globally configured path.
        switch (try handle.getAssociatedBuildFile(self)) {
            .none, .unresolved => {},
            .resolved => |resolved| {
                if (resolved.build_file.builtin_uri) |builtin_uri| {
                    return .{ .one = try builtin_uri.dupe(allocator) };
                }
            },
        }
        if (self.config.builtin_path) |builtin_path| {
            return .{ .one = try .fromPath(allocator, builtin_path) };
        }
        return .none;
    }

    if (!supports_build_system) {
        // Named `@import`s (`@import("my_module")`, `@import("root")`, dependency
        // names inside `build.zig`) need the module graph from a build runner.
        // There is none on Zig 0.17 (see `supports_build_system`), so report
        // `.none` and let callers fall back to file-based resolution.
        // A new configuration protocol must add its resolution logic here.
        return .none;
    }

    comptime unreachable;
}
