const std = @import("std");
const diagnostics = @import("diagnostics.zig");
const handles = @import("handles.zig");
const abi_result = @import("result.zig");
const value_access = @import("value_access.zig");

pub const shovelerdb_database = handles.DatabaseHandle;
pub const shovelerdb_result = handles.ResultHandle;
pub const shovelerdb_row = abi_result.RowView;

pub const shovelerdb_status = handles.StatusCode;
pub const shovelerdb_diagnostic_code = handles.DiagnosticCode;
pub const shovelerdb_result_kind = handles.ResultKind;
pub const shovelerdb_value_kind = handles.ValueKind;
pub const shovelerdb_string_view = handles.StringView;
pub const shovelerdb_bytes_view = handles.BytesView;
pub const shovelerdb_f32_vector_view = handles.F32VectorView;

const abi_version_major: u32 = 0;
const abi_version_minor: u32 = 1;
const abi_version_patch: u32 = 0;

pub export fn shovelerdb_abi_version_major() u32 {
    return abi_version_major;
}

pub export fn shovelerdb_abi_version_minor() u32 {
    return abi_version_minor;
}

pub export fn shovelerdb_abi_version_patch() u32 {
    return abi_version_patch;
}

pub export fn shovelerdb_open_or_create(
    path: ?[*:0]const u8,
    out_database: ?*?*shovelerdb_database,
) shovelerdb_status {
    const out = out_database orelse return .invalid_argument;
    out.* = null;
    const path_ptr = path orelse return .invalid_argument;
    const path_slice = std.mem.span(path_ptr);
    if (path_slice.len == 0) return .invalid_argument;

    const handle = handles.allocator.create(shovelerdb_database) catch return .allocation_failed;

    handle.* = handles.DatabaseHandle.openOrCreate(
        handles.allocator,
        handles.defaultIo(),
        std.Io.Dir.cwd(),
        path_slice,
    ) catch |err| {
        handles.allocator.destroy(handle);
        return diagnostics.statusFromError(err);
    };

    out.* = handle;
    return .ok;
}

pub export fn shovelerdb_close(database: ?*shovelerdb_database) void {
    const handle = database orelse return;
    handle.deinit();
    handles.allocator.destroy(handle);
}

pub export fn shovelerdb_checkpoint(database: ?*shovelerdb_database) shovelerdb_status {
    const handle = database orelse return .invalid_handle;
    handle.checkpoint() catch |err| {
        const status = diagnostics.statusFromError(err);
        handle.last_status = status;
        return status;
    };
    return .ok;
}

pub export fn shovelerdb_execute(
    database: ?*shovelerdb_database,
    sql: ?[*:0]const u8,
    out_result: ?*?*shovelerdb_result,
) shovelerdb_status {
    const handle = database orelse return .invalid_handle;
    const out = out_result orelse return .invalid_argument;
    out.* = null;
    const sql_ptr = sql orelse {
        handle.last_status = .invalid_argument;
        return .invalid_argument;
    };
    const sql_slice = std.mem.span(sql_ptr);
    if (sql_slice.len == 0) {
        handle.last_status = .invalid_argument;
        return .invalid_argument;
    }

    const result_handle = handles.allocator.create(shovelerdb_result) catch {
        handle.last_status = .allocation_failed;
        return .allocation_failed;
    };

    result_handle.* = handle.execute(sql_slice) catch |err| {
        const status = diagnostics.statusFromError(err);
        handle.last_status = status;
        handles.allocator.destroy(result_handle);
        return status;
    };

    out.* = result_handle;
    return .ok;
}

pub export fn shovelerdb_result_release(result: ?*shovelerdb_result) void {
    const handle = result orelse return;
    handle.deinit();
    handles.allocator.destroy(handle);
}

pub export fn shovelerdb_result_kind_of(result: ?*const shovelerdb_result) shovelerdb_result_kind {
    const handle = result orelse return .empty;
    return handle.kind();
}

