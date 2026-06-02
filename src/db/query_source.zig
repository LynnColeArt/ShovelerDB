const std = @import("std");
const ast = @import("../sql/ast.zig");
const aggregate = @import("aggregate.zig");
const catalog = @import("catalog.zig");
const row_store = @import("row_store.zig");
const value = @import("value.zig");
const vector_distance = @import("../vector/distance.zig");

pub const ResultRow = struct {
    values: []value.Value,
};

pub const ResultSet = struct {
    columns: [][]u8,
    rows: []ResultRow,
};

pub const BaseTable = struct {
    name: []const u8,
    columns: []const catalog.ColumnDef,
    rows: []row_store.Row,

    pub fn deinit(self: *BaseTable, allocator: std.mem.Allocator) void {
        row_store.deinitRows(allocator, self.rows);
        self.* = undefined;
    }
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    user_data: *anyopaque,
    load_base_table: *const fn (*anyopaque, []const u8) anyerror!BaseTable,
    find_view: *const fn (*anyopaque, []const u8) ?*const ast.SelectStatement,
};

const CteScope = struct {
    ctes: []const ast.CommonTableExpression,
    parent: ?*const CteScope = null,
};

const CteLookup = struct {
    scope: *const CteScope,
    index: usize,
};

const ColumnBinding = struct {
    name: []u8,
    labels: [][]u8,

    fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        labels: []const []const u8,
    ) !ColumnBinding {
        var owned_labels = try allocator.alloc([]u8, labels.len);
        errdefer allocator.free(owned_labels);

        var count: usize = 0;
        errdefer {
            for (owned_labels[0..count]) |label| allocator.free(label);
        }
        for (labels, 0..) |label, index| {
            owned_labels[index] = try allocator.dupe(u8, label);
            count += 1;
        }

        return .{
            .name = try allocator.dupe(u8, name),
            .labels = owned_labels,
        };
    }

    fn clone(allocator: std.mem.Allocator, source: ColumnBinding) !ColumnBinding {
        var label_refs = try allocator.alloc([]const u8, source.labels.len);
        defer allocator.free(label_refs);
        for (source.labels, 0..) |label, index| label_refs[index] = label;
        return init(allocator, source.name, label_refs);
    }

    fn deinit(self: *ColumnBinding, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.labels) |label| allocator.free(label);
        allocator.free(self.labels);
        self.* = undefined;
    }

    fn hasLabel(self: ColumnBinding, label: []const u8) bool {
        for (self.labels) |candidate| {
            if (std.ascii.eqlIgnoreCase(candidate, label)) return true;
        }
        return false;
    }
};

const Row = struct {
    values: []value.Value,

    fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        deinitValues(allocator, self.values);
        allocator.free(self.values);
        self.* = undefined;
    }
};

const RowSet = struct {
    columns: []ColumnBinding,
    rows: []Row,

    fn deinit(self: *RowSet, allocator: std.mem.Allocator) void {
        for (self.columns) |*column| column.deinit(allocator);
        allocator.free(self.columns);
        for (self.rows) |*row| row.deinit(allocator);
        allocator.free(self.rows);
        self.* = undefined;
    }
};

const ProjectionItem = struct {
    expression: ast.Expression,
    alias: ?[]const u8 = null,
};

const Group = struct {
    keys: []value.Value,
    row_indices: std.ArrayList(usize) = .empty,

    fn deinit(self: *Group, allocator: std.mem.Allocator) void {
        deinitValues(allocator, self.keys);
        allocator.free(self.keys);
        self.row_indices.deinit(allocator);
        self.* = undefined;
    }
};

pub fn executeSelect(ctx: Context, statement: ast.SelectStatement) anyerror!ResultSet {
    return executeSelectScoped(ctx, statement, null, 0);
}

fn executeSelectScoped(
    ctx: Context,
    statement: ast.SelectStatement,
    parent_scope: ?*const CteScope,
    depth: usize,
) anyerror!ResultSet {
    const source = statement.source orelse return error.UnknownObject;
    const scope = CteScope{ .ctes = statement.ctes, .parent = parent_scope };

    var row_set = try executeSource(ctx, source.*, &scope, depth);
    defer row_set.deinit(ctx.allocator);

    var filtered_indices: std.ArrayList(usize) = .empty;
    defer filtered_indices.deinit(ctx.allocator);
    for (row_set.rows, 0..) |row, index| {
        if (try matchesWhere(ctx.allocator, row_set, row, statement.where_clause)) {
            try filtered_indices.append(ctx.allocator, index);
        }
    }

    const projections = try projectionItems(ctx.allocator, statement);
    defer ctx.allocator.free(projections);

    if (isAggregateSelect(statement, projections)) {
        return executeAggregateSelect(ctx, row_set, filtered_indices.items, statement, projections);
    }

    try validateSelect(row_set, statement, projections);

    try sortIndices(ctx.allocator, row_set, filtered_indices.items, statement.order_by, projections);

    const row_limit = if (statement.limit) |limit| @min(limit, filtered_indices.items.len) else filtered_indices.items.len;
    const columns = try resultColumns(ctx.allocator, row_set, projections);
    errdefer deinitColumns(ctx.allocator, columns);

    const rows = try ctx.allocator.alloc(ResultRow, row_limit);
    errdefer ctx.allocator.free(rows);

    var built_rows: usize = 0;
    errdefer {
        for (rows[0..built_rows]) |*row| {
            deinitValues(ctx.allocator, row.values);
            ctx.allocator.free(row.values);
        }
    }
    for (filtered_indices.items[0..row_limit], 0..) |row_index, out_index| {
        rows[out_index] = .{
            .values = try projectRow(ctx.allocator, row_set, row_set.rows[row_index], projections),
        };
        built_rows += 1;
    }

    return .{ .columns = columns, .rows = rows };
}

