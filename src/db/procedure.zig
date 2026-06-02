const std = @import("std");
const ast = @import("../sql/ast.zig");
const procedure_body = @import("../sql/procedure_body.zig");

pub const ProcedureError = error{
    DuplicateObject,
    UnknownObject,
    UnsupportedProcedure,
};

pub const DiagnosticKind = enum {
    duplicate_object,
    unknown_object,
    unsupported_procedure,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.UnsupportedProcedure => .unsupported_procedure,
        else => null,
    };
}

pub const StoredProcedure = struct {
    name: []u8,
    params: []ast.ProcedureParam,
    body: procedure_body.Body,

    pub fn deinit(self: *StoredProcedure, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.params) |param| param.deinit(allocator);
        allocator.free(self.params);
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

pub const ProcedureRegistry = struct {
    allocator: std.mem.Allocator,
    procedures: std.ArrayList(StoredProcedure) = .empty,

    pub fn init(allocator: std.mem.Allocator) ProcedureRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ProcedureRegistry) void {
        for (self.procedures.items) |*stored| stored.deinit(self.allocator);
        self.procedures.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn create(
        self: *ProcedureRegistry,
        name: []const u8,
        params: []const ast.ProcedureParam,
        body_sql: []const u8,
    ) !void {
        if (self.findIndex(name) != null) return error.DuplicateObject;

        var stored = StoredProcedure{
            .name = try self.allocator.dupe(u8, name),
            .params = &.{},
            .body = .{},
        };
        errdefer self.allocator.free(stored.name);

        stored.params = try cloneParams(self.allocator, params);
        errdefer {
            for (stored.params) |param| param.deinit(self.allocator);
            self.allocator.free(stored.params);
        }

        stored.body = procedure_body.parse(self.allocator, body_sql) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.UnsupportedProcedure,
        };
        errdefer stored.body.deinit(self.allocator);

        try self.procedures.append(self.allocator, stored);
    }

    pub fn drop(self: *ProcedureRegistry, name: []const u8) ProcedureError!void {
        const index = self.findIndex(name) orelse return error.UnknownObject;
        var stored = self.procedures.orderedRemove(index);
        stored.deinit(self.allocator);
    }

    pub fn get(self: *const ProcedureRegistry, name: []const u8) ?*const StoredProcedure {
        const index = self.findIndex(name) orelse return null;
        return &self.procedures.items[index];
    }

    fn findIndex(self: *const ProcedureRegistry, name: []const u8) ?usize {
        for (self.procedures.items, 0..) |stored, index| {
            if (std.ascii.eqlIgnoreCase(stored.name, name)) return index;
        }
        return null;
    }
};

fn cloneParams(allocator: std.mem.Allocator, params: []const ast.ProcedureParam) ![]ast.ProcedureParam {
    var cloned = try allocator.alloc(ast.ProcedureParam, params.len);
    errdefer allocator.free(cloned);

    var count: usize = 0;
    errdefer {
        for (cloned[0..count]) |param| param.deinit(allocator);
    }

    for (params, 0..) |param, index| {
        cloned[index] = .{
            .name = try allocator.dupe(u8, param.name),
            .column_type = param.column_type,
            .mode = param.mode,
        };
        count += 1;
    }

    return cloned;
}

test "procedure registry stores a constrained single statement body" {
    const allocator = std.testing.allocator;

    var registry = ProcedureRegistry.init(allocator);
    defer registry.deinit();

    try registry.create("remember", &.{}, "BEGIN INSERT INTO memories VALUES (1, 'hi'); END");
    try std.testing.expectEqual(@as(usize, 1), registry.get("REMEMBER").?.body.statements.len);
    try std.testing.expectEqual(
        @as(std.meta.Tag(ast.Statement), .insert),
        std.meta.activeTag(registry.get("REMEMBER").?.body.statements[0].sql.statement),
    );

    try std.testing.expectError(
        error.DuplicateObject,
        registry.create("remember", &.{}, "BEGIN SELECT * FROM memories; END"),
    );

    try registry.drop("remember");
    try std.testing.expect(registry.get("remember") == null);
    try std.testing.expectError(error.UnknownObject, registry.drop("remember"));
}

test "procedure registry stores parameters and parsed multi statement bodies" {
    const allocator = std.testing.allocator;

    var registry = ProcedureRegistry.init(allocator);
    defer registry.deinit();

    const params = [_]ast.ProcedureParam{
        .{ .name = "p_id", .column_type = .integer },
        .{ .name = "p_body", .column_type = .text },
    };

    try registry.create(
        "remember",
        &params,
        "BEGIN DECLARE attempts INT DEFAULT 0; SET attempts = attempts + 1; INSERT INTO memories (id, body) VALUES (p_id, p_body); END",
    );
    try std.testing.expectEqual(@as(usize, 2), registry.get("remember").?.params.len);
    try std.testing.expectEqual(@as(usize, 3), registry.get("remember").?.body.statements.len);
}

test "procedure registry rejects unsupported stored-program features" {
    const allocator = std.testing.allocator;

    var registry = ProcedureRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expectError(
        error.UnsupportedProcedure,
        registry.create("cursor_proc", &.{}, "BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        registry.create("bare", &.{}, "SELECT 1"),
    );
}
