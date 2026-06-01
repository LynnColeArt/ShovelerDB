const std = @import("std");

pub const VectorError = error{
    VectorDimensionMismatch,
    ZeroVector,
};

pub const DiagnosticKind = enum {
    vector_dimension_mismatch,
    zero_vector,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.ZeroVector => .zero_vector,
        else => null,
    };
}

pub fn squaredL2(left: []const f32, right: []const f32) VectorError!f64 {
    try expectSameDimension(left, right);

    var sum: f64 = 0;
    for (left, right) |l, r| {
        const delta = @as(f64, l) - @as(f64, r);
        sum += delta * delta;
    }
    return sum;
}

pub fn l2(left: []const f32, right: []const f32) VectorError!f64 {
    return std.math.sqrt(try squaredL2(left, right));
}

pub fn cosineDistance(left: []const f32, right: []const f32) VectorError!f64 {
    try expectSameDimension(left, right);

    var dot: f64 = 0;
    var left_norm_squared: f64 = 0;
    var right_norm_squared: f64 = 0;

    for (left, right) |l_raw, r_raw| {
        const l = @as(f64, l_raw);
        const r = @as(f64, r_raw);
        dot += l * r;
        left_norm_squared += l * l;
        right_norm_squared += r * r;
    }

    if (left_norm_squared == 0 or right_norm_squared == 0) return error.ZeroVector;

    const similarity = dot / (std.math.sqrt(left_norm_squared) * std.math.sqrt(right_norm_squared));
    return 1.0 - similarity;
}

fn expectSameDimension(left: []const f32, right: []const f32) VectorError!void {
    if (left.len != right.len) return error.VectorDimensionMismatch;
}

test "squared L2 and L2 match known distances" {
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), try squaredL2(&.{ 0, 0 }, &.{ 3, 4 }), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try l2(&.{ 0, 0 }, &.{ 3, 4 }), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try l2(&.{ 1, -2, 3 }, &.{ 1, -2, 3 }), 0.000001);
}

test "cosine distance handles normalized and non-normalized vectors" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try cosineDistance(&.{ 1, 0 }, &.{ 5, 0 }), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try cosineDistance(&.{ 1, 0 }, &.{ 0, 2 }), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try cosineDistance(&.{ 1, 0 }, &.{ -4, 0 }), 0.000001);
}

test "distance helpers reject dimension mismatch and zero-vector cosine" {
    try std.testing.expectError(error.VectorDimensionMismatch, squaredL2(&.{ 1, 2 }, &.{ 1, 2, 3 }));
    try std.testing.expectError(error.VectorDimensionMismatch, cosineDistance(&.{1}, &.{ 1, 2 }));
    try std.testing.expectError(error.ZeroVector, cosineDistance(&.{ 0, 0 }, &.{ 1, 0 }));
}

test "distance diagnostics map stable typed errors" {
    try std.testing.expectEqual(DiagnosticKind.vector_dimension_mismatch, diagnosticFromError(error.VectorDimensionMismatch).?);
    try std.testing.expectEqual(DiagnosticKind.zero_vector, diagnosticFromError(error.ZeroVector).?);
    try std.testing.expect(diagnosticFromError(error.OutOfMemory) == null);
}
