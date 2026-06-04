const std = @import("std");

pub const ColumnType = union(enum) {
    integer,
    float,
    boolean,
    text,
    blob,
    vector: usize,
};

pub const ColumnDef = struct {
    name: []const u8,
    column_type: ColumnType,
    nullable: bool = true,
    default_value: ?Expression = null,
    primary_key: bool = false,
    auto_increment: bool = false,

    pub fn deinit(self: ColumnDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.default_value) |default| default.deinit(allocator);
    }
};

pub const IndexDef = struct {
    name: ?[]const u8 = null,
    columns: [][]const u8,
    primary: bool = false,

    pub fn deinit(self: IndexDef, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        for (self.columns) |column| allocator.free(column);
        allocator.free(self.columns);
    }
};

pub const Literal = union(enum) {
    null,
    integer: i64,
    float: f64,
    boolean: bool,
    string: []const u8,
    vector: []f64,

    pub fn deinit(self: Literal, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |value| allocator.free(value),
            .vector => |values| allocator.free(values),
            else => {},
        }
    }
};

pub const BinaryOperator = enum {
    add,
    subtract,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    and_op,
};

pub const Expression = union(enum) {
    star,
    identifier: []const u8,
    literal: Literal,
    function_call: FunctionCall,
    binary: BinaryExpression,

    pub fn deinit(self: Expression, allocator: std.mem.Allocator) void {
        switch (self) {
            .identifier => |name| allocator.free(name),
            .literal => |literal| literal.deinit(allocator),
            .function_call => |call| call.deinit(allocator),
            .binary => |binary| binary.deinit(allocator),
            .star => {},
        }
    }
};

pub const IdentifierParts = struct {
    qualifier: ?[]const u8 = null,
    name: []const u8,
};

pub fn identifierParts(identifier: []const u8) IdentifierParts {
    if (std.mem.indexOfScalar(u8, identifier, '.')) |dot| {
        return .{
            .qualifier = identifier[0..dot],
            .name = identifier[dot + 1 ..],
        };
    }
    return .{ .name = identifier };
}

pub const FunctionCall = struct {
    name: []const u8,
    args: []Expression,

    pub fn deinit(self: FunctionCall, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.args) |arg| arg.deinit(allocator);
        allocator.free(self.args);
    }
};

pub const BinaryExpression = struct {
    left: *Expression,
    operator: BinaryOperator,
    right: *Expression,

    pub fn deinit(self: BinaryExpression, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        allocator.destroy(self.left);
        self.right.deinit(allocator);
        allocator.destroy(self.right);
    }
};

pub const Assignment = struct {
    column: []const u8,
    value: Expression,

    pub fn deinit(self: Assignment, allocator: std.mem.Allocator) void {
        allocator.free(self.column);
        self.value.deinit(allocator);
    }
};

pub const OrderDirection = enum {
    asc,
    desc,
};

pub const OrderKey = struct {
    expression: Expression,
    direction: OrderDirection = .asc,

    pub fn deinit(self: OrderKey, allocator: std.mem.Allocator) void {
        self.expression.deinit(allocator);
    }
};

pub const Projection = struct {
    expression: Expression,
    alias: ?[]const u8 = null,

    pub fn deinit(self: Projection, allocator: std.mem.Allocator) void {
        self.expression.deinit(allocator);
        if (self.alias) |alias| allocator.free(alias);
    }
};

pub const TableSource = struct {
    name: []const u8,
    alias: ?[]const u8 = null,

    pub fn deinit(self: TableSource, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.alias) |alias| allocator.free(alias);
    }
};

pub const DerivedTableSource = struct {
    query: *SelectStatement,
    alias: []const u8,

    pub fn deinit(self: DerivedTableSource, allocator: std.mem.Allocator) void {
        self.query.deinit(allocator);
        allocator.destroy(self.query);
        allocator.free(self.alias);
    }
};

pub const JoinType = enum {
    inner,
    cross,
    left,
};

pub const JoinSource = struct {
    left: *RowSource,
    join_type: JoinType,
    right: *RowSource,
    on: ?Expression = null,

    pub fn deinit(self: JoinSource, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        allocator.destroy(self.left);
        self.right.deinit(allocator);
        allocator.destroy(self.right);
        if (self.on) |on| on.deinit(allocator);
    }
};

pub const RowSource = union(enum) {
    base_table: TableSource,
    derived_table: DerivedTableSource,
    join: JoinSource,

    pub fn deinit(self: RowSource, allocator: std.mem.Allocator) void {
        switch (self) {
            .base_table => |source| source.deinit(allocator),
            .derived_table => |source| source.deinit(allocator),
            .join => |source| source.deinit(allocator),
        }
    }
};

