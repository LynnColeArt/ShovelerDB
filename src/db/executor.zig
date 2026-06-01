const std = @import("std");
const ast = @import("../sql/ast.zig");
const parser = @import("../sql/parser.zig");
const catalog = @import("catalog.zig");
const procedure = @import("procedure.zig");
const row_store = @import("row_store.zig");
const transaction = @import("transaction.zig");
const value = @import("value.zig");
const view = @import("view.zig");

pub const DiagnosticKind = enum {
    parse_diagnostic,
    duplicate_object,
    unknown_object,
    name_conflict,
    unknown_column,
    column_count_mismatch,
    transaction_required,
    transaction_active,
    no_active_transaction,
    type_mismatch,
    vector_dimension_mismatch,
    invalid_vector_dimension,
    unsupported_expression,
    unsupported_view,
    unsupported_procedure,
    transaction_closed,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.ParseDiagnostic => .parse_diagnostic,
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.NameConflict => .name_conflict,
        error.UnknownColumn => .unknown_column,
        error.ColumnCountMismatch => .column_count_mismatch,
        error.TransactionRequired => .transaction_required,
        error.TransactionActive => .transaction_active,
        error.NoActiveTransaction => .no_active_transaction,
        error.TypeMismatch => .type_mismatch,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        error.UnsupportedExpression => .unsupported_expression,
        error.UnsupportedView => .unsupported_view,
        error.UnsupportedProcedure => .unsupported_procedure,
        error.AlreadyCommitted, error.AlreadyRolledBack => .transaction_closed,
        else => null,
    };
}

pub const ResultRow = struct {
    values: []value.Value,

    pub fn deinit(self: *ResultRow, allocator: std.mem.Allocator) void {
        for (self.values) |*runtime_value| runtime_value.deinit(allocator);
        allocator.free(self.values);
        self.* = undefined;
    }
};

pub const ResultSet = struct {
    columns: [][]u8,
    rows: []ResultRow,

    pub fn deinit(self: *ResultSet, allocator: std.mem.Allocator) void {
        for (self.columns) |column| allocator.free(column);
        allocator.free(self.columns);
        for (self.rows) |*row| row.deinit(allocator);
        allocator.free(self.rows);
        self.* = undefined;
    }
};

pub const ExecutionResult = union(enum) {
    ok,
    mutation_count: usize,
    result_set: ResultSet,

    pub fn deinit(self: *ExecutionResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .result_set => |*result_set| result_set.deinit(allocator),
            else => {},
        }
        self.* = .ok;
    }
};