fn executeSource(ctx: Context, source: ast.RowSource, scope: *const CteScope, depth: usize) anyerror!RowSet {
    return switch (source) {
        .base_table => |table| try executeNamedSource(ctx, table, scope, depth),
        .derived_table => |derived| try executeDerivedSource(ctx, derived, scope, depth),
        .join => |join| try executeJoinSource(ctx, join, scope, depth),
    };
}

fn executeNamedSource(ctx: Context, source: ast.TableSource, scope: *const CteScope, depth: usize) anyerror!RowSet {
    if (findCte(scope, source.name)) |lookup| {
        const cte = lookup.scope.ctes[lookup.index];
        const definition_scope = CteScope{
            .ctes = lookup.scope.ctes[0..lookup.index],
            .parent = lookup.scope.parent,
        };
        var result = try executeSelectScoped(ctx, cte.query.*, &definition_scope, depth + 1);
        defer deinitResultSet(ctx.allocator, &result);
        return rowSetFromResult(ctx.allocator, result, source.name, source.alias);
    }

    if (ctx.find_view(ctx.user_data, source.name)) |view_query| {
        if (depth >= 8) return error.UnsupportedView;
        var result = try executeSelectScoped(ctx, view_query.*, scope, depth + 1);
        defer deinitResultSet(ctx.allocator, &result);
        return rowSetFromResult(ctx.allocator, result, source.name, source.alias);
    }

    var table = try ctx.load_base_table(ctx.user_data, source.name);
    defer table.deinit(ctx.allocator);
    return rowSetFromBaseTable(ctx.allocator, table, source.alias);
}

fn executeDerivedSource(ctx: Context, source: ast.DerivedTableSource, scope: *const CteScope, depth: usize) anyerror!RowSet {
    var result = try executeSelectScoped(ctx, source.query.*, scope, depth + 1);
    defer deinitResultSet(ctx.allocator, &result);
    return rowSetFromResult(ctx.allocator, result, source.alias, null);
}

fn executeJoinSource(ctx: Context, source: ast.JoinSource, scope: *const CteScope, depth: usize) anyerror!RowSet {
    var left = try executeSource(ctx, source.left.*, scope, depth);
    defer left.deinit(ctx.allocator);
    var right = try executeSource(ctx, source.right.*, scope, depth);
    defer right.deinit(ctx.allocator);

    var joined = RowSet{
        .columns = try concatColumns(ctx.allocator, left.columns, right.columns),
        .rows = &.{},
    };
    errdefer joined.deinit(ctx.allocator);

    if (source.on) |on| try validateExpression(joined, on);

    var rows: std.ArrayList(Row) = .empty;
    errdefer {
        for (rows.items) |*row| row.deinit(ctx.allocator);
        rows.deinit(ctx.allocator);
    }

    for (left.rows) |left_row| {
        var matched = false;
        for (right.rows) |right_row| {
            var combined = try concatRows(ctx.allocator, left_row, right_row);
            errdefer combined.deinit(ctx.allocator);
            if (source.on) |on| {
                if (!try matchesWhere(ctx.allocator, joined, combined, on)) {
                    combined.deinit(ctx.allocator);
                    continue;
                }
            }
            matched = true;
            try rows.append(ctx.allocator, combined);
        }

        if (source.join_type == .left and !matched) {
            try rows.append(ctx.allocator, try concatRowWithNulls(ctx.allocator, left_row, right.columns.len));
        }
    }

    joined.rows = try rows.toOwnedSlice(ctx.allocator);
    return joined;
}

fn rowSetFromBaseTable(allocator: std.mem.Allocator, table: BaseTable, alias: ?[]const u8) !RowSet {
    const labels = try sourceLabels(allocator, table.name, alias);
    defer allocator.free(labels);

    var columns = try allocator.alloc(ColumnBinding, table.columns.len);
    errdefer allocator.free(columns);
    var column_count: usize = 0;
    errdefer {
        for (columns[0..column_count]) |*column| column.deinit(allocator);
    }
    for (table.columns, 0..) |column, index| {
        columns[index] = try ColumnBinding.init(allocator, column.name, labels);
        column_count += 1;
    }

    var rows = try allocator.alloc(Row, table.rows.len);
    errdefer allocator.free(rows);
    var row_count: usize = 0;
    errdefer {
        for (rows[0..row_count]) |*row| row.deinit(allocator);
    }
    for (table.rows, 0..) |row, index| {
        rows[index] = .{ .values = try cloneValueSlice(allocator, row.values) };
        row_count += 1;
    }

    return .{ .columns = columns, .rows = rows };
}

fn rowSetFromResult(
    allocator: std.mem.Allocator,
    result: ResultSet,
    source_name: []const u8,
    alias: ?[]const u8,
) !RowSet {
    const labels = try sourceLabels(allocator, source_name, alias);
    defer allocator.free(labels);

    var columns = try allocator.alloc(ColumnBinding, result.columns.len);
    errdefer allocator.free(columns);
    var column_count: usize = 0;
    errdefer {
        for (columns[0..column_count]) |*column| column.deinit(allocator);
    }
    for (result.columns, 0..) |column, index| {
        columns[index] = try ColumnBinding.init(allocator, column, labels);
        column_count += 1;
    }

    var rows = try allocator.alloc(Row, result.rows.len);
    errdefer allocator.free(rows);
    var row_count: usize = 0;
    errdefer {
        for (rows[0..row_count]) |*row| row.deinit(allocator);
    }
    for (result.rows, 0..) |row, index| {
        rows[index] = .{ .values = try cloneValueSlice(allocator, row.values) };
        row_count += 1;
    }

    return .{ .columns = columns, .rows = rows };
}

