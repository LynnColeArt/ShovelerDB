const std = @import("std");
const ast = @import("../sql/ast.zig");

pub const ViewError = error{
    DuplicateObject,
    UnknownObject,
    UnsupportedView,
};

pub const DiagnosticKind = enum {
    duplicate_object,
    unknown_object,
    unsupported_view,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.UnsupportedView => .unsupported_view,
        else => null,
    };
}

pub const StoredView = struct {
    name: []u8,
    query: ast.SelectStatement,

    pub fn deinit(self: *StoredView, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.query.deinit(allocator);
        self.* = undefined;
    }
};

pub const ViewRegistry = struct {
    allocator: std.mem.Allocator,
    views: std.ArrayList(StoredView) = .empty,

    pub fn init(allocator: std.mem.Allocator) ViewRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ViewRegistry) void {
        for (self.views.items) |*stored| stored.deinit(self.allocator);
        self.views.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn create(self: *ViewRegistry, name: []const u8, query: ast.SelectStatement) !void {
        if (self.findIndex(name) != null) return error.DuplicateObject;
        if (query.source == null and query.from == null) return error.UnsupportedView;

        var stored = StoredView{
            .name = try self.allocator.dupe(u8, name),
            .query = undefined,
        };
        errdefer self.allocator.free(stored.name);

        stored.query = try cloneSelect(self.allocator, query);
        errdefer stored.query.deinit(self.allocator);

        try self.views.append(self.allocator, stored);
    }

    pub fn drop(self: *ViewRegistry, name: []const u8) ViewError!void {
        const index = self.findIndex(name) orelse return error.UnknownObject;
        var stored = self.views.orderedRemove(index);
        stored.deinit(self.allocator);
    }

    pub fn get(self: *const ViewRegistry, name: []const u8) ?*const StoredView {
        const index = self.findIndex(name) orelse return null;
        return &self.views.items[index];
    }

    fn findIndex(self: *const ViewRegistry, name: []const u8) ?usize {
        for (self.views.items, 0..) |stored, index| {
            if (std.ascii.eqlIgnoreCase(stored.name, name)) return index;
        }
        return null;
    }
};

pub fn cloneSelect(allocator: std.mem.Allocator, source: ast.SelectStatement) anyerror!ast.SelectStatement {
    var ctes = try allocator.alloc(ast.CommonTableExpression, source.ctes.len);
    errdefer allocator.free(ctes);

    var cte_count: usize = 0;
    errdefer {
        for (ctes[0..cte_count]) |cte| cte.deinit(allocator);
    }
    for (source.ctes, 0..) |cte, index| {
        var query: ?*ast.SelectStatement = try allocator.create(ast.SelectStatement);
        errdefer if (query) |owned| allocator.destroy(owned);
        query.?.* = try cloneSelect(allocator, cte.query.*);
        errdefer if (query) |owned| owned.deinit(allocator);

        ctes[index] = .{
            .name = try allocator.dupe(u8, cte.name),
            .query = query.?,
        };
        query = null;
        cte_count += 1;
    }

    var projection_items = try allocator.alloc(ast.Projection, source.projection_items.len);
    errdefer allocator.free(projection_items);

    var projection_item_count: usize = 0;
    errdefer {
        for (projection_items[0..projection_item_count]) |projection| projection.deinit(allocator);
    }
    for (source.projection_items, 0..) |projection, index| {
        var expression: ?ast.Expression = try cloneExpression(allocator, projection.expression);
        errdefer if (expression) |expr| expr.deinit(allocator);
        var alias: ?[]const u8 = if (projection.alias) |source_alias| try allocator.dupe(u8, source_alias) else null;
        errdefer if (alias) |owned| allocator.free(owned);

        projection_items[index] = .{
            .expression = expression.?,
            .alias = alias,
        };
        expression = null;
        alias = null;
        projection_item_count += 1;
    }

    var projections = try allocator.alloc(ast.Expression, source.projections.len);
    errdefer allocator.free(projections);

    var projection_count: usize = 0;
    errdefer {
        for (projections[0..projection_count]) |projection| projection.deinit(allocator);
    }
    for (source.projections, 0..) |projection, index| {
        projections[index] = try cloneExpression(allocator, projection);
        projection_count += 1;
    }

    var from: ?[]const u8 = null;
    errdefer if (from) |owned| allocator.free(owned);
    if (source.from) |table| from = try allocator.dupe(u8, table);

    var row_source: ?*ast.RowSource = null;
    errdefer if (row_source) |owned| {
        owned.deinit(allocator);
        allocator.destroy(owned);
    };
    if (source.source) |owned_source| {
        row_source = try cloneRowSourcePtr(allocator, owned_source.*);
    }

    var where_clause: ?ast.Expression = null;
    errdefer if (where_clause) |expr| expr.deinit(allocator);
    if (source.where_clause) |expr| where_clause = try cloneExpression(allocator, expr);

    var group_by = try allocator.alloc(ast.Expression, source.group_by.len);
    errdefer allocator.free(group_by);

    var group_count: usize = 0;
    errdefer {
        for (group_by[0..group_count]) |group_key| group_key.deinit(allocator);
    }
    for (source.group_by, 0..) |group_key, index| {
        group_by[index] = try cloneExpression(allocator, group_key);
        group_count += 1;
    }

    var having: ?ast.Expression = null;
    errdefer if (having) |expr| expr.deinit(allocator);
    if (source.having) |expr| having = try cloneExpression(allocator, expr);

    var order_by = try allocator.alloc(ast.OrderKey, source.order_by.len);
    errdefer allocator.free(order_by);

    var order_count: usize = 0;
    errdefer {
        for (order_by[0..order_count]) |order| order.deinit(allocator);
    }
    for (source.order_by, 0..) |order, index| {
        order_by[index] = .{
            .expression = try cloneExpression(allocator, order.expression),
            .direction = order.direction,
        };
        order_count += 1;
    }

    return .{
        .ctes = ctes,
        .projection_items = projection_items,
        .projections = projections,
        .from = from,
        .source = row_source,
        .where_clause = where_clause,
        .group_by = group_by,
        .having = having,
        .order_by = order_by,
        .limit = source.limit,
    };
}

