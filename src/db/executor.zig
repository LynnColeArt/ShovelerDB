const std = @import("std");
const ast = @import("../sql/ast.zig");
const parser = @import("../sql/parser.zig");
const procedure_body = @import("../sql/procedure_body.zig");
const catalog = @import("catalog.zig");
const concurrency = @import("concurrency.zig");
const procedure = @import("procedure.zig");
const query_source = @import("query_source.zig");
const row_store = @import("row_store.zig");
const snapshot = @import("snapshot.zig");
const transaction = @import("transaction.zig");
const value = @import("value.zig");
const view = @import("view.zig");
const vector_distance = @import("../vector/distance.zig");

const max_procedure_loop_iterations = 10_000;
const ProcedureMaterializeError = error{
    OutOfMemory,
    UnsupportedProcedure,
};

pub const DiagnosticKind = enum {
    parse_diagnostic,
    duplicate_object,
    unknown_object,
    name_conflict,
    unknown_column,
    ambiguous_column,
    column_count_mismatch,
    transaction_required,
    transaction_active,
    no_active_transaction,
    type_mismatch,
    invalid_grouping,
    vector_dimension_mismatch,
    invalid_vector_dimension,
    unsupported_expression,
    unsupported_view,
    unsupported_procedure,
    transaction_closed,
    zero_vector,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.ParseDiagnostic => .parse_diagnostic,
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.NameConflict => .name_conflict,
        error.UnknownColumn => .unknown_column,
        error.AmbiguousColumn => .ambiguous_column,
        error.ColumnCountMismatch => .column_count_mismatch,
        error.TransactionRequired => .transaction_required,
        error.TransactionActive => .transaction_active,
        error.NoActiveTransaction => .no_active_transaction,
        error.TypeMismatch => .type_mismatch,
        error.InvalidGrouping => .invalid_grouping,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        error.UnsupportedExpression => .unsupported_expression,
        error.UnsupportedView => .unsupported_view,
        error.UnsupportedProcedure => .unsupported_procedure,
        error.AlreadyCommitted, error.AlreadyRolledBack => .transaction_closed,
        error.ZeroVector => .zero_vector,
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
    commit_sequence: concurrency.CommitSequence = 0,
    commit_lock: std.atomic.Mutex = .unlocked,
    snapshot_registry: snapshot.Registry,

    pub fn init(allocator: std.mem.Allocator) Database {
        return .{
            .allocator = allocator,
            .db_catalog = catalog.DatabaseCatalog.init(allocator),
            .views = view.ViewRegistry.init(allocator),
            .procedures = procedure.ProcedureRegistry.init(allocator),
            .snapshot_registry = snapshot.Registry.init(allocator, concurrency.default_config),
        };
    }

    pub fn deinit(self: *Database) void {
        self.snapshot_registry.deinit();
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
                try session.begin(self);
                break :blk .ok;
            },
            .commit => blk: {
                try session.commit(self);
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
                try self.dropTable(drop);
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
        if (statement.if_not_exists and self.getTableState(statement.name) != null) return;

        var columns = try self.allocator.alloc(catalog.ColumnSpec, statement.columns.len);
        var initialized_columns: usize = 0;
        defer {
            deinitColumnSpecDefaults(self.allocator, columns[0..initialized_columns]);
            self.allocator.free(columns);
        }

        for (statement.columns, 0..) |column, index| {
            columns[index] = .{
                .name = column.name,
                .column_type = try toCatalogColumnType(column.column_type),
                .nullable = column.nullable,
                .default_value = if (column.default_value) |default| try evalConstant(self.allocator, default) else null,
                .primary_key = column.primary_key,
                .auto_increment = column.auto_increment,
            };
            initialized_columns += 1;
        }

        const primary_column_count = countPrimaryColumns(statement.columns);
        const index_count = statement.indexes.len + if (primary_column_count > 0) @as(usize, 1) else 0;
        var indexes = try self.allocator.alloc(catalog.IndexSpec, index_count);
        defer self.allocator.free(indexes);

        var primary_columns: ?[][]const u8 = null;
        defer if (primary_columns) |owned| self.allocator.free(owned);

        var index_offset: usize = 0;
        if (primary_column_count > 0) {
            var primary = try self.allocator.alloc([]const u8, primary_column_count);
            primary_columns = primary;

            var count: usize = 0;
            for (statement.columns) |column| {
                if (!column.primary_key) continue;
                primary[count] = column.name;
                count += 1;
            }

            indexes[0] = .{
                .name = null,
                .columns = primary,
                .kind = .primary,
            };
            index_offset = 1;
        }

        for (statement.indexes, 0..) |index, offset| {
            indexes[index_offset + offset] = .{
                .name = index.name,
                .columns = index.columns,
                .kind = if (index.primary) .primary else .secondary,
            };
        }

        try self.db_catalog.createTable(.{
            .name = statement.name,
            .columns = columns,
            .indexes = indexes,
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

    fn dropTable(self: *Database, statement: ast.NamedStatement) !void {
        const index = self.findTableStateIndex(statement.name) orelse {
            if (statement.if_exists) return;
            return error.UnknownObject;
        };
        try self.db_catalog.dropTable(statement.name);
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
        try self.procedures.create(statement.name, statement.params, statement.body_sql);
    }

    fn executeInsert(self: *Database, session: *Session, statement: ast.InsertStatement) !usize {
        if (!session.active) return error.TransactionRequired;
        const table_state = self.getTableState(statement.table_name) orelse return error.UnknownObject;
        const table = table_state.store.table;

        var tx = try session.transactionFor(self, table_state);
        const values = try self.rowValuesForInsert(table, statement, tx.next_id);
        defer deinitValueSlice(self.allocator, values);

        _ = try tx.insert(values);
        return 1;
    }

    fn executeUpdate(self: *Database, session: *Session, statement: ast.UpdateStatement) !usize {
        if (!session.active) return error.TransactionRequired;
        const table_state = self.getTableState(statement.table_name) orelse return error.UnknownObject;
        const table = table_state.store.table;
        var tx = try session.transactionFor(self, table_state);

        const rows = try scanRowsForTable(self.allocator, self, session, table_state);
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

        const rows = try scanRowsForTable(self.allocator, self, session, table_state);
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
        var bridge = QuerySourceBridge{ .db = self, .session = session };
        const result = try query_source.executeSelect(.{
            .allocator = self.allocator,
            .user_data = &bridge,
            .load_base_table = loadBaseTableForQuerySource,
            .find_view = findViewForQuerySource,
        }, statement);
        errdefer {
            deinitColumns(self.allocator, result.columns);
            for (result.rows) |*row| {
                deinitValues(self.allocator, row.values);
                self.allocator.free(row.values);
            }
            self.allocator.free(result.rows);
        }

        const rows = try self.allocator.alloc(ResultRow, result.rows.len);
        errdefer self.allocator.free(rows);
        for (result.rows, 0..) |row, index| {
            rows[index] = .{ .values = row.values };
        }
        self.allocator.free(result.rows);

        return .{
            .columns = result.columns,
            .rows = rows,
        };
    }

    fn executeCall(self: *Database, session: *Session, call: ast.CallStatement) anyerror!ExecutionResult {
        const stored = self.procedures.get(call.name) orelse return error.UnknownObject;
        if (call.args.len != stored.params.len) return error.ColumnCountMismatch;

        var env = ProcedureEnv.init(self.allocator);
        defer env.deinit();

        for (stored.params, call.args) |param, arg| {
            var runtime_value = try evalProcedureExpression(self.allocator, &env, arg);
            errdefer runtime_value.deinit(self.allocator);
            const column_type = try toCatalogColumnType(param.column_type);
            if (runtime_value != .null) try column_type.acceptsValue(runtime_value);
            try env.declare(param.name, runtime_value);
            runtime_value = .null;
        }

        return .{ .mutation_count = try self.executeProcedureBody(session, stored.body, &env) };
    }

    fn executeProcedureBody(
        self: *Database,
        session: *Session,
        body: procedure_body.Body,
        env: *ProcedureEnv,
    ) anyerror!usize {
        var mutations: usize = 0;
        for (body.statements) |statement| {
            mutations += try self.executeProcedureStatement(session, statement, env);
        }
        return mutations;
    }

    fn executeProcedureStatement(
        self: *Database,
        session: *Session,
        statement: procedure_body.Statement,
        env: *ProcedureEnv,
    ) anyerror!usize {
        switch (statement) {
            .declare_var => |declare| {
                var runtime_value = if (declare.default_value) |default|
                    try evalProcedureExpression(self.allocator, env, default)
                else
                    .null;
                errdefer runtime_value.deinit(self.allocator);
                try env.declare(declare.name, runtime_value);
                runtime_value = .null;
                return 0;
            },
            .set_var => |set| {
                var runtime_value = try evalProcedureExpression(self.allocator, env, set.value);
                errdefer runtime_value.deinit(self.allocator);
                try env.set(set.name, runtime_value);
                runtime_value = .null;
                return 0;
            },
            .sql => |sql| {
                var materialized = try materializeProcedureStatement(self.allocator, sql.statement, env);
                defer materialized.deinit(self.allocator);

                var result = try self.executeStatement(session, materialized);
                defer result.deinit(self.allocator);

                return switch (result) {
                    .ok => 0,
                    .mutation_count => |count| count,
                    .result_set => 0,
                };
            },
            .if_statement => |branch| {
                var condition = try evalProcedureExpression(self.allocator, env, branch.condition);
                defer condition.deinit(self.allocator);
                if (condition != .boolean) return error.TypeMismatch;
                return if (condition.boolean)
                    try self.executeProcedureBody(session, branch.then_body, env)
                else
                    try self.executeProcedureBody(session, branch.else_body, env);
            },
            .while_statement => |loop| {
                var mutations: usize = 0;
                var iterations: usize = 0;
                while (true) {
                    var condition = try evalProcedureExpression(self.allocator, env, loop.condition);
                    defer condition.deinit(self.allocator);
                    if (condition != .boolean) return error.TypeMismatch;
                    if (!condition.boolean) break;
                    if (iterations >= max_procedure_loop_iterations) return error.UnsupportedProcedure;
                    mutations += try self.executeProcedureBody(session, loop.body, env);
                    iterations += 1;
                }
                return mutations;
            },
        }
    }

    fn rowValuesForInsert(
        self: *Database,
        table: *const catalog.TableDef,
        statement: ast.InsertStatement,
        next_row_id: row_store.RowId,
    ) ![]value.Value {
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
                if (column.auto_increment) {
                    values[index] = .{ .integer = @as(i64, @intCast(next_row_id)) };
                } else if (column.default_value) |default| {
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

    pub fn currentCommitSequence(self: *const Database) concurrency.CommitSequence {
        return self.commit_sequence;
    }

    pub fn activeSnapshotHandleCount(
        self: *const Database,
        generation: concurrency.SnapshotGeneration,
    ) usize {
        return self.snapshot_registry.activeRefCount(generation);
    }

    pub fn retainedSnapshotGenerationCount(self: *const Database) usize {
        return self.snapshot_registry.retainedGenerationCount();
    }

    pub fn retainedSnapshotRowCount(
        self: *const Database,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
    ) ?usize {
        return self.snapshot_registry.retainedRowCount(generation, table_name);
    }

    fn retainCurrentGenerationForActiveSnapshots(
        self: *Database,
        excluding: ?snapshot.SnapshotHandle,
    ) !void {
        const generation = self.currentCommitSequence();
        if (!self.snapshot_registry.needsRetention(generation, excluding)) return;

        const sources = try self.allocator.alloc(snapshot.TableSource, self.tables.items.len);
        defer self.allocator.free(sources);

        for (self.tables.items, 0..) |*table, index| {
            sources[index] = .{
                .table = table.store.table,
                .store = &table.store,
            };
        }

        try self.snapshot_registry.retainGeneration(generation, sources);
    }

    fn lockCommits(self: *Database) void {
        while (!self.commit_lock.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlockCommits(self: *Database) void {
        self.commit_lock.unlock();
    }
};

const ProcedureVariable = struct {
    name: []u8,
    runtime_value: value.Value,

    fn deinit(self: *ProcedureVariable, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.runtime_value.deinit(allocator);
        self.* = undefined;
    }
};

const ProcedureEnv = struct {
    allocator: std.mem.Allocator,
    variables: std.ArrayList(ProcedureVariable) = .empty,

    fn init(allocator: std.mem.Allocator) ProcedureEnv {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ProcedureEnv) void {
        for (self.variables.items) |*variable| variable.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.* = undefined;
    }

    fn declare(self: *ProcedureEnv, name: []const u8, runtime_value: value.Value) !void {
        if (self.findIndex(name) != null) return error.DuplicateObject;
        const variable = ProcedureVariable{
            .name = try self.allocator.dupe(u8, name),
            .runtime_value = runtime_value,
        };
        errdefer self.allocator.free(variable.name);
        try self.variables.append(self.allocator, variable);
    }

    fn set(self: *ProcedureEnv, name: []const u8, runtime_value: value.Value) !void {
        const index = self.findIndex(name) orelse return error.UnknownObject;
        self.variables.items[index].runtime_value.deinit(self.allocator);
        self.variables.items[index].runtime_value = runtime_value;
    }

    fn get(self: *const ProcedureEnv, name: []const u8) ?value.Value {
        const index = self.findIndex(name) orelse return null;
        return self.variables.items[index].runtime_value;
    }

    fn findIndex(self: *const ProcedureEnv, name: []const u8) ?usize {
        for (self.variables.items, 0..) |variable, index| {
            if (std.ascii.eqlIgnoreCase(variable.name, name)) return index;
        }
        return null;
    }
};

fn materializeProcedureStatement(
    allocator: std.mem.Allocator,
    statement: ast.Statement,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.Statement {
    return switch (statement) {
        .insert => |insert| .{ .insert = try materializeInsertStatement(allocator, insert, env) },
        .update => |update| .{ .update = try materializeUpdateStatement(allocator, update, env) },
        .delete => |delete| .{ .delete = try materializeDeleteStatement(allocator, delete, env) },
        .select => |select| .{ .select = try materializeSelectStatement(allocator, select, env) },
        else => error.UnsupportedProcedure,
    };
}

fn materializeInsertStatement(
    allocator: std.mem.Allocator,
    statement: ast.InsertStatement,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.InsertStatement {
    const table_name = try allocator.dupe(u8, statement.table_name);
    errdefer allocator.free(table_name);

    var columns = try allocator.alloc([]const u8, statement.columns.len);
    errdefer allocator.free(columns);
    var column_count: usize = 0;
    errdefer {
        for (columns[0..column_count]) |column| allocator.free(column);
    }
    for (statement.columns, 0..) |column, index| {
        columns[index] = try allocator.dupe(u8, column);
        column_count += 1;
    }

    var values = try allocator.alloc(ast.Expression, statement.values.len);
    errdefer allocator.free(values);
    var value_count: usize = 0;
    errdefer {
        for (values[0..value_count]) |expression| expression.deinit(allocator);
    }
    for (statement.values, 0..) |expression, index| {
        values[index] = try materializeProcedureExpression(allocator, expression, env);
        value_count += 1;
    }

    return .{
        .table_name = table_name,
        .columns = columns,
        .values = values,
    };
}

fn materializeUpdateStatement(
    allocator: std.mem.Allocator,
    statement: ast.UpdateStatement,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.UpdateStatement {
    const table_name = try allocator.dupe(u8, statement.table_name);
    errdefer allocator.free(table_name);

    var assignments = try allocator.alloc(ast.Assignment, statement.assignments.len);
    errdefer allocator.free(assignments);
    var assignment_count: usize = 0;
    errdefer {
        for (assignments[0..assignment_count]) |assignment| assignment.deinit(allocator);
    }
    for (statement.assignments, 0..) |assignment, index| {
        var column: ?[]const u8 = try allocator.dupe(u8, assignment.column);
        errdefer if (column) |owned| allocator.free(owned);
        var expression: ?ast.Expression = try materializeProcedureExpression(allocator, assignment.value, env);
        errdefer if (expression) |owned| owned.deinit(allocator);

        assignments[index] = .{
            .column = column.?,
            .value = expression.?,
        };
        column = null;
        expression = null;
        assignment_count += 1;
    }

    var where_clause: ?ast.Expression = null;
    errdefer if (where_clause) |where| where.deinit(allocator);
    if (statement.where_clause) |where| {
        where_clause = try materializeProcedureExpression(allocator, where, env);
    }

    return .{
        .table_name = table_name,
        .assignments = assignments,
        .where_clause = where_clause,
    };
}

fn materializeDeleteStatement(
    allocator: std.mem.Allocator,
    statement: ast.DeleteStatement,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.DeleteStatement {
    const table_name = try allocator.dupe(u8, statement.table_name);
    errdefer allocator.free(table_name);

    var where_clause: ?ast.Expression = null;
    errdefer if (where_clause) |where| where.deinit(allocator);
    if (statement.where_clause) |where| {
        where_clause = try materializeProcedureExpression(allocator, where, env);
    }

    return .{
        .table_name = table_name,
        .where_clause = where_clause,
    };
}

fn materializeSelectStatement(
    allocator: std.mem.Allocator,
    statement: ast.SelectStatement,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.SelectStatement {
    var materialized = ast.SelectStatement{
        .projections = &.{},
    };
    errdefer materialized.deinit(allocator);

    materialized.ctes = try materializeCtes(allocator, statement.ctes, env);
    materialized.projection_items = try materializeProjectionItems(allocator, statement.projection_items, env);
    materialized.projections = try materializeExpressions(allocator, statement.projections, env);

    if (statement.from) |from| {
        materialized.from = try allocator.dupe(u8, from);
    }
    if (statement.source) |source| {
        var row_source: ?*ast.RowSource = try allocator.create(ast.RowSource);
        errdefer if (row_source) |owned| allocator.destroy(owned);
        row_source.?.* = try materializeRowSource(allocator, source.*, env);
        errdefer if (row_source) |owned| owned.deinit(allocator);
        materialized.source = row_source.?;
        row_source = null;
    }
    if (statement.where_clause) |where_clause| {
        materialized.where_clause = try materializeProcedureExpression(allocator, where_clause, env);
    }
    materialized.group_by = try materializeExpressions(allocator, statement.group_by, env);
    if (statement.having) |having| {
        materialized.having = try materializeProcedureExpression(allocator, having, env);
    }
    materialized.order_by = try materializeOrderKeys(allocator, statement.order_by, env);
    materialized.limit = statement.limit;

    return materialized;
}

fn materializeCtes(
    allocator: std.mem.Allocator,
    ctes: []const ast.CommonTableExpression,
    env: *const ProcedureEnv,
) ProcedureMaterializeError![]ast.CommonTableExpression {
    var materialized = try allocator.alloc(ast.CommonTableExpression, ctes.len);
    errdefer allocator.free(materialized);

    var count: usize = 0;
    errdefer {
        for (materialized[0..count]) |cte| cte.deinit(allocator);
    }
    for (ctes, 0..) |cte, index| {
        var name: ?[]const u8 = try allocator.dupe(u8, cte.name);
        errdefer if (name) |owned| allocator.free(owned);

        var query: ?*ast.SelectStatement = try allocator.create(ast.SelectStatement);
        errdefer if (query) |owned| allocator.destroy(owned);
        query.?.* = try materializeSelectStatement(allocator, cte.query.*, env);
        errdefer if (query) |owned| owned.deinit(allocator);

        materialized[index] = .{
            .name = name.?,
            .query = query.?,
        };
        name = null;
        query = null;
        count += 1;
    }

    return materialized;
}

fn materializeProjectionItems(
    allocator: std.mem.Allocator,
    projections: []const ast.Projection,
    env: *const ProcedureEnv,
) ProcedureMaterializeError![]ast.Projection {
    var materialized = try allocator.alloc(ast.Projection, projections.len);
    errdefer allocator.free(materialized);

    var count: usize = 0;
    errdefer {
        for (materialized[0..count]) |projection| projection.deinit(allocator);
    }
    for (projections, 0..) |projection, index| {
        var expression: ?ast.Expression = try materializeProcedureExpression(allocator, projection.expression, env);
        errdefer if (expression) |owned| owned.deinit(allocator);

        var alias: ?[]const u8 = null;
        errdefer if (alias) |owned| allocator.free(owned);
        if (projection.alias) |projection_alias| {
            alias = try allocator.dupe(u8, projection_alias);
        }

        materialized[index] = .{
            .expression = expression.?,
            .alias = alias,
        };
        expression = null;
        alias = null;
        count += 1;
    }

    return materialized;
}

fn materializeExpressions(
    allocator: std.mem.Allocator,
    expressions: []const ast.Expression,
    env: *const ProcedureEnv,
) ProcedureMaterializeError![]ast.Expression {
    var materialized = try allocator.alloc(ast.Expression, expressions.len);
    errdefer allocator.free(materialized);

    var count: usize = 0;
    errdefer {
        for (materialized[0..count]) |expression| expression.deinit(allocator);
    }
    for (expressions, 0..) |expression, index| {
        materialized[index] = try materializeProcedureExpression(allocator, expression, env);
        count += 1;
    }

    return materialized;
}

fn materializeOrderKeys(
    allocator: std.mem.Allocator,
    order_by: []const ast.OrderKey,
    env: *const ProcedureEnv,
) ProcedureMaterializeError![]ast.OrderKey {
    var materialized = try allocator.alloc(ast.OrderKey, order_by.len);
    errdefer allocator.free(materialized);

    var count: usize = 0;
    errdefer {
        for (materialized[0..count]) |key| key.deinit(allocator);
    }
    for (order_by, 0..) |key, index| {
        materialized[index] = .{
            .expression = try materializeProcedureExpression(allocator, key.expression, env),
            .direction = key.direction,
        };
        count += 1;
    }

    return materialized;
}

fn materializeRowSource(
    allocator: std.mem.Allocator,
    source: ast.RowSource,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.RowSource {
    return switch (source) {
        .base_table => |table| blk: {
            const name = try allocator.dupe(u8, table.name);
            errdefer allocator.free(name);

            var alias: ?[]const u8 = null;
            errdefer if (alias) |owned| allocator.free(owned);
            if (table.alias) |table_alias| {
                alias = try allocator.dupe(u8, table_alias);
            }

            break :blk .{ .base_table = .{
                .name = name,
                .alias = alias,
            } };
        },
        .derived_table => |derived| blk: {
            const query = try allocator.create(ast.SelectStatement);
            errdefer allocator.destroy(query);
            query.* = try materializeSelectStatement(allocator, derived.query.*, env);
            errdefer query.deinit(allocator);

            break :blk .{ .derived_table = .{
                .query = query,
                .alias = try allocator.dupe(u8, derived.alias),
            } };
        },
        .join => |join| blk: {
            const left = try allocator.create(ast.RowSource);
            errdefer allocator.destroy(left);
            left.* = try materializeRowSource(allocator, join.left.*, env);
            errdefer left.deinit(allocator);

            const right = try allocator.create(ast.RowSource);
            errdefer allocator.destroy(right);
            right.* = try materializeRowSource(allocator, join.right.*, env);
            errdefer right.deinit(allocator);

            var on: ?ast.Expression = null;
            errdefer if (on) |condition| condition.deinit(allocator);
            if (join.on) |condition| {
                on = try materializeProcedureExpression(allocator, condition, env);
            }

            break :blk .{ .join = .{
                .left = left,
                .join_type = join.join_type,
                .right = right,
                .on = on,
            } };
        },
    };
}

fn materializeProcedureExpression(
    allocator: std.mem.Allocator,
    expression: ast.Expression,
    env: *const ProcedureEnv,
) ProcedureMaterializeError!ast.Expression {
    return switch (expression) {
        .identifier => |identifier| if (env.get(identifier)) |runtime_value|
            .{ .literal = try literalFromValue(allocator, runtime_value) }
        else
            .{ .identifier = try allocator.dupe(u8, identifier) },
        .literal => |literal| .{ .literal = try cloneLiteralForProcedure(allocator, literal) },
        .star => .star,
        .function_call => |call| blk: {
            const name = try allocator.dupe(u8, call.name);
            errdefer allocator.free(name);

            var args = try allocator.alloc(ast.Expression, call.args.len);
            errdefer allocator.free(args);
            var count: usize = 0;
            errdefer {
                for (args[0..count]) |arg| arg.deinit(allocator);
            }
            for (call.args, 0..) |arg, index| {
                args[index] = try materializeProcedureExpression(allocator, arg, env);
                count += 1;
            }

            break :blk .{
                .function_call = .{
                    .name = name,
                    .args = args,
                },
            };
        },
        .binary => |binary| blk: {
            const left = try allocator.create(ast.Expression);
            errdefer allocator.destroy(left);
            left.* = try materializeProcedureExpression(allocator, binary.left.*, env);
            errdefer left.deinit(allocator);

            const right = try allocator.create(ast.Expression);
            errdefer allocator.destroy(right);
            right.* = try materializeProcedureExpression(allocator, binary.right.*, env);

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

fn literalFromValue(allocator: std.mem.Allocator, runtime_value: value.Value) !ast.Literal {
    return switch (runtime_value) {
        .null => .null,
        .integer => |integer| .{ .integer = integer },
        .float => |float| .{ .float = float },
        .boolean => |boolean| .{ .boolean = boolean },
        .text => |text| .{ .string = try allocator.dupe(u8, text) },
        .blob => error.UnsupportedProcedure,
        .vector => |vector| blk: {
            var components = try allocator.alloc(f64, vector.values.len);
            for (vector.values, 0..) |component, index| {
                components[index] = component;
            }
            break :blk .{ .vector = components };
        },
    };
}

fn cloneLiteralForProcedure(allocator: std.mem.Allocator, literal: ast.Literal) !ast.Literal {
    return switch (literal) {
        .null => .null,
        .integer => |integer| .{ .integer = integer },
        .float => |float| .{ .float = float },
        .boolean => |boolean| .{ .boolean = boolean },
        .string => |string| .{ .string = try allocator.dupe(u8, string) },
        .vector => |components| .{ .vector = try allocator.dupe(f64, components) },
    };
}

fn evalProcedureExpression(
    allocator: std.mem.Allocator,
    env: *const ProcedureEnv,
    expression: ast.Expression,
) anyerror!value.Value {
    return switch (expression) {
        .literal => |literal| try valueFromLiteral(allocator, literal),
        .identifier => |identifier| blk: {
            const runtime_value = env.get(identifier) orelse return error.UnknownObject;
            break :blk try runtime_value.clone(allocator);
        },
        .binary => |binary| try evalProcedureBinary(allocator, env, binary),
        .function_call => error.UnsupportedExpression,
        .star => error.UnsupportedExpression,
    };
}

fn evalProcedureBinary(
    allocator: std.mem.Allocator,
    env: *const ProcedureEnv,
    binary: ast.BinaryExpression,
) anyerror!value.Value {
    var left = try evalProcedureExpression(allocator, env, binary.left.*);
    defer left.deinit(allocator);
    var right = try evalProcedureExpression(allocator, env, binary.right.*);
    defer right.deinit(allocator);

    return evalBinaryValues(left, right, binary.operator);
}

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
    snapshot_sequence: ?concurrency.SnapshotGeneration = null,
    last_commit_sequence: ?concurrency.CommitSequence = null,
    transactions: std.ArrayList(TableTransaction) = .empty,
    snapshot_handle: ?snapshot.SnapshotHandle = null,

    pub fn init(allocator: std.mem.Allocator) Session {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Session) void {
        for (self.transactions.items) |*entry| entry.deinit(self.allocator);
        self.transactions.deinit(self.allocator);
        self.releaseSnapshotHandle();
        self.* = undefined;
    }

    pub fn begin(self: *Session, db: *Database) !void {
        if (self.active) return error.TransactionActive;
        db.lockCommits();
        defer db.unlockCommits();

        const handle = try db.snapshot_registry.acquire(db.currentCommitSequence());
        self.snapshot_sequence = handle.generation;
        self.snapshot_handle = handle;
        self.active = true;
    }

    pub fn commit(self: *Session, db: *Database) !void {
        if (!self.active) return error.NoActiveTransaction;
        db.lockCommits();
        defer db.unlockCommits();

        const had_writes = self.transactions.items.len > 0;
        if (had_writes) {
            try db.retainCurrentGenerationForActiveSnapshots(self.snapshot_handle);
        }
        for (self.transactions.items) |*entry| {
            try entry.tx.commit();
        }
        if (had_writes) db.commit_sequence += 1;
        self.last_commit_sequence = db.currentCommitSequence();
        self.clearTransactions();
        self.releaseSnapshotHandle();
        self.active = false;
    }

    pub fn rollback(self: *Session) !void {
        if (!self.active) return error.NoActiveTransaction;
        for (self.transactions.items) |*entry| {
            try entry.tx.rollback();
        }
        self.clearTransactions();
        self.releaseSnapshotHandle();
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

    fn snapshotStoreForRead(
        self: *const Session,
        db: *const Database,
        table_name: []const u8,
    ) !?*const row_store.RowStore {
        if (!self.active) return null;
        const handle = self.snapshot_handle orelse return null;
        if (db.snapshot_registry.retainedStoreForTable(handle.generation, table_name)) |store| return store;
        if (handle.generation == db.currentCommitSequence()) return null;
        return error.SnapshotRetentionExceeded;
    }

    fn baseStoreForRead(
        self: *const Session,
        db: *const Database,
        table: *TableState,
    ) !*const row_store.RowStore {
        if (try self.snapshotStoreForRead(db, table.name)) |snapshot_store| return snapshot_store;
        return &table.store;
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

    fn releaseSnapshotHandle(self: *Session) void {
        if (self.snapshot_handle) |*handle| handle.release();
        self.snapshot_handle = null;
        self.snapshot_sequence = null;
    }
};

const QuerySourceBridge = struct {
    db: *Database,
    session: *Session,
};

fn loadBaseTableForQuerySource(user_data: *anyopaque, name: []const u8) !query_source.BaseTable {
    const bridge: *QuerySourceBridge = @ptrCast(@alignCast(user_data));
    const table_state = bridge.db.getTableState(name) orelse return error.UnknownObject;
    return .{
        .name = table_state.store.table.name,
        .columns = table_state.store.table.columns,
        .rows = try scanRowsForTable(bridge.db.allocator, bridge.db, bridge.session, table_state),
    };
}

fn findViewForQuerySource(user_data: *anyopaque, name: []const u8) ?*const ast.SelectStatement {
    const bridge: *QuerySourceBridge = @ptrCast(@alignCast(user_data));
    const stored = bridge.db.views.get(name) orelse return null;
    return &stored.query;
}

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

fn countPrimaryColumns(columns: []const ast.ColumnDef) usize {
    var count: usize = 0;
    for (columns) |column| {
        if (column.primary_key) count += 1;
    }
    return count;
}

fn scanRowsForTable(
    allocator: std.mem.Allocator,
    db: *const Database,
    session: *const Session,
    table: *TableState,
) ![]row_store.Row {
    if (session.transactionForRead(table.name)) |tx| {
        const base_store = try session.baseStoreForRead(db, table);
        return tx.scanWithBase(base_store);
    }

    if (try session.snapshotStoreForRead(db, table.name)) |snapshot_store| {
        return cloneRowsFromStore(allocator, snapshot_store);
    }

    return cloneRowsFromStore(allocator, &table.store);
}

fn cloneRowsFromStore(allocator: std.mem.Allocator, store: *const row_store.RowStore) ![]row_store.Row {
    var rows = try allocator.alloc(row_store.Row, store.rows().len);
    errdefer allocator.free(rows);

    var count: usize = 0;
    errdefer {
        for (rows[0..count]) |*row| row.deinit(allocator);
    }

    for (store.rows(), 0..) |row, index| {
        rows[index] = try row.clone(allocator, store.table);
        count += 1;
    }

    return rows;
}

fn cloneTableDef(allocator: std.mem.Allocator, source: catalog.TableDef) !catalog.TableDef {
    var columns = try allocator.alloc(catalog.ColumnSpec, source.columns.len);
    defer allocator.free(columns);
    for (source.columns, 0..) |column, index| {
        columns[index] = .{
            .name = column.name,
            .column_type = column.column_type,
            .nullable = column.nullable,
            .default_value = column.default_value,
            .primary_key = column.primary_key,
            .auto_increment = column.auto_increment,
        };
    }

    var indexes = try allocator.alloc(catalog.IndexSpec, source.indexes.len);
    defer allocator.free(indexes);
    for (source.indexes, 0..) |index, offset| {
        indexes[offset] = .{
            .name = index.name,
            .columns = index.columns,
            .kind = index.kind,
        };
    }

    return catalog.TableDef.init(allocator, .{
        .name = source.name,
        .columns = columns,
        .indexes = indexes,
    });
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
        .function_call => |call| {
            for (call.args) |arg| try validateExpressionColumns(table, arg);
        },
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
        .function_call => |call| try evalFunctionCall(allocator, table, row, call),
        .star => error.UnsupportedExpression,
    };
}

fn evalFunctionCall(
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    row: row_store.Row,
    call: ast.FunctionCall,
) anyerror!value.Value {
    if (isBuiltin(call.name, "l2_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, table, row, call, .l2) };
    }
    if (isBuiltin(call.name, "squared_l2_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, table, row, call, .squared_l2) };
    }
    if (isBuiltin(call.name, "cosine_distance")) {
        return .{ .float = try evalVectorDistanceFunction(allocator, table, row, call, .cosine) };
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
    table: *const catalog.TableDef,
    row: row_store.Row,
    call: ast.FunctionCall,
    function: VectorDistanceFunction,
) anyerror!f64 {
    if (call.args.len != 2) return error.UnsupportedExpression;

    var left = try evalExpression(allocator, table, row, call.args[0]);
    defer left.deinit(allocator);
    var right = try evalExpression(allocator, table, row, call.args[1]);
    defer right.deinit(allocator);

    if (left != .vector or right != .vector) return error.TypeMismatch;

    return switch (function) {
        .l2 => try vector_distance.l2(left.vector.values, right.vector.values),
        .squared_l2 => try vector_distance.squaredL2(left.vector.values, right.vector.values),
        .cosine => try vector_distance.cosineDistance(left.vector.values, right.vector.values),
    };
}

fn isBuiltin(actual: []const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(actual, expected);
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

fn deinitColumns(allocator: std.mem.Allocator, columns: [][]u8) void {
    for (columns) |column| allocator.free(column);
    allocator.free(columns);
}

fn deinitValues(allocator: std.mem.Allocator, values: []value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}

fn deinitColumnSpecDefaults(allocator: std.mem.Allocator, columns: []catalog.ColumnSpec) void {
    for (columns) |*column| {
        if (column.default_value) |*default| default.deinit(allocator);
    }
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

test "executor applies mysql-style ddl metadata during insert and drop" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(
        &session,
        "CREATE TABLE IF NOT EXISTS memories (id INTEGER PRIMARY KEY AUTO_INCREMENT, body TEXT NOT NULL DEFAULT 'seed', tag TEXT NULL, INDEX idx_tag (tag));",
    );
    result.deinit(allocator);
    result = try db.executeSql(
        &session,
        "CREATE TABLE IF NOT EXISTS memories (id INTEGER PRIMARY KEY AUTO_INCREMENT, body TEXT NOT NULL DEFAULT 'seed', tag TEXT NULL, INDEX idx_tag (tag));",
    );
    result.deinit(allocator);

    const table = db.db_catalog.getTable("memories").?;
    try std.testing.expect(table.column("id").?.primary_key);
    try std.testing.expect(table.column("id").?.auto_increment);
    try std.testing.expectEqualStrings("seed", table.column("body").?.default_value.?.text);
    try std.testing.expectEqual(@as(usize, 2), table.indexes.len);
    try std.testing.expectEqualStrings("PRIMARY", table.indexes[0].name);
    try std.testing.expectEqualStrings("idx_tag", table.indexes[1].name);

    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories (tag) VALUES ('project');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT id, body, tag FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqualStrings("project", result.result_set.rows[0].values[2].text);
    result.deinit(allocator);

    result = try db.executeSql(&session, "COMMIT;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "DROP TABLE IF EXISTS missing;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "DROP TABLE IF EXISTS memories;");
    result.deinit(allocator);
    try std.testing.expect(db.db_catalog.getTable("memories") == null);
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

test "executor keeps read transaction snapshot stable across writer commit" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var seed = Session.init(allocator);
    defer seed.deinit();
    var reader = Session.init(allocator);
    defer reader.deinit();
    var writer = Session.init(allocator);
    defer writer.deinit();
    var observer = Session.init(allocator);
    defer observer.deinit();

    var result = try db.executeSql(&seed, "CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit(allocator);
    result = try db.executeSql(&seed, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&seed, "INSERT INTO memories VALUES (1, 'seed');");
    result.deinit(allocator);
    result = try db.executeSql(&seed, "COMMIT;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 1), db.currentCommitSequence());

    result = try db.executeSql(&reader, "BEGIN;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 1), reader.snapshot_sequence.?);

    result = try db.executeSql(&writer, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&writer, "INSERT INTO memories VALUES (2, 'writer');");
    result.deinit(allocator);
    result = try db.executeSql(&writer, "COMMIT;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 2), db.currentCommitSequence());

    result = try db.executeSql(&observer, "SELECT id FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&reader, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    result = try db.executeSql(&reader, "COMMIT;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 2), reader.last_commit_sequence.?);

    result = try db.executeSql(&reader, "SELECT id FROM memories ORDER BY id ASC;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
}

test "executor serializes concurrent writer commits into deterministic sequence" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var setup = Session.init(allocator);
    defer setup.deinit();
    var first = Session.init(allocator);
    defer first.deinit();
    var second = Session.init(allocator);
    defer second.deinit();
    var reader = Session.init(allocator);
    defer reader.deinit();

    var result = try db.executeSql(&setup, "CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit(allocator);

    result = try db.executeSql(&first, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&second, "BEGIN;");
    result.deinit(allocator);

    result = try db.executeSql(&first, "INSERT INTO memories VALUES (1, 'first');");
    result.deinit(allocator);
    result = try db.executeSql(&second, "INSERT INTO memories VALUES (2, 'second');");
    result.deinit(allocator);

    result = try db.executeSql(&first, "COMMIT;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 1), first.last_commit_sequence.?);
    try std.testing.expectEqual(@as(u64, 1), db.currentCommitSequence());

    result = try db.executeSql(&second, "COMMIT;");
    result.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 2), second.last_commit_sequence.?);
    try std.testing.expectEqual(@as(u64, 2), db.currentCommitSequence());

    result = try db.executeSql(&reader, "SELECT id, body FROM memories ORDER BY id ASC;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
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

test "executor evaluates vector distance functions in projection filter and ordering" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var session = Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'origin', [1, 0]);");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (2, 'side', [0, 1]);");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (3, 'near', [2, 0]);");
    result.deinit(allocator);

    result = try db.executeSql(
        &session,
        "SELECT id, l2_distance(embedding, [1, 0]) FROM memories ORDER BY l2_distance(embedding, [1, 0]) ASC LIMIT 2;",
    );
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqualStrings("l2_distance", result.result_set.columns[1]);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.result_set.rows[0].values[1].float, 0.000001);
    try std.testing.expectEqual(@as(i64, 3), result.result_set.rows[1].values[0].integer);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.result_set.rows[1].values[1].float, 0.000001);
    result.deinit(allocator);

    result = try db.executeSql(
        &session,
        "SELECT id FROM memories WHERE squared_l2_distance(embedding, [1, 0]) < 1.1 ORDER BY id ASC;",
    );
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.result_set.rows[1].values[0].integer);
    result.deinit(allocator);

    result = try db.executeSql(
        &session,
        "SELECT cosine_distance(embedding, [1, 0]) FROM memories WHERE id = 2;",
    );
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.result_set.rows[0].values[0].float, 0.000001);
    result.deinit(allocator);

    try std.testing.expectError(
        error.VectorDimensionMismatch,
        db.executeSql(&session, "SELECT l2_distance(embedding, [1, 0, 0]) FROM memories;"),
    );
    try std.testing.expectError(
        error.UnsupportedExpression,
        db.executeSql(&session, "SELECT made_up_distance(embedding, [1, 0]) FROM memories;"),
    );
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

test "executor runs procedure parameters variables control flow and transaction visibility" {
    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();
    var writer = Session.init(allocator);
    defer writer.deinit();
    var reader = Session.init(allocator);
    defer reader.deinit();

    var result = try db.executeSql(&writer, "CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit(allocator);
    result = try db.executeSql(&writer,
        \\CREATE PROCEDURE remember(IN p_id INT, IN p_body TEXT)
        \\BEGIN
        \\  DECLARE attempts INT DEFAULT 0;
        \\  IF p_id > 0 THEN
        \\    WHILE attempts < 1 DO
        \\      INSERT INTO memories (id, body) VALUES (p_id, p_body);
        \\      SET attempts = attempts + 1;
        \\    END WHILE;
        \\  END IF;
        \\END;
    );
    result.deinit(allocator);

    result = try db.executeSql(&writer, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&writer, "CALL remember(1, 'from proc');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try db.executeSql(&writer, "SELECT id, body FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    result = try db.executeSql(&reader, "SELECT id, body FROM memories;");
    try std.testing.expectEqual(@as(usize, 0), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&writer, "COMMIT;");
    result.deinit(allocator);

    result = try db.executeSql(&reader, "SELECT id, body FROM memories;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[1].text);
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
        db.executeSql(&session, "CREATE PROCEDURE bad_cursor() BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END;"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        db.executeSql(&session, "CREATE PROCEDURE bad_dynamic() BEGIN PREPARE stmt FROM 'SELECT 1'; END;"),
    );
    try std.testing.expectEqual(DiagnosticKind.unknown_column, diagnosticFromError(error.UnknownColumn).?);
}