fn sourceLabels(allocator: std.mem.Allocator, source_name: []const u8, alias: ?[]const u8) ![][]const u8 {
    if (alias) |source_alias| {
        const labels = try allocator.alloc([]const u8, 2);
        labels[0] = source_alias;
        labels[1] = source_name;
        return labels;
    }
    const labels = try allocator.alloc([]const u8, 1);
    labels[0] = source_name;
    return labels;
}

fn findCte(scope: *const CteScope, name: []const u8) ?CteLookup {
    var current: ?*const CteScope = scope;
    while (current) |candidate_scope| {
        for (candidate_scope.ctes, 0..) |cte, index| {
            if (std.ascii.eqlIgnoreCase(cte.name, name)) {
                return .{ .scope = candidate_scope, .index = index };
            }
        }
        current = candidate_scope.parent;
    }
    return null;
}

fn validateSelect(row_set: RowSet, statement: ast.SelectStatement, projections: []const ProjectionItem) !void {
    for (projections) |projection| try validateExpression(row_set, projection.expression);
    if (statement.where_clause) |where_clause| try validateExpression(row_set, where_clause);
    for (statement.order_by) |order| try validateOrderExpression(row_set, order.expression, projections);
}

fn validateOrderExpression(
    row_set: RowSet,
    expression: ast.Expression,
    projections: []const ProjectionItem,
) !void {
    if (expression == .identifier) {
        const parts = ast.identifierParts(expression.identifier);
        if (parts.qualifier == null) {
            var match: ?ast.Expression = null;
            for (projections) |projection| {
                if (projection.alias) |alias| {
                    if (std.ascii.eqlIgnoreCase(alias, parts.name)) {
                        if (match != null) return error.AmbiguousColumn;
                        match = projection.expression;
                    }
                }
            }
            if (match) |projection_expression| {
                return validateExpression(row_set, projection_expression);
            }
        }
    }
    return validateExpression(row_set, expression);
}

fn isAggregateSelect(statement: ast.SelectStatement, projections: []const ProjectionItem) bool {
    if (statement.group_by.len > 0 or statement.having != null) return true;
    for (projections) |projection| {
        if (aggregate.expressionContainsAggregate(projection.expression)) return true;
    }
    for (statement.order_by) |order| {
        if (aggregate.expressionContainsAggregate(order.expression)) return true;
    }
    return false;
}

fn executeAggregateSelect(
    ctx: Context,
    row_set: RowSet,
    filtered_indices: []const usize,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) !ResultSet {
    try validateAggregateSelect(row_set, statement, projections);

    const groups = try buildGroups(ctx.allocator, row_set, filtered_indices, statement.group_by);
    defer deinitGroups(ctx.allocator, groups);

    var accepted_indices: std.ArrayList(usize) = .empty;
    defer accepted_indices.deinit(ctx.allocator);
    for (groups, 0..) |group, index| {
        if (try groupMatchesHaving(ctx.allocator, row_set, group, statement, projections)) {
            try accepted_indices.append(ctx.allocator, index);
        }
    }

    try sortGroupIndices(ctx.allocator, row_set, groups, accepted_indices.items, statement, projections);

    const row_limit = if (statement.limit) |limit| @min(limit, accepted_indices.items.len) else accepted_indices.items.len;
    const columns = try resultColumns(ctx.allocator, row_set, projections);
    errdefer deinitColumns(ctx.allocator, columns);

    const rows = try ctx.allocator.alloc(ResultRow, row_limit);
    errdefer ctx.allocator.free(rows);

    var built_rows: usize = 0;
    errdefer {
        for (rows[0..built_rows]) |*row| {
            deinitValues(ctx.allocator, row.values);
            ctx.allocator.free(row.values);
        }
    }
    for (accepted_indices.items[0..row_limit], 0..) |group_index, out_index| {
        rows[out_index] = .{
            .values = try projectGroup(ctx.allocator, row_set, groups[group_index], statement, projections),
        };
        built_rows += 1;
    }

    return .{ .columns = columns, .rows = rows };
}

fn validateAggregateSelect(
    row_set: RowSet,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) !void {
    if (isStarProjection(projections)) return error.InvalidGrouping;

    for (statement.group_by) |group_key| {
        if (aggregate.expressionContainsAggregate(group_key)) return error.InvalidGrouping;
        try validateExpression(row_set, group_key);
    }
    if (statement.where_clause) |where_clause| try validateExpression(row_set, where_clause);
    for (projections) |projection| {
        try validateGroupedExpression(row_set, statement, projections, projection.expression, false);
    }
    if (statement.having) |having| {
        try validateGroupedExpression(row_set, statement, projections, having, true);
    }
    for (statement.order_by) |order| {
        try validateGroupedExpression(row_set, statement, projections, order.expression, true);
    }
}