pub export fn shovelerdb_result_mutation_count(result: ?*const shovelerdb_result) u64 {
    const handle = result orelse return 0;
    return handle.mutationCount();
}

pub export fn shovelerdb_result_column_count(result: ?*const shovelerdb_result) usize {
    const handle = result orelse return 0;
    return handle.columnCount();
}

pub export fn shovelerdb_result_row_count(result: ?*const shovelerdb_result) usize {
    const handle = result orelse return 0;
    return abi_result.rowCount(handle);
}

pub export fn shovelerdb_result_column_name(
    result: ?*const shovelerdb_result,
    column_index: usize,
    out_name: ?*shovelerdb_string_view,
) shovelerdb_status {
    const out = out_name orelse return .invalid_argument;
    out.* = .{ .data = null, .len = 0 };
    const handle = result orelse return .invalid_handle;
    out.* = handle.columnName(column_index) catch return .invalid_argument;
    return .ok;
}

pub export fn shovelerdb_result_next(
    result: ?*shovelerdb_result,
    out_row: ?*?*const shovelerdb_row,
) shovelerdb_status {
    const out = out_row orelse return .invalid_argument;
    out.* = null;
    const handle = result orelse return .invalid_handle;
    out.* = abi_result.nextRow(handle);
    return .ok;
}