const TableState = struct {
    name: []u8,
    store: row_store.RowStore,

    fn deinit(self: *TableState, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.store.deinit();
        self.* = undefined;
    }
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    db_catalog: catalog.DatabaseCatalog,
    views: view.ViewRegistry,
    procedures: procedure.ProcedureRegistry,
    tables: std.ArrayList(TableState) = .empty,

    pub fn init(allocator: std.mem.Allocator) Database {
        return .{
            .allocator = allocator,
            .db_catalog = catalog.DatabaseCatalog.init(allocator),
            .views = view.ViewRegistry.init(allocator),
            .procedures = procedure.ProcedureRegistry.init(allocator),
        };
    }

    pub fn deinit(self: *Database) void {
        for (self.tables.items) |*table| table.deinit(self.allocator);
        self.tables.deinit(self.allocator);
        self.procedures.deinit();
        self.views.deinit();
        self.db_catalog.deinit();
        self.* = undefined;
    }

    pub fn executeSql(self: *Database, session: *Session, sql: []const u8) anyerror!ExecutionResult {
        const parsed = try parser.parse(self.allocator, sql);
        defer parsed.deinit(self.allocator);

        return switch (parsed) {
            .diagnostic => error.ParseDiagnostic,
            .statement => |statement| try self.executeStatement(session, statement),
        };
    }

    pub fn executeStatement(self: *Database, session: *Session, statement: ast.Statement) anyerror!ExecutionResult {
        return switch (statement) {
            .begin => blk: {
                try session.begin();
                break :blk .ok;
            },
            .commit => blk: {
                try session.commit();
                self.refreshTablePointers();
                break :blk .ok;
            },
            .rollback => blk: {
                try session.rollback();
                break :blk .ok;
            },
            .create_table => |create| blk: {
                try self.createTable(create);
                break :blk .ok;
            },
            .drop_table => |drop| blk: {
                try self.dropTable(drop.name);
                break :blk .ok;
            },
            .insert => |insert| .{ .mutation_count = try self.executeInsert(session, insert) },
            .update => |update| .{ .mutation_count = try self.executeUpdate(session, update) },
            .delete => |delete| .{ .mutation_count = try self.executeDelete(session, delete) },
            .select => |select| .{ .result_set = try self.executeSelect(session, select) },
            .create_view => |create| blk: {
                try self.createView(create);
                break :blk .ok;
            },
            .drop_view => |drop| blk: {
                try self.views.drop(drop.name);
                try self.db_catalog.dropView(drop.name);
                break :blk .ok;
            },
            .create_procedure => |create| blk: {
                try self.createProcedure(create);
                break :blk .ok;
            },
            .drop_procedure => |drop| blk: {
                try self.procedures.drop(drop.name);
                try self.db_catalog.dropProcedure(drop.name);
                break :blk .ok;
            },
            .call => |call| try self.executeCall(session, call),
        };
    }

    fn createTable(self: *Database, statement: ast.CreateTableStatement) !void {
        var columns = try self.allocator.alloc(catalog.ColumnSpec, statement.columns.len);
        defer self.allocator.free(columns);

        for (statement.columns, 0..) |column, index| {
            columns[index] = .{
                .name = column.name,
                .column_type = try toCatalogColumnType(column.column_type),
                .nullable = true,
            };
        }

        try self.db_catalog.createTable(.{
            .name = statement.name,
            .columns = columns,
        });
        errdefer self.db_catalog.dropTable(statement.name) catch {};

        const table = self.db_catalog.getTable(statement.name) orelse return error.UnknownObject;
        const state = TableState{
            .name = try self.allocator.dupe(u8, statement.name),
            .store = row_store.RowStore.init(self.allocator, table),
        };
        errdefer self.allocator.free(state.name);

        try self.tables.append(self.allocator, state);
        self.refreshTablePointers();
    }

    fn dropTable(self: *Database, name: []const u8) !void {
        const index = self.findTableStateIndex(name) orelse return error.UnknownObject;
        try self.db_catalog.dropTable(name);
        var state = self.tables.orderedRemove(index);
        state.deinit(self.allocator);
        self.refreshTablePointers();
    }

    fn createView(self: *Database, statement: ast.CreateViewStatement) !void {
        try self.db_catalog.registerView(statement.name, "SELECT");
        errdefer self.db_catalog.dropView(statement.name) catch {};
        try self.views.create(statement.name, statement.query.*);
    }

    fn createProcedure(self: *Database, statement: ast.ProcedureStatement) !void {
        try self.db_catalog.registerProcedure(statement.name, statement.body_sql);
        errdefer self.db_catalog.dropProcedure(statement.name) catch {};
        try self.procedures.create(statement.name, statement.body_sql);
    }

    fn executeInsert(self: *Database, session: *Session, statement: ast.InsertStatement) !usize {
        if (!session.active) return error.TransactionRequired;
        const table_state = self.getTableState(statement.table_name) orelse return error.UnknownObject;
        const table = table_state.store.table;

        const values = try self.rowValuesForInsert(table, statement);
        defer deinitValueSlice(self.allocator, values);

        var tx = try session.transactionFor(self, table_state);
        _ = try tx.insert(values);
        return 1;
    }

    fn executeUpdate(self: *Database, session: *Session, statement: ast.UpdateStatement) !usize {
        if (!session.active) return error.TransactionRequired;
        const table_state = self.getTableState(statement.table_name) orelse return error.UnknownObject;
        const table = table_state.store.table;
        var tx = try session.transactionFor(self, table_state);

        const rows = try scanRowsForTable(self.allocator, session, table_state);
        defer row_store.deinitRows(self.allocator, rows);

        var count: usize = 0;
        for (rows) |row| {
            if (!try matchesWhere(self.allocator, table, row, statement.where_clause)) continue;
            var next_values = try cloneValueSlice(self.allocator, row.values);
            defer deinitValueSlice(self.allocator, next_values);

            for (statement.assignments) |assignment| {
                const index = table.columnIndex(assignment.column) orelse return error.UnknownColumn;
                next_values[index].deinit(self.allocator);
                next_values[index] = try evalExpression(self.allocator, table, row, assignment.value);
            }

            try tx.update(row.id, next_values);
            count += 1;
        }

        return count;
    }

    fn executeDelete(self: *Database, session: *Session, statement: ast.DeleteStatement) !usize {
        if (!session.active) return error.TransactionRequired;
        const table_state = self.getTableState(statement.table_name) orelse return error.UnknownObject;
        const table = table_state.store.table;
        var tx = try session.transactionFor(self, table_state);

        const rows = try scanRowsForTable(self.allocator, session, table_state);
        defer row_store.deinitRows(self.allocator, rows);

        var count: usize = 0;
        for (rows) |row| {
            if (!try matchesWhere(self.allocator, table, row, statement.where_clause)) continue;
            try tx.delete(row.id);
            count += 1;
        }

        return count;
    }

    fn executeSelect(self: *Database, session: *Session, statement: ast.SelectStatement) !ResultSet {
        return self.executeSelectDepth(session, statement, 0);
    }

    fn executeSelectDepth(self: *Database, session: *Session, statement: ast.SelectStatement, depth: usize) !ResultSet {
        const from = statement.from orelse return error.UnknownObject;
        if (self.views.get(from)) |stored| {
            if (depth >= 4 or !isSimpleViewDelegation(statement)) return error.UnsupportedView;
            return self.executeSelectDepth(session, stored.query, depth + 1);
        }

        const table_state = self.getTableState(from) orelse return error.UnknownObject;
        const table = table_state.store.table;
        try validateSelectExpressions(table, statement);

        const rows = try scanRowsForTable(self.allocator, session, table_state);
        defer row_store.deinitRows(self.allocator, rows);

        var indices: std.ArrayList(usize) = .empty;
        defer indices.deinit(self.allocator);
        for (rows, 0..) |row, index| {
            if (try matchesWhere(self.allocator, table, row, statement.where_clause)) {
                try indices.append(self.allocator, index);
            }
        }

        try sortIndices(self.allocator, table, rows, indices.items, statement.order_by);

        const row_limit = if (statement.limit) |limit| @min(limit, indices.items.len) else indices.items.len;
        var result = ResultSet{
            .columns = try resultColumns(self.allocator, table, statement.projections),
            .rows = try self.allocator.alloc(ResultRow, row_limit),
        };
        errdefer result.deinit(self.allocator);

        var built_rows: usize = 0;
        errdefer {
            for (result.rows[0..built_rows]) |*row| row.deinit(self.allocator);
        }

        for (indices.items[0..row_limit], 0..) |row_index, out_index| {
            result.rows[out_index] = .{
                .values = try projectRow(self.allocator, table, rows[row_index], statement.projections),
            };
            built_rows += 1;
        }

        return result;
    }

    fn executeCall(self: *Database, session: *Session, call: ast.CallStatement) anyerror!ExecutionResult {
        if (call.args.len != 0) return error.UnsupportedProcedure;
        const stored = self.procedures.get(call.name) orelse return error.UnknownObject;

        const parsed = try parser.parse(self.allocator, stored.body_sql);
        defer parsed.deinit(self.allocator);

        return switch (parsed) {
            .diagnostic => error.UnsupportedProcedure,
            .statement => |statement| switch (statement) {
                .call, .begin, .commit, .rollback, .create_procedure, .drop_procedure => error.UnsupportedProcedure,
                else => try self.executeStatement(session, statement),
            },
        };
    }

    fn rowValuesForInsert(self: *Database, table: *const catalog.TableDef, statement: ast.InsertStatement) ![]value.Value {
        var initialized = try self.allocator.alloc(bool, table.columns.len);
        defer self.allocator.free(initialized);
        @memset(initialized, false);

        var values = try self.allocator.alloc(value.Value, table.columns.len);
        for (values) |*runtime_value| runtime_value.* = .null;
        errdefer deinitInitializedValues(self.allocator, values, initialized);

        if (statement.columns.len == 0) {
            if (statement.values.len != table.columns.len) return error.ColumnCountMismatch;
            for (statement.values, 0..) |expression, index| {
                values[index] = try evalConstant(self.allocator, expression);
                initialized[index] = true;
            }
        } else {
            if (statement.values.len != statement.columns.len) return error.ColumnCountMismatch;
            for (statement.columns, statement.values) |column_name, expression| {
                const index = table.columnIndex(column_name) orelse return error.UnknownColumn;
                if (initialized[index]) return error.UnknownColumn;
                values[index] = try evalConstant(self.allocator, expression);
                initialized[index] = true;
            }
        }

        for (table.columns, 0..) |column, index| {
            if (!initialized[index]) {
                if (column.default_value) |default| {
                    values[index] = try default.clone(self.allocator);
                } else {
                    values[index] = .null;
                }
                initialized[index] = true;
            }
            try column.validateValue(values[index]);
        }

        return values;
    }

    fn getTableState(self: *Database, name: []const u8) ?*TableState {
        const index = self.findTableStateIndex(name) orelse return null;
        return &self.tables.items[index];
    }

    fn findTableStateIndex(self: *const Database, name: []const u8) ?usize {
        for (self.tables.items, 0..) |table, index| {
            if (std.ascii.eqlIgnoreCase(table.name, name)) return index;
        }
        return null;
    }

    fn refreshTablePointers(self: *Database) void {
        for (self.tables.items) |*table| {
            table.store.table = self.db_catalog.getTable(table.name).?;
        }
    }
};

