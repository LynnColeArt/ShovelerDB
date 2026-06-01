const std = @import("std");

pub const ValueError = error{
    TypeMismatch,
    VectorDimensionMismatch,
    InvalidVectorDimension,
};

pub const VectorElementType = enum {
    float32,
};

pub const Vector = struct {
    element_type: VectorElementType = .float32,
    dimension: usize,
    values: []f32,

    pub fn init(
        allocator: std.mem.Allocator,
        element_type: VectorElementType,
        dimension: usize,
        values: []const f32,
    ) !Vector {
        if (dimension == 0) return error.InvalidVectorDimension;
        if (values.len != dimension) return error.VectorDimensionMismatch;

        return .{
            .element_type = element_type,
            .dimension = dimension,
            .values = try allocator.dupe(f32, values),
        };
    }

    pub fn clone(self: Vector, allocator: std.mem.Allocator) !Vector {
        return init(allocator, self.element_type, self.dimension, self.values);
    }

    pub fn deinit(self: *Vector, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        self.* = undefined;
    }
};

pub const Value = union(enum) {
    null,
    integer: i64,
    float: f64,
    boolean: bool,
    text: []u8,
    blob: []u8,
    vector: Vector,

    pub fn initText(allocator: std.mem.Allocator, text: []const u8) !Value {
        return .{ .text = try allocator.dupe(u8, text) };
    }

    pub fn initBlob(allocator: std.mem.Allocator, bytes: []const u8) !Value {
        return .{ .blob = try allocator.dupe(u8, bytes) };
    }

    pub fn initVector(
        allocator: std.mem.Allocator,
        element_type: VectorElementType,
        dimension: usize,
        values: []const f32,
    ) !Value {
        return .{ .vector = try Vector.init(allocator, element_type, dimension, values) };
    }

    pub fn clone(self: Value, allocator: std.mem.Allocator) !Value {
        return switch (self) {
            .null => .null,
            .integer => |v| .{ .integer = v },
            .float => |v| .{ .float = v },
            .boolean => |v| .{ .boolean = v },
            .text => |v| .{ .text = try allocator.dupe(u8, v) },
            .blob => |v| .{ .blob = try allocator.dupe(u8, v) },
            .vector => |v| .{ .vector = try v.clone(allocator) },
        };
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |bytes| allocator.free(bytes),
            .blob => |bytes| allocator.free(bytes),
            .vector => |*vector| vector.deinit(allocator),
            else => {},
        }
        self.* = .null;
    }
};

pub const DiagnosticKind = enum {
    type_mismatch,
    vector_dimension_mismatch,
    invalid_vector_dimension,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.TypeMismatch => .type_mismatch,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        else => null,
    };
}

test "scalar values clone heap-owned bytes independently" {
    const allocator = std.testing.allocator;

    var original = try Value.initText(allocator, "memory");
    defer original.deinit(allocator);

    var copy = try original.clone(allocator);
    defer copy.deinit(allocator);

    try std.testing.expectEqualStrings("memory", original.text);
    try std.testing.expectEqualStrings("memory", copy.text);
    try std.testing.expect(original.text.ptr != copy.text.ptr);

    var blob = try Value.initBlob(allocator, &.{ 0x01, 0x02, 0x03 });
    defer blob.deinit(allocator);

    var blob_copy = try blob.clone(allocator);
    defer blob_copy.deinit(allocator);

    try std.testing.expectEqualSlices(u8, blob.blob, blob_copy.blob);
    try std.testing.expect(blob.blob.ptr != blob_copy.blob.ptr);
}

test "vector values carry dimension and element metadata" {
    const allocator = std.testing.allocator;

    var value = try Value.initVector(allocator, .float32, 3, &.{ 1.0, 2.0, 3.0 });
    defer value.deinit(allocator);

    try std.testing.expectEqual(VectorElementType.float32, value.vector.element_type);
    try std.testing.expectEqual(@as(usize, 3), value.vector.dimension);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 2.0, 3.0 }, value.vector.values);

    try std.testing.expectError(
        error.VectorDimensionMismatch,
        Value.initVector(allocator, .float32, 4, &.{ 1.0, 2.0, 3.0 }),
    );
    try std.testing.expectError(
        error.InvalidVectorDimension,
        Value.initVector(allocator, .float32, 0, &.{}),
    );
}

test "vector clone owns a separate backing slice" {
    const allocator = std.testing.allocator;

    var original = try Value.initVector(allocator, .float32, 2, &.{ 0.25, 0.75 });
    defer original.deinit(allocator);

    var copy = try original.clone(allocator);
    defer copy.deinit(allocator);

    try std.testing.expectEqualSlices(f32, original.vector.values, copy.vector.values);
    try std.testing.expect(original.vector.values.ptr != copy.vector.values.ptr);
}

test "value diagnostics map stable typed errors" {
    try std.testing.expectEqual(DiagnosticKind.type_mismatch, diagnosticFromError(error.TypeMismatch).?);
    try std.testing.expectEqual(
        DiagnosticKind.vector_dimension_mismatch,
        diagnosticFromError(error.VectorDimensionMismatch).?,
    );
    try std.testing.expectEqual(
        DiagnosticKind.invalid_vector_dimension,
        diagnosticFromError(error.InvalidVectorDimension).?,
    );
    try std.testing.expect(diagnosticFromError(error.OutOfMemory) == null);
}
