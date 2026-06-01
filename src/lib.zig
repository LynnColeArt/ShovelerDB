const std = @import("std");

pub const sql = struct {
    pub const ast = @import("sql/ast.zig");
    pub const parser = @import("sql/parser.zig");
    pub const tokenizer = @import("sql/tokenizer.zig");
    pub const policy = @import("sql/policy.zig");
};

pub const db = struct {
    pub const value = @import("db/value.zig");
    pub const catalog = @import("db/catalog.zig");
    pub const row_store = @import("db/row_store.zig");
    pub const transaction = @import("db/transaction.zig");
    pub const view = @import("db/view.zig");
    pub const procedure = @import("db/procedure.zig");
    pub const executor = @import("db/executor.zig");
    pub const persistence = @import("db/persistence.zig");
    pub const database = @import("db/database.zig");
};

pub const vector = struct {
    pub const distance = @import("vector/distance.zig");
    pub const search = @import("vector/search.zig");
};

pub const mariadb = struct {
    pub const test_analyzer = @import("mariadb/test_analyzer.zig");
    pub const test_classifier = @import("mariadb/test_classifier.zig");
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
    std.testing.refAllDecls(sql.ast);
    std.testing.refAllDecls(sql.parser);
    std.testing.refAllDecls(sql.tokenizer);
    std.testing.refAllDecls(sql.policy);
    std.testing.refAllDecls(db.value);
    std.testing.refAllDecls(db.catalog);
    std.testing.refAllDecls(db.row_store);
    std.testing.refAllDecls(db.transaction);
    std.testing.refAllDecls(db.view);
    std.testing.refAllDecls(db.procedure);
    std.testing.refAllDecls(db.executor);
    std.testing.refAllDecls(db.persistence);
    std.testing.refAllDecls(db.database);
    std.testing.refAllDecls(vector.distance);
    std.testing.refAllDecls(vector.search);
    std.testing.refAllDecls(mariadb.test_analyzer);
    std.testing.refAllDecls(mariadb.test_classifier);
}