const TableTransaction = struct {
    table_name: []u8,
    tx: transaction.Transaction,

    fn deinit(self: *TableTransaction, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        self.tx.deinit();
        self.* = undefined;
    }
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    active: bool = false,
    transactions: std.ArrayList(TableTransaction) = .empty,

    pub fn init(allocator: std.mem.Allocator) Session {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Session) void {
        for (self.transactions.items) |*entry| entry.deinit(self.allocator);
        self.transactions.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn begin(self: *Session) !void {
        if (self.active) return error.TransactionActive;
        self.active = true;
    }

    pub fn commit(self: *Session) !void {
        if (!self.active) return error.NoActiveTransaction;
        for (self.transactions.items) |*entry| {
            try entry.tx.commit();
        }
        self.clearTransactions();
        self.active = false;
    }

    pub fn rollback(self: *Session) !void {
        if (!self.active) return error.NoActiveTransaction;
        for (self.transactions.items) |*entry| {
            try entry.tx.rollback();
        }
        self.clearTransactions();
        self.active = false;
    }

    fn transactionFor(self: *Session, db: *Database, table: *TableState) !*transaction.Transaction {
        _ = db;
        if (self.findTransactionIndex(table.name)) |index| return &self.transactions.items[index].tx;

        const entry = TableTransaction{
            .table_name = try self.allocator.dupe(u8, table.name),
            .tx = transaction.Transaction.begin(self.allocator, &table.store),
        };
        errdefer self.allocator.free(entry.table_name);

        try self.transactions.append(self.allocator, entry);
        return &self.transactions.items[self.transactions.items.len - 1].tx;
    }

    fn transactionForRead(self: *const Session, table_name: []const u8) ?*const transaction.Transaction {
        const index = self.findTransactionIndex(table_name) orelse return null;
        return &self.transactions.items[index].tx;
    }

    fn findTransactionIndex(self: *const Session, table_name: []const u8) ?usize {
        for (self.transactions.items, 0..) |entry, index| {
            if (std.ascii.eqlIgnoreCase(entry.table_name, table_name)) return index;
        }
        return null;
    }

    fn clearTransactions(self: *Session) void {
        for (self.transactions.items) |*entry| entry.deinit(self.allocator);
        self.transactions.clearRetainingCapacity();
    }
};

fn toCatalogColumnType(column_type: ast.ColumnType) !catalog.ColumnType {
    return switch (column_type) {
        .integer => .integer,
        .float => .float,
        .boolean => .boolean,
        .text => .text,
        .blob => .blob,
        .vector => |dimension| .{ .vector = .{ .dimension = dimension } },
    };
}

fn scanRowsForTable(allocator: std.mem.Allocator, session: *const Session, table: *TableState) ![]row_store.Row {
    if (session.transactionForRead(table.name)) |tx| return tx.scan();

    var rows = try allocator.alloc(row_store.Row, table.store.rows().len);
    errdefer allocator.free(rows);

    var count: usize = 0;
    errdefer {
        for (rows[0..count]) |*row| row.deinit(allocator);
    }

    for (table.store.rows(), 0..) |row, index| {
        rows[index] = try row.clone(allocator, table.store.table);
        count += 1;
    }

    return rows;
}

fn matchesWhere(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    row: row_store.Row,
    where_clause: ?ast.Expression,
) !bool {
    const clause = where_clause orelse return true;
    var result = try evalExpression(allocator, table, row, clause);
    defer result.deinit(allocator);
    if (result != .boolean) return error.TypeMismatch;
    return result.boolean;
}

fn validateSelectExpressions(table: *const catalog.TableDef, statement: ast.SelectStatement) !void {
    for (statement.projections) |projection| try validateExpressionColumns(table, projection);
    if (statement.where_clause) |where_clause| try validateExpressionColumns(table, where_clause);
    for (statement.order_by) |order| try validateExpressionColumns(table, order.expression);
}

fn validateExpressionColumns(table: *const catalog.TableDef, expression: ast.Expression) !void {
    switch (expression) {
        .star, .literal => {},
        .identifier => |identifier| {
            _ = table.columnIndex(identifier) orelse return error.UnknownColumn;
        },
        .binary => |binary| {
            try validateExpressionColumns(table, binary.left.*);
            try validateExpressionColumns(table, binary.right.*);
        },
        .function_call => return error.UnsupportedExpression,
    }
}

fn sortIndices(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    rows: []const row_store.Row,
    indices: []usize,
    order_by: []const ast.OrderKey,
) !void {
    if (order_by.len == 0 or indices.len < 2) return;

    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        var j = i;
        while (j > 0 and try rowComesAfter(allocator, table, rows[indices[j - 1]], rows[indices[j]], order_by)) : (j -= 1) {
            std.mem.swap(usize, &indices[j - 1], &indices[j]);
        }
    }
}

