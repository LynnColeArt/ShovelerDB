const std = @import("std");
const executor = @import("../db/executor.zig");
const handles = @import("handles.zig");

pub const RowView = opaque {};

pub fn rowCount(result: *const handles.ResultHandle) usize {
    return switch (result.result) {
        .result_set => |result_set| result_set.rows.len,
        else => 0,
    };
}

pub fn nextRow(result: *handles.ResultHandle) ?*const RowView {
    return switch (result.result) {
        .result_set => |result_set| {
            if (result.next_row_index >= result_set.rows.len) return null;
            const row = &result_set.rows[result.next_row_index];
            result.next_row_index += 1;
            return rowToView(row);
        },
        else => null,
    };
}

pub fn rowFromView(row: *const RowView) *const executor.ResultRow {
    return @ptrCast(@alignCast(row));
}

fn rowToView(row: *const executor.ResultRow) *const RowView {
    return @ptrCast(row);
}

test "ABI result row cursor yields borrowed rows and row count" {
    const allocator = std.testing.allocator;

    const values = try allocator.alloc(@import("../db/value.zig").Value, 1);
    values[0] = .{ .integer = 42 };
    const rows = try allocator.alloc(executor.ResultRow, 1);
    rows[0] = .{ .values = values };
    const columns = try allocator.alloc([]u8, 1);
    columns[0] = try allocator.dupe(u8, "answer");

    var result = handles.ResultHandle{
        .allocator = allocator,
        .result = .{ .result_set = .{
            .columns = columns,
            .rows = rows,
        } },
    };
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), rowCount(&result));
    const row = nextRow(&result) orelse return error.ExpectedRow;
    try std.testing.expectEqual(@as(i64, 42), rowFromView(row).values[0].integer);
    try std.testing.expect(nextRow(&result) == null);
}