fn cloneRowSourcePtr(allocator: std.mem.Allocator, source: ast.RowSource) anyerror!*ast.RowSource {
    const cloned = try allocator.create(ast.RowSource);
    errdefer allocator.destroy(cloned);
    cloned.* = try cloneRowSource(allocator, source);
    return cloned;
}

fn cloneRowSource(allocator: std.mem.Allocator, source: ast.RowSource) anyerror!ast.RowSource {
    return switch (source) {
        .base_table => |table| blk: {
            var name: ?[]u8 = try allocator.dupe(u8, table.name);
            errdefer if (name) |owned| allocator.free(owned);
            var alias: ?[]u8 = if (table.alias) |source_alias| try allocator.dupe(u8, source_alias) else null;
            errdefer if (alias) |owned| allocator.free(owned);
            const owned_name = name.?;
            name = null;
            const owned_alias = alias;
            alias = null;
            break :blk .{ .base_table = .{
                .name = owned_name,
                .alias = owned_alias,
            } };
        },
        .derived_table => |derived| blk: {
            var query: ?*ast.SelectStatement = try allocator.create(ast.SelectStatement);
            errdefer if (query) |owned| allocator.destroy(owned);
            query.?.* = try cloneSelect(allocator, derived.query.*);
            errdefer if (query) |owned| owned.deinit(allocator);
            const alias = try allocator.dupe(u8, derived.alias);
            errdefer allocator.free(alias);
            const owned_query = query.?;
            query = null;
            break :blk .{ .derived_table = .{
                .query = owned_query,
                .alias = alias,
            } };
        },
        .join => |join| blk: {
            const left = try cloneRowSourcePtr(allocator, join.left.*);
            errdefer {
                left.deinit(allocator);
                allocator.destroy(left);
            }
            const right = try cloneRowSourcePtr(allocator, join.right.*);
            errdefer {
                right.deinit(allocator);
                allocator.destroy(right);
            }
            break :blk .{ .join = .{
                .left = left,
                .join_type = join.join_type,
                .right = right,
                .on = if (join.on) |on| try cloneExpression(allocator, on) else null,
            } };
        },
    };
}

pub fn cloneExpression(allocator: std.mem.Allocator, source: ast.Expression) !ast.Expression {
    return switch (source) {
        .star => .star,
        .identifier => |identifier| .{ .identifier = try allocator.dupe(u8, identifier) },
        .literal => |literal| .{ .literal = try cloneLiteral(allocator, literal) },
        .function_call => |call| blk: {
            var args = try allocator.alloc(ast.Expression, call.args.len);
            errdefer allocator.free(args);

            var count: usize = 0;
            errdefer {
                for (args[0..count]) |arg| arg.deinit(allocator);
            }
            for (call.args, 0..) |arg, index| {
                args[index] = try cloneExpression(allocator, arg);
                count += 1;
            }

            break :blk .{
                .function_call = .{
                    .name = try allocator.dupe(u8, call.name),
                    .args = args,
                },
            };
        },
        .binary => |binary| blk: {
            const left = try allocator.create(ast.Expression);
            errdefer allocator.destroy(left);
            left.* = try cloneExpression(allocator, binary.left.*);
            errdefer left.deinit(allocator);

            const right = try allocator.create(ast.Expression);
            errdefer allocator.destroy(right);
            right.* = try cloneExpression(allocator, binary.right.*);

            break :blk .{
                .binary = .{
                    .left = left,
                    .operator = binary.operator,
                    .right = right,
                },
            };
        },
    };
}

fn cloneLiteral(allocator: std.mem.Allocator, source: ast.Literal) !ast.Literal {
    return switch (source) {
        .null => .null,
        .integer => |v| .{ .integer = v },
        .float => |v| .{ .float = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| .{ .string = try allocator.dupe(u8, v) },
        .vector => |v| .{ .vector = try allocator.dupe(f64, v) },
    };
}

test "view registry clones select statements" {
    const allocator = std.testing.allocator;

    var registry = ViewRegistry.init(allocator);
    defer registry.deinit();

    var source = ast.SelectStatement{
        .projections = try allocator.dupe(ast.Expression, &.{.{ .star = {} }}),
        .from = try allocator.dupe(u8, "memories"),
        .where_clause = null,
        .order_by = &.{},
        .limit = 10,
    };
    defer source.deinit(allocator);

    try registry.create("recent", source);
    try std.testing.expectEqual(@as(usize, 10), registry.get("RECENT").?.query.limit.?);
    try std.testing.expectEqualStrings("memories", registry.get("recent").?.query.from.?);

    try std.testing.expectError(error.DuplicateObject, registry.create("recent", source));
    try registry.drop("recent");
    try std.testing.expect(registry.get("recent") == null);
    try std.testing.expectError(error.UnknownObject, registry.drop("recent"));
}

test "view registry rejects sourceless views" {
    const allocator = std.testing.allocator;

    var registry = ViewRegistry.init(allocator);
    defer registry.deinit();

    var source = ast.SelectStatement{
        .projections = try allocator.dupe(ast.Expression, &.{.{ .literal = .{ .integer = 1 } }}),
        .from = null,
    };
    defer source.deinit(allocator);

    try std.testing.expectError(error.UnsupportedView, registry.create("constant_view", source));
}
