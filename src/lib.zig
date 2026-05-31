const std = @import("std");

pub const sql = struct {
    pub const tokenizer = @import("sql/tokenizer.zig");
    pub const policy = @import("sql/policy.zig");
};

pub const Project = struct {
    pub const name = "ShovelerDB";
    pub const dialect = "MariaDB-like SQL";
    pub const implementation_language = "Zig";
};

pub const FeaturePolicy = struct {
    pub const transactions = true;
    pub const tables = true;
    pub const views = true;
    pub const procedures = true;
    pub const vectors = true;
    pub const foreign_keys = false;
    pub const temporary_tables = false;
    pub const replication = false;
    pub const plugins = false;
};

test "project policy is intentionally smaller than MariaDB" {
    try std.testing.expect(FeaturePolicy.transactions);
    try std.testing.expect(FeaturePolicy.tables);
    try std.testing.expect(FeaturePolicy.views);
    try std.testing.expect(FeaturePolicy.procedures);
    try std.testing.expect(FeaturePolicy.vectors);
    try std.testing.expect(!FeaturePolicy.foreign_keys);
    try std.testing.expect(!FeaturePolicy.temporary_tables);
    try std.testing.expect(!FeaturePolicy.replication);
    try std.testing.expect(!FeaturePolicy.plugins);
}

test {
    std.testing.refAllDecls(sql.tokenizer);
    std.testing.refAllDecls(sql.policy);
}
