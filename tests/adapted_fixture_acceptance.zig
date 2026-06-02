const std = @import("std");
const shovelerdb = @import("shovelerdb");

const mtr_lite = shovelerdb.mariadb.mtr_lite;

test "adapted MariaDB syntax fixtures execute through MTR-lite" {
    const allocator = std.testing.allocator;

    const fixtures = [_]struct {
        name: []const u8,
        contents: []const u8,
        min_statements: usize,
        expected_errors: usize,
    }{
        .{
            .name = "query-syntax",
            .contents = @embedFile("fixtures/mariadb-adapted/query-syntax.md"),
            .min_statements = 16,
            .expected_errors = 0,
        },
        .{
            .name = "procedure-control-flow",
            .contents = @embedFile("fixtures/mariadb-adapted/procedure-control-flow.md"),
            .min_statements = 8,
            .expected_errors = 2,
        },
        .{
            .name = "grouping-aggregates",
            .contents = @embedFile("fixtures/mariadb-adapted/grouping-aggregates.md"),
            .min_statements = 11,
            .expected_errors = 1,
        },
    };

    for (fixtures) |fixture| {
        const summary = try mtr_lite.runMarkdownFixture(allocator, fixture.contents);
        try std.testing.expect(summary.statements >= fixture.min_statements);
        try std.testing.expectEqual(summary.statements, summary.executed);
        try std.testing.expectEqual(fixture.expected_errors, summary.expected_errors);
        try std.testing.expect(fixture.name.len > 0);
    }
}

test "MTR-lite reports unsupported MariaDB harness directives" {
    const fixture =
        \\# Unsupported Harness Fixture
        \\
        \\```sql
        \\connect con1,localhost,root,,;
        \\```
    ;

    try std.testing.expectError(
        error.UnsupportedDirective,
        mtr_lite.runMarkdownFixture(std.testing.allocator, fixture),
    );
    try std.testing.expectEqual(
        mtr_lite.DiagnosticKind.unsupported_directive,
        mtr_lite.diagnosticFromError(error.UnsupportedDirective).?,
    );
}
