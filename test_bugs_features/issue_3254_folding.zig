//! Upstream zigtools/zls#3254: anon struct param breaks function folding.
//!
//! helix manual check:
//!   1. `hx test_bugs_features/issue_3254_folding.zig`
//!   2. `foo` and `bar` fold on the body as usual
//!   3. bug: `baz` has no body fold because the `{}` of the inline struct
//!      in the parameter list confuses the fold-range end
//!   4. fixed: `baz` folds exactly like `foo` and `bar`

fn foo(
    b: i32,
) void {
    _ = b;
}

const A = struct {
    b: i32,
};

fn bar(
    a: A,
) void {
    _ = a;
}

fn baz(a: struct {
    b: i32,
}) void {
    _ = a.b;
}