pub export fn shovelerdb_row_value_kind(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_kind: ?*shovelerdb_value_kind,
) shovelerdb_status {
    const out = out_kind orelse return .invalid_argument;
    out.* = .null;
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.kind(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_int64(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*i64,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = 0;
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.int64(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_float64(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*f64,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = 0;
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.float64(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_bool(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*u8,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = 0;
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.boolean(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_text(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_string_view,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = .{ .data = null, .len = 0 };
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.text(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_blob(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_bytes_view,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = .{ .data = null, .len = 0 };
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.blob(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_row_value_vector_f32(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_f32_vector_view,
) shovelerdb_status {
    const out = out_value orelse return .invalid_argument;
    out.* = .{ .data = null, .len = 0 };
    const row_handle = row orelse return .invalid_handle;
    out.* = value_access.vectorF32(row_handle, column_index) catch |err| return diagnostics.statusFromError(err);
    return .ok;
}

pub export fn shovelerdb_status_diagnostic_code(status: shovelerdb_status) shovelerdb_diagnostic_code {
    return diagnostics.diagnosticCodeFromStatus(status);
}

pub export fn shovelerdb_status_message(status: shovelerdb_status) [*:0]const u8 {
    return diagnostics.statusMessage(status);
}

pub export fn shovelerdb_database_last_diagnostic(
    database: ?*const shovelerdb_database,
    out_code: ?*shovelerdb_diagnostic_code,
    out_message: ?*shovelerdb_string_view,
) shovelerdb_status {
    const handle = database orelse return .invalid_handle;
    const code_out = out_code orelse return .invalid_argument;
    const message_out = out_message orelse return .invalid_argument;
    const message = diagnostics.statusMessage(handle.last_status);
    const message_slice = std.mem.span(message);
    code_out.* = diagnostics.diagnosticCodeFromStatus(handle.last_status);
    message_out.* = .{ .data = message_slice.ptr, .len = message_slice.len };
    return .ok;
}

test "C ABI reports versions and maps diagnostics" {
    try std.testing.expectEqual(@as(u32, 0), shovelerdb_abi_version_major());
    try std.testing.expectEqual(@as(u32, 1), shovelerdb_abi_version_minor());
    try std.testing.expectEqual(@as(u32, 0), shovelerdb_abi_version_patch());
    try std.testing.expectEqual(shovelerdb_diagnostic_code.vector, shovelerdb_status_diagnostic_code(.vector_error));
    try std.testing.expectEqualStrings("vector error", std.mem.span(shovelerdb_status_message(.vector_error)));
}

test "C ABI rejects invalid pointer arguments" {
    try std.testing.expectEqual(shovelerdb_status.invalid_argument, shovelerdb_open_or_create(null, null));
    try std.testing.expectEqual(shovelerdb_status.invalid_handle, shovelerdb_checkpoint(null));
    try std.testing.expectEqual(shovelerdb_status.invalid_handle, shovelerdb_execute(null, "SELECT 1", null));
}

test "C ABI iterates rows and reads typed values from result handles" {
    const test_allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try handles.DatabaseHandle.openOrCreate(test_allocator, io, tmp.dir, "abi-values.shovel");
    defer db.deinit();

    var setup = try db.execute("CREATE TABLE memories (id INTEGER, score FLOAT, active BOOLEAN, body TEXT, embedding VECTOR(2));");
    setup.deinit();
    setup = try db.execute("BEGIN;");
    setup.deinit();
    setup = try db.execute("INSERT INTO memories VALUES (7, 1.5, TRUE, 'memory', [0.25, 0.75]);");
    setup.deinit();
    setup = try db.execute("COMMIT;");
    setup.deinit();

    var selected = try db.execute("SELECT NULL, id, score, active, body, embedding FROM memories;");
    defer selected.deinit();

    try std.testing.expectEqual(shovelerdb_result_kind.rows, shovelerdb_result_kind_of(&selected));
    try std.testing.expectEqual(@as(usize, 6), shovelerdb_result_column_count(&selected));
    try std.testing.expectEqual(@as(usize, 1), shovelerdb_result_row_count(&selected));

    var column_name = shovelerdb_string_view{ .data = null, .len = 0 };
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_result_column_name(&selected, 1, &column_name));
    try std.testing.expectEqualStrings("id", column_name.data.?[0..column_name.len]);

    var row: ?*const shovelerdb_row = null;
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_result_next(&selected, &row));
    const current_row = row orelse return error.ExpectedRow;

    var kind_out = shovelerdb_value_kind.null;
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_kind(current_row, 0, &kind_out));
    try std.testing.expectEqual(shovelerdb_value_kind.null, kind_out);

    var int_out: i64 = 0;
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_int64(current_row, 1, &int_out));
    try std.testing.expectEqual(@as(i64, 7), int_out);

    var float_out: f64 = 0;
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_float64(current_row, 2, &float_out));
    try std.testing.expectEqual(@as(f64, 1.5), float_out);

    var bool_out: u8 = 0;
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_bool(current_row, 3, &bool_out));
    try std.testing.expectEqual(@as(u8, 1), bool_out);

    var text_out = shovelerdb_string_view{ .data = null, .len = 0 };
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_text(current_row, 4, &text_out));
    try std.testing.expectEqualStrings("memory", text_out.data.?[0..text_out.len]);

    var vector_out = shovelerdb_f32_vector_view{ .data = null, .len = 0 };
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_vector_f32(current_row, 5, &vector_out));
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.75 }, vector_out.data.?[0..vector_out.len]);

    try std.testing.expectEqual(shovelerdb_status.type_error, shovelerdb_row_value_int64(current_row, 4, &int_out));
    try std.testing.expectEqual(shovelerdb_status.invalid_argument, shovelerdb_result_next(&selected, null));
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_result_next(&selected, &row));
    try std.testing.expect(row == null);
}

test "C ABI reads blob values from borrowed row views" {
    const test_allocator = std.testing.allocator;
    const db_value = @import("../db/value.zig");
    const executor = @import("../db/executor.zig");

    const values = try test_allocator.alloc(db_value.Value, 1);
    values[0] = try db_value.Value.initBlob(test_allocator, &.{ 0xCA, 0xFE });
    var row = executor.ResultRow{ .values = values };
    defer row.deinit(test_allocator);

    const row_view: *const shovelerdb_row = @ptrCast(&row);
    var blob_out = shovelerdb_bytes_view{ .data = null, .len = 0 };
    try std.testing.expectEqual(shovelerdb_status.ok, shovelerdb_row_value_blob(row_view, 0, &blob_out));
    try std.testing.expectEqualSlices(u8, &.{ 0xCA, 0xFE }, blob_out.data.?[0..blob_out.len]);
}