fn rowComesAfter(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    left: row_store.Row,
    right: row_store.Row,
    order_by: []const ast.OrderKey,
) !bool {
    for (order_by) |order| {
        var left_value = try evalExpression(allocator, table, left, order.expression);
        defer left_value.deinit(allocator);
        var right_value = try evalExpression(allocator, table, right, order.expression);
        defer right_value.deinit(allocator);

        const comparison = try compareValues(left_value, right_value);
        if (comparison == 0) continue;
        return if (order.direction == .asc) comparison > 0 else comparison < 0;
    }
    return false;
}

fn resultColumns(allocator: std.mem.Allocator, table: *const catalog.TableDef, projections: []const ast.Expression) ![][]u8 {
    if (isStarProjection(projections)) {
        var columns = try allocator.alloc([]u8, table.columns.len);
        errdefer allocator.free(columns);

        var count: usize = 0;
        errdefer {
            for (columns[0..count]) |column| allocator.free(column);
        }
        for (table.columns, 0..) |column, index| {
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

fn projectRow(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    row: row_store.Row,
    projections: []const ast.Expression,
) ![]value.Value {
    if (isStarProjection(projections)) return cloneValueSlice(allocator, row.values);

    var values = try allocator.alloc(value.Value, projections.len);
    errdefer allocator.free(values);

    var count: usize = 0;
    errdefer deinitValues(allocator, values[0..count]);

    for (projections, 0..) |projection, index| {
        values[index] = try evalExpression(allocator, table, row, projection);
        count += 1;
    }

    return values;
}

fn evalConstant(allocator: std.mem.Allocator, expression: ast.Expression) !value.Value {
    return switch (expression) {
        .literal => |literal| try valueFromLiteral(allocator, literal),
        else => error.UnsupportedExpression,
    };
}

fn evalExpression(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    row: row_store.Row,
    expression: ast.Expression,
) anyerror!value.Value {
    return switch (expression) {
        .literal => |literal| try valueFromLiteral(allocator, literal),
        .identifier => |identifier| blk: {
            const index = table.columnIndex(identifier) orelse return error.UnknownColumn;
            break :blk try row.values[index].clone(allocator);
        },
        .binary => |binary| try evalBinary(allocator, table, row, binary),
        .function_call, .star => error.UnsupportedExpression,
    };
}

fn evalBinary(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    row: row_store.Row,
    binary: ast.BinaryExpression,
) anyerror!value.Value {
    var left = try evalExpression(allocator, table, row, binary.left.*);
    defer left.deinit(allocator);
    var right = try evalExpression(allocator, table, row, binary.right.*);
    defer right.deinit(allocator);

    if (binary.operator == .and_op) {
        if (left != .boolean or right != .boolean) return error.TypeMismatch;
        return .{ .boolean = left.boolean and right.boolean };
    }

    const comparison = try compareValues(left, right);
    return .{ .boolean = switch (binary.operator) {
        .equal => comparison == 0,
        .not_equal => comparison != 0,
        .less_than => comparison < 0,
        .less_equal => comparison <= 0,
        .greater_than => comparison > 0,
        .greater_equal => comparison >= 0,
        .and_op => unreachable,
    } };
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

fn isSimpleViewDelegation(statement: ast.SelectStatement) bool {
    return isStarProjection(statement.projections) and
        statement.where_clause == null and
        statement.order_by.len == 0 and
        statement.limit == null;
}

fn isStarProjection(projections: []const ast.Expression) bool {
    return projections.len == 1 and projections[0] == .star;
}

fn projectionName(expression: ast.Expression) []const u8 {
    return switch (expression) {
        .identifier => |identifier| identifier,
        .function_call => |call| call.name,
        .literal => "literal",
        .binary => "expression",
        .star => "*",
    };
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

fn deinitValueSlice(allocator: std.mem.Allocator, values: []value.Value) void {
    deinitValues(allocator, values);
    allocator.free(values);
}

fn deinitValues(allocator: std.mem.Allocator, values: []value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}

fn deinitInitializedValues(allocator: std.mem.Allocator, values: []value.Value, initialized: []const bool) void {
    for (values, initialized) |*runtime_value, is_initialized| {
        if (is_initialized) runtime_value.deinit(allocator);
    }
    allocator.free(values);
}

test "executor creates table inserts and selects committed rows" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'first', [1, 0]);");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT id, body FROM memories WHERE id = 1;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqualStrings("body", result.result_set.columns[1]);
    try std.testing.expectEqualStrings("first", result.result_set.rows[0].values[1].text);
}

test "executor preserves transaction-local visibility and commit" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var writer = Session.init(allocator);
    defer writer.deinit();
    var reader = Session.init(allocator);
    defer reader.deinit();

    var result = try db.executeSql(&writer, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&writer, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&writer, "INSERT INTO memories VALUES (1, 'draft', [1, 0]);");
    result.deinit(allocator);

    result = try db.executeSql(&writer, "SELECT * FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&reader, "SELECT * FROM memories;");
    try std.testing.expectEqual(@as(usize, 0), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&writer, "COMMIT;");
    result.deinit(allocator);

    result = try db.executeSql(&reader, "SELECT * FROM memories;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
}

test "executor updates deletes orders and limits rows" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'first', [1, 0]);");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (2, 'second', [0, 1]);");
    result.deinit(allocator);
    result = try db.executeSql(&session, "UPDATE memories SET body = 'updated' WHERE id = 2;");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);
    result = try db.executeSql(&session, "DELETE FROM memories WHERE id = 1;");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT id, body FROM memories ORDER BY id DESC LIMIT 1;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("updated", result.result_set.rows[0].values[1].text);
}

