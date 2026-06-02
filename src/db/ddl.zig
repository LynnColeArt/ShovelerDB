const std = @import("std");

pub const IndexKind = enum {
    primary,
    secondary,
};

pub const primary_index_name = "PRIMARY";

pub fn namesEqual(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

test "DDL name comparison is case-insensitive" {
    try std.testing.expect(namesEqual("PRIMARY", "primary"));
}