fn validateGroupedExpression(
    row_set: RowSet,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
    expression: ast.Expression,
    allow_alias: bool,
) !void {
    if (allow_alias) {
        if (projectionAliasExpression(expression, projections)) |projection_expression| {
            return validateGroupedExpression(row_set, statement, projections, projection_expression, false);
        }
    }

    return switch (expression) {
        .literal => {},
        .star => error.InvalidGrouping,
        .identifier => {
            if (!expressionMatchesGroupBy(expression, statement.group_by)) return error.InvalidGrouping;
            try validateExpression(row_set, expression);
        },
        .binary => |binary| {
            try validateGroupedExpression(row_set, statement, projections, binary.left.*, allow_alias);
            try validateGroupedExpression(row_set, statement, projections, binary.right.*, allow_alias);
        },
        .function_call => |call| {
            if (aggregate.functionForName(call.name) != null) {
                return validateAggregateCall(row_set, call);
            }
            if (!expressionMatchesGroupBy(expression, statement.group_by)) return error.InvalidGrouping;
            try validateExpression(row_set, expression);
        },
    };
}

fn validateAggregateCall(row_set: RowSet, call: ast.FunctionCall) !void {
    const function = aggregate.functionForName(call.name) orelse return error.UnsupportedExpression;
    if (call.args.len != 1) return error.UnsupportedExpression;
    const arg = call.args[0];
    if (aggregate.expressionContainsAggregate(arg)) return error.InvalidGrouping;

    if (function == .count and arg == .star) return;
    if (arg == .star) return error.UnsupportedExpression;
    try validateExpression(row_set, arg);
}

fn buildGroups(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    filtered_indices: []const usize,
    group_by: []const ast.Expression,
) ![]Group {
    var groups: std.ArrayList(Group) = .empty;
    errdefer {
        for (groups.items) |*group| group.deinit(allocator);
        groups.deinit(allocator);
    }

    if (group_by.len == 0) {
        var group: ?Group = Group{ .keys = try allocator.alloc(value.Value, 0) };
        errdefer if (group) |*owned| owned.deinit(allocator);
        for (filtered_indices) |row_index| try group.?.row_indices.append(allocator, row_index);
        try groups.append(allocator, group.?);
        group = null;
        return groups.toOwnedSlice(allocator);
    }

    for (filtered_indices) |row_index| {
        const keys = try evalGroupKeys(allocator, row_set, row_set.rows[row_index], group_by);
        if (try findGroup(groups.items, keys)) |group_index| {
            deinitValues(allocator, keys);
            allocator.free(keys);
            try groups.items[group_index].row_indices.append(allocator, row_index);
            continue;
        }

        var group: ?Group = Group{ .keys = keys };
        errdefer if (group) |*owned| owned.deinit(allocator);
        try group.?.row_indices.append(allocator, row_index);
        try groups.append(allocator, group.?);
        group = null;
    }

    return groups.toOwnedSlice(allocator);
}

fn evalGroupKeys(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    group_by: []const ast.Expression,
) ![]value.Value {
    var keys = try allocator.alloc(value.Value, group_by.len);
    errdefer allocator.free(keys);

    var count: usize = 0;
    errdefer deinitValues(allocator, keys[0..count]);
    for (group_by, 0..) |group_key, index| {
        keys[index] = try evalExpression(allocator, row_set, row, group_key);
        count += 1;
    }
    return keys;
}

fn findGroup(groups: []const Group, keys: []const value.Value) !?usize {
    for (groups, 0..) |group, index| {
        if (try groupKeysEqual(group.keys, keys)) return index;
    }
    return null;
}

fn groupKeysEqual(left: []const value.Value, right: []const value.Value) !bool {
    if (left.len != right.len) return false;
    for (left, right) |left_value, right_value| {
        if (!try valuesEquivalent(left_value, right_value)) return false;
    }
    return true;
}

fn valuesEquivalent(left: value.Value, right: value.Value) !bool {
    if (left == .null or right == .null) return left == .null and right == .null;
    const comparison = compareValues(left, right) catch return false;
    return comparison == 0;
}

fn groupMatchesHaving(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) !bool {
    const having = statement.having orelse return true;
    var result = try evalGroupedExpression(allocator, row_set, group, statement, projections, having, true);
    defer result.deinit(allocator);
    if (result != .boolean) return error.TypeMismatch;
    return result.boolean;
}

fn sortGroupIndices(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    groups: []const Group,
    indices: []usize,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) !void {
    if (statement.order_by.len == 0 or indices.len < 2) return;

    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        var j = i;
        while (j > 0 and try groupComesAfter(
            allocator,
            row_set,
            groups[indices[j - 1]],
            groups[indices[j]],
            statement,
            projections,
        )) : (j -= 1) {
            std.mem.swap(usize, &indices[j - 1], &indices[j]);
        }
    }
}

fn groupComesAfter(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    left: Group,
    right: Group,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) !bool {
    for (statement.order_by) |order| {
        var left_value = try evalGroupedExpression(allocator, row_set, left, statement, projections, order.expression, true);
        defer left_value.deinit(allocator);
        var right_value = try evalGroupedExpression(allocator, row_set, right, statement, projections, order.expression, true);
        defer right_value.deinit(allocator);

        const comparison = try compareValues(left_value, right_value);
        if (comparison == 0) continue;
        return if (order.direction == .asc) comparison > 0 else comparison < 0;
    }
    return false;
}

fn projectGroup(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
) ![]value.Value {
    var values = try allocator.alloc(value.Value, projections.len);
    errdefer allocator.free(values);
    var count: usize = 0;
    errdefer deinitValues(allocator, values[0..count]);

    for (projections, 0..) |projection, index| {
        values[index] = try evalGroupedExpression(allocator, row_set, group, statement, projections, projection.expression, false);
        count += 1;
    }
    return values;
}

