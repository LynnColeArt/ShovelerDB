const std = @import("std");
const handles = @import("handles.zig");

pub const shovelerdb_database = handles.DatabaseHandle;
pub const shovelerdb_result = handles.ResultHandle;
pub const shovelerdb_row = opaque {};

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

export fn shovelerdb_abi_version_major() u32 {
    return abi_version_major;
}

export fn shovelerdb_abi_version_minor() u32 {
    return abi_version_minor;
}

export fn shovelerdb_abi_version_patch() u32 {
    return abi_version_patch;
}

export fn shovelerdb_open_or_create(
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
        return statusFromError(err);
    };

    out.* = handle;
    return .ok;
}

export fn shovelerdb_close(database: ?*shovelerdb_database) void {
    const handle = database orelse return;
    handle.deinit();
    handles.allocator.destroy(handle);
}

export fn shovelerdb_checkpoint(database: ?*shovelerdb_database) shovelerdb_status {
    const handle = database orelse return .invalid_handle;
    handle.checkpoint() catch |err| {
        const status = statusFromError(err);
        handle.last_status = status;
        return status;
    };
    return .ok;
}

export fn shovelerdb_execute(
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
        const status = statusFromError(err);
        handle.last_status = status;
        handles.allocator.destroy(result_handle);
        return status;
    };

    out.* = result_handle;
    return .ok;
}

export fn shovelerdb_result_release(result: ?*shovelerdb_result) void {
    const handle = result orelse return;
    handle.deinit();
    handles.allocator.destroy(handle);
}

export fn shovelerdb_result_kind_of(result: ?*const shovelerdb_result) shovelerdb_result_kind {
    const handle = result orelse return .empty;
    return handle.kind();
}

export fn shovelerdb_result_mutation_count(result: ?*const shovelerdb_result) u64 {
    const handle = result orelse return 0;
    return handle.mutationCount();
}

export fn shovelerdb_result_column_count(result: ?*const shovelerdb_result) usize {
    const handle = result orelse return 0;
    return handle.columnCount();
}

export fn shovelerdb_result_column_name(
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

export fn shovelerdb_result_next(
    result: ?*shovelerdb_result,
    out_row: ?*?*const shovelerdb_row,
) shovelerdb_status {
    _ = result;
    if (out_row) |out| out.* = null;
    return .unsupported;
}

export fn shovelerdb_row_value_kind(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_kind: ?*shovelerdb_value_kind,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_kind) |out| out.* = .null;
    return .unsupported;
}

export fn shovelerdb_row_value_int64(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*i64,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = 0;
    return .unsupported;
}

export fn shovelerdb_row_value_float64(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*f64,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = 0;
    return .unsupported;
}

export fn shovelerdb_row_value_bool(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*u8,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = 0;
    return .unsupported;
}

export fn shovelerdb_row_value_text(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_string_view,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = .{ .data = null, .len = 0 };
    return .unsupported;
}

export fn shovelerdb_row_value_blob(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_bytes_view,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = .{ .data = null, .len = 0 };
    return .unsupported;
}

export fn shovelerdb_row_value_vector_f32(
    row: ?*const shovelerdb_row,
    column_index: usize,
    out_value: ?*shovelerdb_f32_vector_view,
) shovelerdb_status {
    _ = row;
    _ = column_index;
    if (out_value) |out| out.* = .{ .data = null, .len = 0 };
    return .unsupported;
}

export fn shovelerdb_status_diagnostic_code(status: shovelerdb_status) shovelerdb_diagnostic_code {
    return diagnosticCodeFromStatus(status);
}

export fn shovelerdb_status_message(status: shovelerdb_status) [*:0]const u8 {
    return statusMessage(status);
}

export fn shovelerdb_database_last_diagnostic(
    database: ?*const shovelerdb_database,
    out_code: ?*shovelerdb_diagnostic_code,
    out_message: ?*shovelerdb_string_view,
) shovelerdb_status {
    const handle = database orelse return .invalid_handle;
    const code_out = out_code orelse return .invalid_argument;
    const message_out = out_message orelse return .invalid_argument;
    const message = statusMessage(handle.last_status);
    const message_slice = std.mem.span(message);
    code_out.* = diagnosticCodeFromStatus(handle.last_status);
    message_out.* = .{ .data = message_slice.ptr, .len = message_slice.len };
    return .ok;
}

fn statusFromError(err: anyerror) shovelerdb_status {
    return switch (err) {
        error.OutOfMemory => .allocation_failed,
        error.InvalidHandle => .invalid_handle,
        error.ParseDiagnostic => .parse_error,
        error.DuplicateObject,
        error.UnknownObject,
        error.NameConflict,
        error.UnknownColumn,
        error.AmbiguousColumn,
        error.ColumnCountMismatch,
        => .object_error,
        error.TransactionRequired,
        error.TransactionActive,
        error.NoActiveTransaction,
        error.AlreadyCommitted,
        error.AlreadyRolledBack,
        => .transaction_error,
        error.TypeMismatch,
        error.InvalidGrouping,
        => .type_error,
        error.VectorDimensionMismatch,
        error.InvalidVectorDimension,
        error.ZeroVector,
        => .vector_error,
        error.InvalidHeader,
        error.UnsupportedVersion,
        error.TruncatedPayload,
        error.PayloadLengthMismatch,
        error.PayloadChecksumMismatch,
        error.InvalidColumnType,
        error.InvalidValueTag,
        error.InvalidBooleanEncoding,
        error.InvalidVectorElementType,
        error.RowStoreMismatch,
        error.ValueTooLarge,
        => .persistence_error,
        error.FileNotFound,
        error.AccessDenied,
        error.FileTooBig,
        error.IsDir,
        error.NoSpaceLeft,
        error.NotDir,
        error.PathAlreadyExists,
        error.SystemResources,
        error.WouldBlock,
        error.InputOutput,
        => .io_error,
        error.UnsupportedExpression,
        error.UnsupportedView,
        error.UnsupportedProcedure,
        => .unsupported,
        else => .internal_error,
    };
}

fn diagnosticCodeFromStatus(status: shovelerdb_status) shovelerdb_diagnostic_code {
    return switch (status) {
        .ok => .none,
        .invalid_argument => .invalid_argument,
        .invalid_handle => .invalid_handle,
        .allocation_failed => .allocation,
        .parse_error => .parser,
        .object_error => .object,
        .transaction_error => .transaction,
        .type_error => .type,
        .vector_error => .vector,
        .persistence_error => .persistence,
        .io_error => .io,
        .unsupported => .unsupported,
        .internal_error => .internal,
    };
}

fn statusMessage(status: shovelerdb_status) [*:0]const u8 {
    return switch (status) {
        .ok => "ok",
        .invalid_argument => "invalid argument",
        .invalid_handle => "invalid handle",
        .allocation_failed => "allocation failed",
        .parse_error => "SQL parse error",
        .object_error => "object or catalog error",
        .transaction_error => "transaction error",
        .type_error => "type error",
        .vector_error => "vector error",
        .persistence_error => "persistence error",
        .io_error => "I/O error",
        .unsupported => "unsupported SQL surface",
        .internal_error => "internal error",
    };
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
