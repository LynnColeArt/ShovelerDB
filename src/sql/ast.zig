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

    pub fn deinit(self: ColumnDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
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

pub const SelectStatement = struct {
    projections: []Expression,
    from: ?[]const u8 = null,
    where_clause: ?Expression = null,
    order_by: []OrderKey = &.{},
    limit: ?usize = null,

    pub fn deinit(self: SelectStatement, allocator: std.mem.Allocator) void {
        for (self.projections) |projection| projection.deinit(allocator);
        allocator.free(self.projections);
        if (self.from) |from| allocator.free(from);
        if (self.where_clause) |where_clause| where_clause.deinit(allocator);
        for (self.order_by) |order_key| order_key.deinit(allocator);
        allocator.free(self.order_by);
    }
};

pub const CreateTableStatement = struct {
    name: []const u8,
    columns: []ColumnDef,

    pub fn deinit(self: CreateTableStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.columns) |column| column.deinit(allocator);
        allocator.free(self.columns);
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

    pub fn deinit(self: CreateViewStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.query.deinit(allocator);
        allocator.destroy(self.query);
    }
};

pub const ProcedureStatement = struct {
    name: []const u8,
    body_sql: []const u8,

    pub fn deinit(self: ProcedureStatement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
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