fn evalGroupedExpression(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
    expression: ast.Expression,
    allow_alias: bool,
) anyerror!value.Value {
    if (allow_alias) {
        if (projectionAliasExpression(expression, projections)) |projection_expression| {
            return evalGroupedExpression(allocator, row_set, group, statement, projections, projection_expression, false);
        }
    }

    return switch (expression) {
        .literal => |literal| try valueFromLiteral(allocator, literal),
        .star => error.InvalidGrouping,
        .identifier => {
            if (!expressionMatchesGroupBy(expression, statement.group_by)) return error.InvalidGrouping;
            return evalRepresentativeExpression(allocator, row_set, group, expression);
        },
        .binary => |binary| try evalGroupedBinary(allocator, row_set, group, statement, projections, binary, allow_alias),
        .function_call => |call| {
            if (aggregate.functionForName(call.name)) |_| {
                return evalAggregateCall(allocator, row_set, group, call);
            }
            if (!expressionMatchesGroupBy(expression, statement.group_by)) return error.InvalidGrouping;
            return evalRepresentativeExpression(allocator, row_set, group, expression);
        },
    };
}

fn evalGroupedBinary(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    statement: ast.SelectStatement,
    projections: []const ProjectionItem,
    binary: ast.BinaryExpression,
    allow_alias: bool,
) !value.Value {
    var left = try evalGroupedExpression(allocator, row_set, group, statement, projections, binary.left.*, allow_alias);
    defer left.deinit(allocator);
    var right = try evalGroupedExpression(allocator, row_set, group, statement, projections, binary.right.*, allow_alias);
    defer right.deinit(allocator);

    if (binary.operator == .and_op) {
        if (left != .boolean or right != .boolean) return error.TypeMismatch;
        return .{ .boolean = left.boolean and right.boolean };
    }

    return evalBinaryValues(left, right, binary.operator);
}

fn evalRepresentativeExpression(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    expression: ast.Expression,
) !value.Value {
    if (group.row_indices.items.len == 0) return error.InvalidGrouping;
    return evalExpression(allocator, row_set, row_set.rows[group.row_indices.items[0]], expression);
}

fn evalAggregateCall(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    group: Group,
    call: ast.FunctionCall,
) !value.Value {
    const function = aggregate.functionForName(call.name) orelse return error.UnsupportedExpression;
    if (call.args.len != 1) return error.UnsupportedExpression;
    const arg = call.args[0];

    if (function == .count and arg == .star) {
        return .{ .integer = @intCast(group.row_indices.items.len) };
    }
    if (arg == .star) return error.UnsupportedExpression;

    var count: usize = 0;
    var sum: f64 = 0;
    var best: ?value.Value = null;
    errdefer if (best) |*owned| owned.deinit(allocator);

    for (group.row_indices.items) |row_index| {
        var runtime_value = try evalExpression(allocator, row_set, row_set.rows[row_index], arg);
        defer runtime_value.deinit(allocator);
        if (runtime_value == .null) continue;

        switch (function) {
            .count => count += 1,
            .sum, .avg => {
                sum += try numericAsFloat(runtime_value);
                count += 1;
            },
            .min, .max => {
                if (best) |*owned| {
                    const comparison = try compareValues(runtime_value, owned.*);
                    const replace = if (function == .min) comparison < 0 else comparison > 0;
                    if (replace) {
                        owned.deinit(allocator);
                        owned.* = try runtime_value.clone(allocator);
                    }
                } else {
                    best = try runtime_value.clone(allocator);
                }
            },
        }
    }

    return switch (function) {
        .count => .{ .integer = @intCast(count) },
        .sum => if (count == 0) .null else .{ .float = sum },
        .avg => if (count == 0) .null else .{ .float = sum / @as(f64, @floatFromInt(count)) },
        .min, .max => if (best) |owned| owned else .null,
    };
}

fn numericAsFloat(runtime_value: value.Value) !f64 {
    return switch (runtime_value) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => error.TypeMismatch,
    };
}

fn projectionAliasExpression(expression: ast.Expression, projections: []const ProjectionItem) ?ast.Expression {
    if (expression != .identifier) return null;
    const parts = ast.identifierParts(expression.identifier);
    if (parts.qualifier != null) return null;

    var match: ?ast.Expression = null;
    for (projections) |projection| {
        const alias = projection.alias orelse continue;
        if (!std.ascii.eqlIgnoreCase(alias, parts.name)) continue;
        if (match != null) return null;
        match = projection.expression;
    }
    return match;
}

fn expressionMatchesGroupBy(expression: ast.Expression, group_by: []const ast.Expression) bool {
    for (group_by) |group_key| {
        if (expressionsEqual(expression, group_key)) return true;
    }
    return false;
}

fn expressionsEqual(left: ast.Expression, right: ast.Expression) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .star => true,
        .identifier => |identifier| std.ascii.eqlIgnoreCase(identifier, right.identifier),
        .literal => |literal| literalsEqual(literal, right.literal),
        .function_call => |call| blk: {
            const other = right.function_call;
            if (!std.ascii.eqlIgnoreCase(call.name, other.name) or call.args.len != other.args.len) break :blk false;
            for (call.args, other.args) |arg, other_arg| {
                if (!expressionsEqual(arg, other_arg)) break :blk false;
            }
            break :blk true;
        },
        .binary => |binary| blk: {
            const other = right.binary;
            break :blk binary.operator == other.operator and
                expressionsEqual(binary.left.*, other.left.*) and
                expressionsEqual(binary.right.*, other.right.*);
        },
    };
}

