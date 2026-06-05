const std = @import("std");
const db_value = @import("../db/value.zig");
const handles = @import("handles.zig");
const abi_result = @import("result.zig");

pub fn kind(row: *const abi_result.RowView, column_index: usize) !handles.ValueKind {
    return kindOf(try valueAt(row, column_index));
}

pub fn int64(row: *const abi_result.RowView, column_index: usize) !i64 {
    return switch ((try valueAt(row, column_index)).*) {
        .integer => |value| value,
        else => error.TypeMismatch,
    };
}

pub fn float64(row: *const abi_result.RowView, column_index: usize) !f64 {
    return switch ((try valueAt(row, column_index)).*) {
        .float => |value| value,
        else => error.TypeMismatch,
    };
}

pub fn boolean(row: *const abi_result.RowView, column_index: usize) !u8 {
    return switch ((try valueAt(row, column_index)).*) {
        .boolean => |value| if (value) 1 else 0,
        else => error.TypeMismatch,
    };
}

pub fn text(row: *const abi_result.RowView, column_index: usize) !handles.StringView {
    return switch ((try valueAt(row, column_index)).*) {
        .text => |value| .{ .data = value.ptr, .len = value.len },
        else => error.TypeMismatch,
    };
}

pub fn blob(row: *const abi_result.RowView, column_index: usize) !handles.BytesView {
    return switch ((try valueAt(row, column_index)).*) {
        .blob => |value| .{ .data = value.ptr, .len = value.len },
        else => error.TypeMismatch,
    };
}

pub fn vectorF32(row: *const abi_result.RowView, column_index: usize) !handles.F32VectorView {
    return switch ((try valueAt(row, column_index)).*) {
        .vector => |value| .{ .data = value.values.ptr, .len = value.dimension },
        else => error.TypeMismatch,
    };
}

fn valueAt(row: *const abi_result.RowView, column_index: usize) !*const db_value.Value {
    const result_row = abi_result.rowFromView(row);
    if (column_index >= result_row.values.len) return error.InvalidArgument;
    return &result_row.values[column_index];
}

fn kindOf(value: *const db_value.Value) handles.ValueKind {
    return switch (value.*) {
        .null => .null,
        .integer => .integer,
        .float => .float,
        .boolean => .boolean,
        .text => .text,
        .blob => .blob,
        .vector => .vector_f32,
    };
}

test "ABI value access maps native values to borrowed views" {
    const allocator = std.testing.allocator;

    var text_value = try db_value.Value.initText(allocator, "memory");
    errdefer text_value.deinit(allocator);
    var blob_value = try db_value.Value.initBlob(allocator, &.{ 0x01, 0x02 });
    errdefer blob_value.deinit(allocator);
    var vector_value = try db_value.Value.initVector(allocator, .float32, 2, &.{ 0.25, 0.75 });
    errdefer vector_value.deinit(allocator);

    const values = try allocator.alloc(db_value.Value, 7);
    values[0] = .null;
    values[1] = .{ .integer = 7 };
    values[2] = .{ .float = 1.5 };
    values[3] = .{ .boolean = true };
    values[4] = text_value;
    values[5] = blob_value;
    values[6] = vector_value;

    var row = @import("../db/executor.zig").ResultRow{ .values = values };
    defer row.deinit(allocator);
    const row_view: *const abi_result.RowView = @ptrCast(&row);

    try std.testing.expectEqual(handles.ValueKind.null, try kind(row_view, 0));
    try std.testing.expectEqual(@as(i64, 7), try int64(row_view, 1));
    try std.testing.expectEqual(@as(f64, 1.5), try float64(row_view, 2));
    try std.testing.expectEqual(@as(u8, 1), try boolean(row_view, 3));
    const text_view = try text(row_view, 4);
    try std.testing.expectEqualStrings("memory", text_view.data.?[0..text_view.len]);
    const blob_view = try blob(row_view, 5);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, blob_view.data.?[0..blob_view.len]);
    const vector_view = try vectorF32(row_view, 6);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.75 }, vector_view.data.?[0..vector_view.len]);
    try std.testing.expectError(error.TypeMismatch, int64(row_view, 4));
    try std.testing.expectError(error.InvalidArgument, kind(row_view, 7));
}