pub const CommonTableExpression = struct {
    name: []const u8,
    query: *SelectStatement,

    pub fn deinit(self: CommonTableExpression, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.query.deinit(allocator);
        allocator.destroy(self.query);
    }
};

pub const SelectStatement = struct {
    ctes: []CommonTableExpression = &.{},
    projection_items: []Projection = &.{},
    projections: []Expression,
    from: ?[]const u8 = null,
    source: ?*RowSource = null,
    where_clause: ?Expression = null,
    group_by: []Expression = &.{},
    having: ?Expression = null,
    order_by: []OrderKey = &.{},
    limit: ?usize = null,

    pub fn deinit(self: SelectStatement, allocator: std.mem.Allocator) void {
        for (self.ctes) |cte| cte.deinit(allocator);
        allocator.free(self.ctes);
        for (self.projection_items) |projection| projection.deinit(allocator);
        allocator.free(self.projection_items);
        for (self.projections) |projection| projection.deinit(allocator);
        allocator.free(self.projections);
        if (self.from) |from| allocator.free(from);
        if (self.source) |source| {
            source.deinit(allocator);
            allocator.destroy(source);
        }
        if (self.where_clause) |where_clause| where_clause.deinit(allocator);
        for (self.group_by) |group_key| group_key.deinit(allocator);
        allocator.free(self.group_by);
        if (self.having) |having| having.deinit(allocator);
        for (self.order_by) |order_key| order_key.deinit(allocator);
        allocator.free(self.order_by);
    }
};

pub const CreateTableStatement = struct {
    name: []const u8,
    if_not_exists: bool = false,
    columns: []ColumnDef,
    indexes: []IndexDef = &.{},

    pub fn deinit(self: CreateTableStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.columns) |column| column.deinit(allocator);
        allocator.free(self.columns);
        for (self.indexes) |index| index.deinit(allocator);
        allocator.free(self.indexes);
    }
};

pub const InsertStatement = struct {
    table_name: []const u8,
    columns: [][]const u8 = &.{},
    values: []Expression,

    pub fn deinit(self: InsertStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.columns) |column| allocator.free(column);
        allocator.free(self.columns);
        for (self.values) |value| value.deinit(allocator);
        allocator.free(self.values);
    }
};

pub const UpdateStatement = struct {
    table_name: []const u8,
    assignments: []Assignment,
    where_clause: ?Expression = null,

    pub fn deinit(self: UpdateStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        for (self.assignments) |assignment| assignment.deinit(allocator);
        allocator.free(self.assignments);
        if (self.where_clause) |where_clause| where_clause.deinit(allocator);
    }
};

pub const DeleteStatement = struct {
    table_name: []const u8,
    where_clause: ?Expression = null,

    pub fn deinit(self: DeleteStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        if (self.where_clause) |where_clause| where_clause.deinit(allocator);
    }
};

pub const CreateViewStatement = struct {
    name: []const u8,
    query: *SelectStatement,
    body_sql: []const u8,

    pub fn deinit(self: CreateViewStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.query.deinit(allocator);
        allocator.destroy(self.query);
        allocator.free(self.body_sql);
    }
};

pub const ProcedureParamMode = enum {
    in,
};

pub const ProcedureParam = struct {
    name: []const u8,
    column_type: ColumnType,
    mode: ProcedureParamMode = .in,

    pub fn deinit(self: ProcedureParam, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const ProcedureStatement = struct {
    name: []const u8,
    params: []ProcedureParam = &.{},
    body_sql: []const u8,

    pub fn deinit(self: ProcedureStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.params) |param| param.deinit(allocator);
        allocator.free(self.params);
        allocator.free(self.body_sql);
    }
};

pub const CallStatement = struct {
    name: []const u8,
    args: []Expression,

    pub fn deinit(self: CallStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.args) |arg| arg.deinit(allocator);
        allocator.free(self.args);
    }
};