fn literalsEqual(left: ast.Literal, right: ast.Literal) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .null => true,
        .integer => |v| v == right.integer,
        .float => |v| v == right.float,
        .boolean => |v| v == right.boolean,
        .string => |v| std.mem.eql(u8, v, right.string),
        .vector => |v| std.mem.eql(f64, v, right.vector),
    };
}

fn deinitGroups(allocator: std.mem.Allocator, groups: []Group) void {
    for (groups) |*group| group.deinit(allocator);
    allocator.free(groups);
}

fn validateExpression(row_set: RowSet, expression: ast.Expression) !void {
    switch (expression) {
        .star, .literal => {},
        .identifier => |identifier| try validateIdentifier(row_set, identifier),
        .binary => |binary| {
            try validateExpression(row_set, binary.left.*);
            try validateExpression(row_set, binary.right.*);
        },
        .function_call => |call| {
            if (!isBuiltin(call.name, "l2_distance") and
                !isBuiltin(call.name, "squared_l2_distance") and
                !isBuiltin(call.name, "cosine_distance"))
            {
                return error.UnsupportedExpression;
            }
            if (call.args.len != 2) return error.UnsupportedExpression;
            for (call.args) |arg| try validateExpression(row_set, arg);
        },
    }
}

fn validateIdentifier(row_set: RowSet, identifier: []const u8) !void {
    const parts = ast.identifierParts(identifier);
    var matches: usize = 0;

    for (row_set.columns) |column| {
        if (!std.ascii.eqlIgnoreCase(column.name, parts.name)) continue;
        if (parts.qualifier) |qualifier| {
            if (!column.hasLabel(qualifier)) continue;
        }
        matches += 1;
    }

    if (matches == 0) return error.UnknownColumn;
    if (matches > 1) return error.AmbiguousColumn;
}

fn matchesWhere(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    where_clause: ?ast.Expression,
) !bool {
    const clause = where_clause orelse return true;
    var result = try evalExpression(allocator, row_set, row, clause);
    defer result.deinit(allocator);
    if (result != .boolean) return error.TypeMismatch;
    return result.boolean;
}

fn sortIndices(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    indices: []usize,
    order_by: []const ast.OrderKey,
    projections: []const ProjectionItem,
) !void {
    if (order_by.len == 0 or indices.len < 2) return;

    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        var j = i;
        while (j > 0 and try rowComesAfter(
            allocator,
            row_set,
            row_set.rows[indices[j - 1]],
            row_set.rows[indices[j]],
            order_by,
            projections,
        )) : (j -= 1) {
            std.mem.swap(usize, &indices[j - 1], &indices[j]);
        }
    }
}

fn rowComesAfter(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    left: Row,
    right: Row,
    order_by: []const ast.OrderKey,
    projections: []const ProjectionItem,
) !bool {
    for (order_by) |order| {
        var left_value = try evalOrderExpression(allocator, row_set, left, order.expression, projections);
        defer left_value.deinit(allocator);
        var right_value = try evalOrderExpression(allocator, row_set, right, order.expression, projections);
        defer right_value.deinit(allocator);

        const comparison = try compareValues(left_value, right_value);
        if (comparison == 0) continue;
        return if (order.direction == .asc) comparison > 0 else comparison < 0;
    }
    return false;
}

fn resultColumns(allocator: std.mem.Allocator, row_set: RowSet, projections: []const ProjectionItem) ![][]u8 {
    if (isStarProjection(projections)) {
        var columns = try allocator.alloc([]u8, row_set.columns.len);
        errdefer allocator.free(columns);
        var count: usize = 0;
        errdefer {
            for (columns[0..count]) |column| allocator.free(column);
        }
        for (row_set.columns, 0..) |column, index| {
            columns[index] = try allocator.dupe(u8, column.name);
            count += 1;
        }
        return columns;
    }

    var columns = try allocator.alloc([]u8, projections.len);
    errdefer allocator.free(columns);
    var count: usize = 0;
    errdefer {
        for (columns[0..count]) |column| allocator.free(column);
    }
    for (projections, 0..) |projection, index| {
        columns[index] = try allocator.dupe(u8, projectionName(projection));
        count += 1;
    }
    return columns;
}

fn projectRow(allocator: std.mem.Allocator, row_set: RowSet, row: Row, projections: []const ProjectionItem) ![]value.Value {
    if (isStarProjection(projections)) return cloneValueSlice(allocator, row.values);

    var values = try allocator.alloc(value.Value, projections.len);
    errdefer allocator.free(values);
    var count: usize = 0;
    errdefer deinitValues(allocator, values[0..count]);

    for (projections, 0..) |projection, index| {
        values[index] = try evalExpression(allocator, row_set, row, projection.expression);
        count += 1;
    }
    return values;
}

fn evalOrderExpression(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    expression: ast.Expression,
    projections: []const ProjectionItem,
) !value.Value {
    if (expression == .identifier) {
        const parts = ast.identifierParts(expression.identifier);
        if (parts.qualifier == null) {
            var match: ?ast.Expression = null;
            for (projections) |projection| {
                if (projection.alias) |alias| {
                    if (std.ascii.eqlIgnoreCase(alias, parts.name)) {
                        if (match != null) return error.AmbiguousColumn;
                        match = projection.expression;
                    }
                }
            }
            if (match) |projection_expression| {
                return evalExpression(allocator, row_set, row, projection_expression);
            }
        }
    }
    return evalExpression(allocator, row_set, row, expression);
}

