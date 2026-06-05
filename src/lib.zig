const std = @import("std");

pub const sql = struct {
    pub const ast = @import("sql/ast.zig");
    pub const parser = @import("sql/parser.zig");
    pub const procedure_body = @import("sql/procedure_body.zig");
    pub const tokenizer = @import("sql/tokenizer.zig");
    pub const policy = @import("sql/policy.zig");
};

pub const db = struct {
    pub const value = @import("db/value.zig");
    pub const catalog = @import("db/catalog.zig");
    pub const ddl = @import("db/ddl.zig");
    pub const aggregate = @import("db/aggregate.zig");
    pub const checkpoint_worker = @import("db/checkpoint_worker.zig");
    pub const concurrency = @import("db/concurrency.zig");
    pub const backpressure = @import("db/backpressure.zig");
    pub const commit_queue = @import("db/commit_queue.zig");
    pub const snapshot = @import("db/snapshot.zig");
    pub const row_store = @import("db/row_store.zig");
    pub const transaction = @import("db/transaction.zig");
    pub const query_source = @import("db/query_source.zig");
    pub const view = @import("db/view.zig");
    pub const procedure = @import("db/procedure.zig");
    pub const executor = @import("db/executor.zig");
    pub const persistence = @import("db/persistence.zig");
    pub const database = @import("db/database.zig");
};

pub const abi = struct {
    pub const c_api = @import("abi/c_api.zig");
    pub const diagnostics = @import("abi/diagnostics.zig");
    pub const handles = @import("abi/handles.zig");
    pub const result = @import("abi/result.zig");
    pub const value_access = @import("abi/value_access.zig");
};

pub const vector = struct {
    pub const distance = @import("vector/distance.zig");
    pub const overlay = @import("vector/overlay.zig");
    pub const search = @import("vector/search.zig");
};

pub const mariadb = struct {
    pub const test_analyzer = @import("mariadb/test_analyzer.zig");
    pub const test_classifier = @import("mariadb/test_classifier.zig");
    pub const mtr_lite = @import("mariadb/mtr_lite.zig");
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
    std.testing.refAllDecls(sql.procedure_body);
    std.testing.refAllDecls(sql.tokenizer);
    std.testing.refAllDecls(sql.policy);
    std.testing.refAllDecls(db.value);
    std.testing.refAllDecls(db.catalog);
    std.testing.refAllDecls(db.ddl);
    std.testing.refAllDecls(db.aggregate);
    std.testing.refAllDecls(db.checkpoint_worker);
    std.testing.refAllDecls(db.concurrency);
    std.testing.refAllDecls(db.backpressure);
    std.testing.refAllDecls(db.commit_queue);
    std.testing.refAllDecls(db.snapshot);
    std.testing.refAllDecls(db.row_store);
    std.testing.refAllDecls(db.transaction);
    std.testing.refAllDecls(db.query_source);
    std.testing.refAllDecls(db.view);
    std.testing.refAllDecls(db.procedure);
    std.testing.refAllDecls(db.executor);
    std.testing.refAllDecls(db.persistence);
    std.testing.refAllDecls(db.database);
    std.testing.refAllDecls(abi.c_api);
    std.testing.refAllDecls(abi.diagnostics);
    std.testing.refAllDecls(abi.handles);
    std.testing.refAllDecls(abi.result);
    std.testing.refAllDecls(abi.value_access);
    std.testing.refAllDecls(vector.distance);
    std.testing.refAllDecls(vector.overlay);
    std.testing.refAllDecls(vector.search);
    std.testing.refAllDecls(mariadb.test_analyzer);
    std.testing.refAllDecls(mariadb.test_classifier);
    std.testing.refAllDecls(mariadb.mtr_lite);
}
