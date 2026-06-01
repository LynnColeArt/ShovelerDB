const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub const UnsupportedFeature = enum {
    foreign_key,
    temporary_table,
    storage_engine_selection,
    replication,
    user_auth,
    plugin,

    pub fn label(self: UnsupportedFeature) []const u8 {
        return switch (self) {
            .foreign_key => "foreign keys",
            .temporary_table => "temporary tables",
            .storage_engine_selection => "storage engine selection",
            .replication => "replication/binlog",
            .user_auth => "users/grants/auth",
            .plugin => "plugins",
        };
    }
};

pub const PolicyViolation = struct {
    feature: UnsupportedFeature,
    offset: usize,
    token: []const u8,

    pub fn message(self: PolicyViolation) []const u8 {
        return self.feature.label();
    }
};

const Keyword = enum {
    begin,
    binlog,
    commit,
    create,
    engine,
    foreign,
    grant,
    install,
    key,
    plugin,
    replication,
    references,
    revoke,
    rollback,
    table,
    temp,
    temporary,
    uninstall,
    user,
    view,
    procedure,
};

const SeenKeyword = struct {
    keyword: Keyword,
    offset: usize,
};

pub fn firstViolation(sql: []const u8) ?PolicyViolation {
    var tokens = tokenizer.Tokenizer.init(sql);
    var prev: ?SeenKeyword = null;
    var prev2: ?SeenKeyword = null;
    var in_create_table = false;
    var paren_depth: usize = 0;

    while (tokens.next()) |token| {
        if (token.kind == .symbol) {
            if (std.mem.eql(u8, token.lexeme, ";")) {
                in_create_table = false;
                paren_depth = 0;
                prev = null;
                prev2 = null;
                continue;
            }

            if (in_create_table and std.mem.eql(u8, token.lexeme, "(")) {
                paren_depth += 1;
            } else if (in_create_table and std.mem.eql(u8, token.lexeme, ")")) {
                if (paren_depth > 0) paren_depth -= 1;
            }
            continue;
        }

        if (token.kind != .identifier) continue;
        const keyword = keywordOf(token) orelse continue;

        if (keyword == .grant or keyword == .revoke) {
            return violation(.user_auth, token);
        }

        if (keyword == .binlog or keyword == .replication) {
            return violation(.replication, token);
        }

        if (keyword == .references) {
            return violation(.foreign_key, token);
        }

        if (prev) |p| {
            if (p.keyword == .foreign and keyword == .key) {
                return violation(.foreign_key, token);
            }

            if (p.keyword == .create and keyword == .user) {
                return violation(.user_auth, token);
            }

            if ((p.keyword == .install or p.keyword == .uninstall) and keyword == .plugin) {
                return violation(.plugin, token);
            }
        }

        if (keyword == .table) {
            if (prev) |p| {
                if (p.keyword == .temporary or p.keyword == .temp) {
                    return violation(.temporary_table, token);
                }
                if (p.keyword == .create) {
                    in_create_table = true;
                    paren_depth = 0;
                }
            }
            if (prev2) |p2| {
                if (p2.keyword == .create and prev != null and
                    (prev.?.keyword == .temporary or prev.?.keyword == .temp))
                {
                    return violation(.temporary_table, token);
                }
            }
        }

        if (in_create_table and paren_depth == 0 and keyword == .engine) {
            return violation(.storage_engine_selection, token);
        }

        prev2 = prev;
        prev = .{ .keyword = keyword, .offset = token.offset };
    }

    return null;
}

pub fn accepts(sql: []const u8) bool {
    return firstViolation(sql) == null;
}

fn violation(feature: UnsupportedFeature, token: tokenizer.Token) PolicyViolation {
    return .{
        .feature = feature,
        .offset = token.offset,
        .token = token.lexeme,
    };
}