fn evalExpression(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    expression: ast.Expression,
) anyerror!value.Value {
    return switch (expression) {
        .literal => |literal| try valueFromLiteral(allocator, literal),
        .identifier => |identifier| try resolveIdentifier(allocator, row_set, row, identifier),
        .binary => |binary| try evalBinary(allocator, row_set, row, binary),
        .function_call => |call| try evalFunctionCall(allocator, row_set, row, call),
        .star => error.UnsupportedExpression,
    };
}

fn resolveIdentifier(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    identifier: []const u8,
) !value.Value {
    const parts = ast.identifierParts(identifier);
    var match_index: ?usize = null;
    var matches: usize = 0;

    for (row_set.columns, 0..) |column, index| {
        if (!std.ascii.eqlIgnoreCase(column.name, parts.name)) continue;
        if (parts.qualifier) |qualifier| {
            if (!column.hasLabel(qualifier)) continue;
        }
        match_index = index;
        matches += 1;
    }

    if (matches == 0) return error.UnknownColumn;
    if (matches > 1) return error.AmbiguousColumn;
    return row.values[match_index.?].clone(allocator);
}

fn evalFunctionCall(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    call: ast.FunctionCall,
) anyerror!value.Value {
    if (isBuiltin(call.name, "l2_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, row_set, row, call, .l2) };
    }
    if (isBuiltin(call.name, "squared_l2_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, row_set, row, call, .squared_l2) };
    }
    if (isBuiltin(call.name, "cosine_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, row_set, row, call, .cosine) };
    }
    return error.UnsupportedExpression;
}

const VectorDistanceFunction = enum {
    l2,
    squared_l2,
    cosine,
};

fn evalVectorDistanceFunction(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    call: ast.FunctionCall,
    function: VectorDistanceFunction,
) !f64 {
    if (call.args.len != 2) return error.UnsupportedExpression;

    var left = try evalExpression(allocator, row_set, row, call.args[0]);
    defer left.deinit(allocator);
    var right = try evalExpression(allocator, row_set, row, call.args[1]);
    defer right.deinit(allocator);

    if (left != .vector or right != .vector) return error.TypeMismatch;
    return switch (function) {
        .l2 => try vector_distance.l2(left.vector.values, right.vector.values),
        .squared_l2 => try vector_distance.squaredL2(left.vector.values, right.vector.values),
        .cosine => try vector_distance.cosineDistance(left.vector.values, right.vector.values),
    };
}

fn evalBinary(
    allocator: std.mem.Allocator,
    row_set: RowSet,
    row: Row,
    binary: ast.BinaryExpression,
) !value.Value {
    var left = try evalExpression(allocator, row_set, row, binary.left.*);
    defer left.deinit(allocator);
    var right = try evalExpression(allocator, row_set, row, binary.right.*);
    defer right.deinit(allocator);

    return evalBinaryValues(left, right, binary.operator);
}

fn evalBinaryValues(left: value.Value, right: value.Value, operator: ast.BinaryOperator) !value.Value {
    return switch (operator) {
        .add => try evalNumericBinary(left, right, .add),
        .subtract => try evalNumericBinary(left, right, .subtract),
        .and_op => blk: {
            if (left != .boolean or right != .boolean) return error.TypeMismatch;
            break :blk .{ .boolean = left.boolean and right.boolean };
        },
        else => blk: {
            const comparison = try compareValues(left, right);
            break :blk .{ .boolean = switch (operator) {
                .equal => comparison == 0,
                .not_equal => comparison != 0,
                .less_than => comparison < 0,
                .less_equal => comparison <= 0,
                .greater_than => comparison > 0,
                .greater_equal => comparison >= 0,
                .add, .subtract, .and_op => unreachable,
            } };
        },
    };
}

const NumericOperator = enum {
    add,
    subtract,
};

fn evalNumericBinary(left: value.Value, right: value.Value, operator: NumericOperator) !value.Value {
    return switch (left) {
        .integer => |left_integer| switch (right) {
            .integer => |right_integer| .{ .integer = switch (operator) {
                .add => left_integer + right_integer,
                .subtract => left_integer - right_integer,
            } },
            .float => |right_float| .{ .float = switch (operator) {
                .add => @as(f64, @floatFromInt(left_integer)) + right_float,
                .subtract => @as(f64, @floatFromInt(left_integer)) - right_float,
            } },
            else => error.TypeMismatch,
        },
        .float => |left_float| switch (right) {
            .integer => |right_integer| .{ .float = switch (operator) {
                .add => left_float + @as(f64, @floatFromInt(right_integer)),
                .subtract => left_float - @as(f64, @floatFromInt(right_integer)),
            } },
            .float => |right_float| .{ .float = switch (operator) {
                .add => left_float + right_float,
                .subtract => left_float - right_float,
            } },
            else => error.TypeMismatch,
        },
        else => error.TypeMismatch,
    };
}

fn projectionItems(allocator: std.mem.Allocator, statement: ast.SelectStatement) ![]ProjectionItem {
    if (statement.projection_items.len > 0) {
        var items = try allocator.alloc(ProjectionItem, statement.projection_items.len);
        for (statement.projection_items, 0..) |projection, index| {
            items[index] = .{ .expression = projection.expression, .alias = projection.alias };
        }
        return items;
    }

    var items = try allocator.alloc(ProjectionItem, statement.projections.len);
    for (statement.projections, 0..) |projection, index| {
        items[index] = .{ .expression = projection };
    }
    return items;
}

fn projectionName(projection: ProjectionItem) []const u8 {
    if (projection.alias) |alias| return alias;
    return switch (projection.expression) {
        .identifier => |identifier| ast.identifierParts(identifier).name,
        .function_call => |call| call.name,
        .literal => "literal",
        .binary => "expression",
        .star => "*",
    };
}

fn isStarProjection(projections: []const ProjectionItem) bool {
    return projections.len == 1 and projections[0].expression == .star;
}

fn concatColumns(
    allocator: std.mem.Allocator,
    left: []const ColumnBinding,
    right: []const ColumnBinding,
) ![]ColumnBinding {
    var columns = try allocator.alloc(ColumnBinding, left.len + right.len);
    errdefer allocator.free(columns);
    var count: usize = 0;
    errdefer {
        for (columns[0..count]) |*column| column.deinit(allocator);
    }

    for (left, 0..) |column, index| {
        columns[index] = try ColumnBinding.clone(allocator, column);
        count += 1;
    }
    for (right, 0..) |column, index| {
        columns[left.len + index] = try ColumnBinding.clone(allocator, column);
        count += 1;
    }
    return columns;
}

fn concatRows(allocator: std.mem.Allocator, left: Row, right: Row) !Row {
    var values = try allocator.alloc(value.Value, left.values.len + right.values.len);
    errdefer allocator.free(values);
    var count: usize = 0;
    errdefer deinitValues(allocator, values[0..count]);

    for (left.values, 0..) |runtime_value, index| {
        values[index] = try runtime_value.clone(allocator);
        count += 1;
    }
    for (right.values, 0..) |runtime_value, index| {
        values[left.values.len + index] = try runtime_value.clone(allocator);
        count += 1;
    }
    return .{ .values = values };
}

fn concatRowWithNulls(allocator: std.mem.Allocator, left: Row, null_count: usize) !Row {
    var values = try allocator.alloc(value.Value, left.values.len + null_count);
    errdefer allocator.free(values);
    var count: usize = 0;
    errdefer deinitValues(allocator, values[0..count]);

    for (left.values, 0..) |runtime_value, index| {
        values[index] = try runtime_value.clone(allocator);
        count += 1;
    }
    for (values[left.values.len..]) |*runtime_value| {
        runtime_value.* = .null;
        count += 1;
    }
    return .{ .values = values };
}

fn valueFromLiteral(allocator: std.mem.Allocator, literal: ast.Literal) !value.Value {
    return switch (literal) {
        .null => .null,
        .integer => |v| .{ .integer = v },
        .float => |v| .{ .float = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| try value.Value.initText(allocator, v),
        .vector => |components| blk: {
            var vector_values = try allocator.alloc(f32, components.len);
            defer allocator.free(vector_values);
            for (components, 0..) |component, index| {
                vector_values[index] = @floatCast(component);
            }
            break :blk try value.Value.initVector(allocator, .float32, components.len, vector_values);
        },
    };
}

fn compareValues(left: value.Value, right: value.Value) !i8 {
    return switch (left) {
        .null => if (right == .null) 0 else error.TypeMismatch,
        .integer => |l| switch (right) {
            .integer => |r| compareNumbers(i128, l, r),
            .float => |r| compareFloats(@as(f64, @floatFromInt(l)), r),
            else => error.TypeMismatch,
        },
        .float => |l| switch (right) {
            .integer => |r| compareFloats(l, @floatFromInt(r)),
            .float => |r| compareFloats(l, r),
            else => error.TypeMismatch,
        },
        .boolean => |l| switch (right) {
            .boolean => |r| compareNumbers(u2, @intFromBool(l), @intFromBool(r)),
            else => error.TypeMismatch,
        },
        .text => |l| switch (right) {
            .text => |r| compareOrdering(std.mem.order(u8, l, r)),
            else => error.TypeMismatch,
        },
        .blob, .vector => error.TypeMismatch,
    };
}

fn compareNumbers(comptime T: type, left: T, right: T) i8 {
    if (left < right) return -1;
    if (left > right) return 1;
    return 0;
}

fn compareFloats(left: f64, right: f64) i8 {
    if (left < right) return -1;
    if (left > right) return 1;
    return 0;
}

fn compareOrdering(order: std.math.Order) i8 {
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn isBuiltin(actual: []const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(actual, expected);
}

fn cloneValueSlice(allocator: std.mem.Allocator, values: []const value.Value) ![]value.Value {
    var cloned = try allocator.alloc(value.Value, values.len);
    errdefer allocator.free(cloned);
    var count: usize = 0;
    errdefer deinitValues(allocator, cloned[0..count]);
    for (values, 0..) |runtime_value, index| {
        cloned[index] = try runtime_value.clone(allocator);
        count += 1;
    }
    return cloned;
}

fn deinitResultSet(allocator: std.mem.Allocator, result: *ResultSet) void {
    deinitColumns(allocator, result.columns);
    for (result.rows) |*row| {
        deinitValues(allocator, row.values);
        allocator.free(row.values);
    }
    allocator.free(result.rows);
    result.* = undefined;
}

fn deinitColumns(allocator: std.mem.Allocator, columns: [][]u8) void {
    for (columns) |column| allocator.free(column);
    allocator.free(columns);
}

fn deinitValues(allocator: std.mem.Allocator, values: []value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}