pub const NamedStatement = struct {
    name: []const u8,
    if_exists: bool = false,

    pub fn deinit(self: NamedStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Statement = union(enum) {
    create_table: CreateTableStatement,
    drop_table: NamedStatement,
    insert: InsertStatement,
    select: SelectStatement,
    update: UpdateStatement,
    delete: DeleteStatement,
    begin,
    commit,
    rollback,
    create_view: CreateViewStatement,
    drop_view: NamedStatement,
    create_procedure: ProcedureStatement,
    drop_procedure: NamedStatement,
    call: CallStatement,

    pub fn deinit(self: Statement, allocator: std.mem.Allocator) void {
        switch (self) {
            .create_table => |statement| statement.deinit(allocator),
            .drop_table => |statement| statement.deinit(allocator),
            .insert => |statement| statement.deinit(allocator),
            .select => |statement| statement.deinit(allocator),
            .update => |statement| statement.deinit(allocator),
            .delete => |statement| statement.deinit(allocator),
            .create_view => |statement| statement.deinit(allocator),
            .drop_view => |statement| statement.deinit(allocator),
            .create_procedure => |statement| statement.deinit(allocator),
            .drop_procedure => |statement| statement.deinit(allocator),
            .call => |statement| statement.deinit(allocator),
            .begin, .commit, .rollback => {},
        }
    }
};

pub fn cloneIdentifier(allocator: std.mem.Allocator, identifier: []const u8) ![]const u8 {
    return allocator.dupe(u8, identifier);
}

pub fn cloneExpression(allocator: std.mem.Allocator, source: Expression) !Expression {
    return switch (source) {
        .star => .star,
        .identifier => |identifier| .{ .identifier = try allocator.dupe(u8, identifier) },
        .literal => |literal| .{ .literal = try cloneLiteral(allocator, literal) },
        .function_call => |call| blk: {
            var args = try allocator.alloc(Expression, call.args.len);
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
            const left = try allocator.create(Expression);
            errdefer allocator.destroy(left);
            left.* = try cloneExpression(allocator, binary.left.*);
            errdefer left.deinit(allocator);

            const right = try allocator.create(Expression);
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

fn cloneLiteral(allocator: std.mem.Allocator, source: Literal) !Literal {
    return switch (source) {
        .null => .null,
        .integer => |v| .{ .integer = v },
        .float => |v| .{ .float = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| .{ .string = try allocator.dupe(u8, v) },
        .vector => |v| .{ .vector = try allocator.dupe(f64, v) },
    };
}

test "statement deinit releases owned strings and vectors" {
    const allocator = std.testing.allocator;
    const columns = try allocator.alloc(ColumnDef, 2);
    columns[0] = .{
        .name = try cloneIdentifier(allocator, "id"),
        .column_type = .integer,
    };
    columns[1] = .{
        .name = try cloneIdentifier(allocator, "embedding"),
        .column_type = .{ .vector = 3 },
    };

    const statement: Statement = .{
        .create_table = .{
            .name = try cloneIdentifier(allocator, "memories"),
            .columns = columns,
        },
    };
    statement.deinit(allocator);
}

test "select statement deinit releases projection rowsources and ctes" {
    const allocator = std.testing.allocator;

    const cte_query = try allocator.create(SelectStatement);
    cte_query.* = .{
        .projections = try allocator.dupe(Expression, &.{.{ .literal = .{ .integer = 1 } }}),
    };

    const derived_query = try allocator.create(SelectStatement);
    derived_query.* = .{
        .projections = try allocator.dupe(Expression, &.{.{ .star = {} }}),
        .from = try cloneIdentifier(allocator, "memories"),
    };

    const source = try allocator.create(RowSource);
    source.* = .{
        .derived_table = .{
            .query = derived_query,
            .alias = try cloneIdentifier(allocator, "m"),
        },
    };

    const statement = SelectStatement{
        .ctes = try allocator.dupe(CommonTableExpression, &.{.{
            .name = try cloneIdentifier(allocator, "ranked"),
            .query = cte_query,
        }}),
        .projection_items = try allocator.dupe(Projection, &.{.{
            .expression = .{ .identifier = try cloneIdentifier(allocator, "m.id") },
            .alias = try cloneIdentifier(allocator, "id"),
        }}),
        .projections = try allocator.dupe(Expression, &.{.{
            .identifier = try cloneIdentifier(allocator, "m.id"),
        }}),
        .source = source,
        .group_by = try allocator.dupe(Expression, &.{.{
            .identifier = try cloneIdentifier(allocator, "m.id"),
        }}),
    };
    statement.deinit(allocator);
}

test "expression deinit releases nested function arguments" {
    const allocator = std.testing.allocator;
    const args = try allocator.alloc(Expression, 1);
    args[0] = .{ .literal = .{ .vector = try allocator.dupe(f64, &.{ 1, 2, 3 }) } };

    const expression: Expression = .{
        .function_call = .{
            .name = try cloneIdentifier(allocator, "l2_distance"),
            .args = args,
        },
    };
    expression.deinit(allocator);
}

test "insert statement deinit releases optional column names" {
    const allocator = std.testing.allocator;
    const columns = try allocator.alloc([]const u8, 2);
    columns[0] = try cloneIdentifier(allocator, "id");
    columns[1] = try cloneIdentifier(allocator, "embedding");
    const values = try allocator.alloc(Expression, 1);
    values[0] = .{ .literal = .{ .integer = 1 } };

    const statement: Statement = .{
        .insert = .{
            .table_name = try cloneIdentifier(allocator, "memories"),
            .columns = columns,
            .values = values,
        },
    };
    statement.deinit(allocator);
}
