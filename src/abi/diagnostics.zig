const std = @import("std");
const handles = @import("handles.zig");

pub fn statusFromError(err: anyerror) handles.StatusCode {
    return switch (err) {
        error.OutOfMemory => .allocation_failed,
        error.InvalidArgument => .invalid_argument,
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

pub fn diagnosticCodeFromStatus(status: handles.StatusCode) handles.DiagnosticCode {
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

pub fn statusMessage(status: handles.StatusCode) [*:0]const u8 {
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

test "ABI diagnostics map stable status categories" {
    try std.testing.expectEqual(handles.StatusCode.vector_error, statusFromError(error.VectorDimensionMismatch));
    try std.testing.expectEqual(handles.StatusCode.transaction_error, statusFromError(error.TransactionRequired));
    try std.testing.expectEqual(handles.StatusCode.object_error, statusFromError(error.UnknownObject));
    try std.testing.expectEqual(handles.DiagnosticCode.vector, diagnosticCodeFromStatus(.vector_error));
    try std.testing.expectEqualStrings("vector error", std.mem.span(statusMessage(.vector_error)));
}