fn keywordOf(token: tokenizer.Token) ?Keyword {
    if (token.eqlIgnoreCase("BEGIN")) return .begin;
    if (token.eqlIgnoreCase("BINLOG")) return .binlog;
    if (token.eqlIgnoreCase("COMMIT")) return .commit;
    if (token.eqlIgnoreCase("CREATE")) return .create;
    if (token.eqlIgnoreCase("ENGINE")) return .engine;
    if (token.eqlIgnoreCase("FOREIGN")) return .foreign;
    if (token.eqlIgnoreCase("GRANT")) return .grant;
    if (token.eqlIgnoreCase("INSTALL")) return .install;
    if (token.eqlIgnoreCase("KEY")) return .key;
    if (token.eqlIgnoreCase("PLUGIN")) return .plugin;
    if (token.eqlIgnoreCase("PROCEDURE")) return .procedure;
    if (token.eqlIgnoreCase("REPLICATION")) return .replication;
    if (token.eqlIgnoreCase("REFERENCES")) return .references;
    if (token.eqlIgnoreCase("REVOKE")) return .revoke;
    if (token.eqlIgnoreCase("ROLLBACK")) return .rollback;
    if (token.eqlIgnoreCase("TABLE")) return .table;
    if (token.eqlIgnoreCase("TEMP")) return .temp;
    if (token.eqlIgnoreCase("TEMPORARY")) return .temporary;
    if (token.eqlIgnoreCase("UNINSTALL")) return .uninstall;
    if (token.eqlIgnoreCase("USER")) return .user;
    if (token.eqlIgnoreCase("VIEW")) return .view;
    return null;
}

test "policy accepts ShovelerDB sacred surface" {
    try std.testing.expect(accepts(
        \\CREATE TABLE memories (id INTEGER PRIMARY KEY, body TEXT, embedding VECTOR(4));
        \\CREATE VIEW recent_memories AS SELECT * FROM memories;
        \\CREATE PROCEDURE remember() BEGIN INSERT INTO memories VALUES (1, 'hi', '[0,0,0,0]'); COMMIT; END;
    ));
}

test "policy rejects foreign keys loudly" {
    const result = firstViolation(
        \\CREATE TABLE child (
        \\  parent_id INTEGER,
        \\  FOREIGN KEY (parent_id) REFERENCES parent(id)
        \\);
    ) orelse return error.ExpectedViolation;

    try std.testing.expectEqual(UnsupportedFeature.foreign_key, result.feature);

    const references_result = firstViolation(
        \\CREATE TABLE child (
        \\  parent_id INTEGER REFERENCES parent(id)
        \\);
    ) orelse return error.ExpectedViolation;

    try std.testing.expectEqual(UnsupportedFeature.foreign_key, references_result.feature);
}

test "policy rejects temporary tables loudly" {
    const result = firstViolation(
        \\CREATE TEMPORARY TABLE stage (id INTEGER);
    ) orelse return error.ExpectedViolation;

    try std.testing.expectEqual(UnsupportedFeature.temporary_table, result.feature);
}

test "policy rejects storage engine selection outside column definitions" {
    const result = firstViolation(
        \\CREATE TABLE t (id INTEGER) ENGINE=InnoDB;
    ) orelse return error.ExpectedViolation;

    try std.testing.expectEqual(UnsupportedFeature.storage_engine_selection, result.feature);
}

test "policy ignores rejected keywords in comments and strings" {
    try std.testing.expect(accepts(
        \\-- CREATE TEMPORARY TABLE nope (id INTEGER);
        \\CREATE TABLE notes (body TEXT DEFAULT 'FOREIGN KEY is text');
    ));
}

test "policy rejects server-era administration" {
    try std.testing.expectEqual(
        UnsupportedFeature.user_auth,
        (firstViolation("GRANT SELECT ON *.* TO 'agent'@'localhost';") orelse return error.ExpectedViolation).feature,
    );
    try std.testing.expectEqual(
        UnsupportedFeature.plugin,
        (firstViolation("INSTALL PLUGIN foo SONAME 'foo.so';") orelse return error.ExpectedViolation).feature,
    );
    try std.testing.expectEqual(
        UnsupportedFeature.replication,
        (firstViolation("SHOW BINLOG EVENTS;") orelse return error.ExpectedViolation).feature,
    );
}