test "executor registers queries and drops views" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CREATE VIEW recent AS SELECT id, body FROM memories ORDER BY id DESC LIMIT 1;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'first', [1, 0]);");
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT * FROM recent;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&session, "DROP VIEW recent;");
    result.deinit(allocator);
    try std.testing.expectError(error.UnknownObject, db.executeSql(&session, "SELECT * FROM recent;"));
}

test "executor registers and calls constrained procedures" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CREATE PROCEDURE remember() BEGIN INSERT INTO memories VALUES (1, 'from proc', [1, 0]); END;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CALL remember();");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT body FROM memories;");
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[0].text);
    result.deinit(allocator);

    result = try db.executeSql(&session, "DROP PROCEDURE remember;");
    result.deinit(allocator);
    try std.testing.expectError(error.UnknownObject, db.executeSql(&session, "CALL remember();"));
}

test "executor returns typed diagnostics for unsupported and invalid operations" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    try std.testing.expectError(error.TransactionRequired, db.executeSql(&session, "INSERT INTO missing VALUES (1);"));

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);

    try std.testing.expectError(
        error.VectorDimensionMismatch,
        db.executeSql(&session, "INSERT INTO memories VALUES (1, [1, 2, 3]);"),
    );
    try std.testing.expectError(
        error.UnknownColumn,
        db.executeSql(&session, "SELECT nope FROM memories;"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        db.executeSql(&session, "CREATE PROCEDURE bad() BEGIN IF TRUE THEN SELECT * FROM memories; END IF; END;"),
    );
    try std.testing.expectEqual(DiagnosticKind.unknown_column, diagnosticFromError(error.UnknownColumn).?);
}
