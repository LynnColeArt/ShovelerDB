const std = @import("std");
const ddl = @import("ddl.zig");
const value = @import("value.zig");

pub const CatalogError = error{
    DuplicateColumn,
    DuplicateObject,
    UnknownObject,
    NameConflict,
    TypeMismatch,
    VectorDimensionMismatch,
    InvalidVectorDimension,
};

pub const DiagnosticKind = enum {
    duplicate_column,
    duplicate_object,
    unknown_object,
    name_conflict,
    type_mismatch,
    vector_dimension_mismatch,
    invalid_vector_dimension,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.DuplicateColumn => .duplicate_column,
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.NameConflict => .name_conflict,
        error.TypeMismatch => .type_mismatch,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        else => null,
    };
}

pub const VectorType = struct {
    element_type: value.VectorElementType = .float32,
    dimension: usize,

    pub fn validate(self: VectorType) CatalogError!void {
        if (self.dimension == 0) return error.InvalidVectorDimension;
    }
};

pub const ColumnType = union(enum) {
    integer,
    float,
    boolean,
    text,
    blob,
    vector: VectorType,

    pub fn validate(self: ColumnType) CatalogError!void {
        switch (self) {
            .vector => |vector_type| try vector_type.validate(),
            else => {},
        }
    }

    pub fn acceptsValue(self: ColumnType, runtime_value: value.Value) CatalogError!void {
        switch (self) {
            .integer => if (runtime_value != .integer) return error.TypeMismatch,
            .float => if (runtime_value != .float) return error.TypeMismatch,
            .boolean => if (runtime_value != .boolean) return error.TypeMismatch,
            .text => if (runtime_value != .text) return error.TypeMismatch,
            .blob => if (runtime_value != .blob) return error.TypeMismatch,
            .vector => |vector_type| {
                if (runtime_value != .vector) return error.TypeMismatch;
                if (runtime_value.vector.element_type != vector_type.element_type or
                    runtime_value.vector.dimension != vector_type.dimension)
                {
                    return error.VectorDimensionMismatch;
                }
            },
        }
    }
};

pub const ColumnSpec = struct {
    name: []const u8,
    column_type: ColumnType,
    nullable: bool = true,
    default_value: ?value.Value = null,
    primary_key: bool = false,
    auto_increment: bool = false,
};

pub const ColumnDef = struct {
    name: []u8,
    column_type: ColumnType,
    nullable: bool = true,
    default_value: ?value.Value = null,
    primary_key: bool = false,
    auto_increment: bool = false,

    pub fn init(allocator: std.mem.Allocator, spec: ColumnSpec) !ColumnDef {
        try spec.column_type.validate();

        const name = try allocator.dupe(u8, spec.name);
        errdefer allocator.free(name);

        var default_value: ?value.Value = null;
        if (spec.default_value) |default| {
            if (default == .null) {
                if (!effectiveNullable(spec)) return error.TypeMismatch;
            } else {
                try spec.column_type.acceptsValue(default);
            }

            default_value = try default.clone(allocator);
            errdefer if (default_value) |*owned| owned.deinit(allocator);
        }

        return .{
            .name = name,
            .column_type = spec.column_type,
            .nullable = effectiveNullable(spec),
            .default_value = default_value,
            .primary_key = spec.primary_key,
            .auto_increment = spec.auto_increment,
        };
    }

    pub fn deinit(self: *ColumnDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.default_value) |*default| default.deinit(allocator);
        self.* = undefined;
    }

    pub fn validateValue(self: ColumnDef, runtime_value: value.Value) CatalogError!void {
        if (runtime_value == .null) {
            if (self.nullable) return;
            return error.TypeMismatch;
        }

        try self.column_type.acceptsValue(runtime_value);
    }
};

fn effectiveNullable(spec: ColumnSpec) bool {
    return spec.nullable and !spec.primary_key and !spec.auto_increment;
}

pub const IndexSpec = struct {
    name: ?[]const u8 = null,
    columns: []const []const u8,
    kind: ddl.IndexKind = .secondary,
};

pub const IndexDef = struct {
    name: []u8,
    columns: [][]u8,
    kind: ddl.IndexKind = .secondary,

    pub fn init(allocator: std.mem.Allocator, spec: IndexSpec) !IndexDef {
        if (spec.columns.len == 0) return error.UnknownObject;

        const index_name = spec.name orelse if (spec.kind == .primary) ddl.primary_index_name else spec.columns[0];
        const name = try allocator.dupe(u8, index_name);
        errdefer allocator.free(name);

        var columns = try allocator.alloc([]u8, spec.columns.len);
        errdefer allocator.free(columns);

        var initialized: usize = 0;
        errdefer {
            for (columns[0..initialized]) |column| allocator.free(column);
        }
        for (spec.columns, 0..) |column, index| {
            columns[index] = try allocator.dupe(u8, column);
            initialized += 1;
        }

        return .{ .name = name, .columns = columns, .kind = spec.kind };
    }

    pub fn deinit(self: *IndexDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.columns) |column| allocator.free(column);
        allocator.free(self.columns);
        self.* = undefined;
    }
};

pub const TableSpec = struct {
    name: []const u8,
    columns: []const ColumnSpec,
    indexes: []const IndexSpec = &.{},
};

pub const TableDef = struct {
    name: []u8,
    columns: []ColumnDef,
    indexes: []IndexDef = &.{},

    pub fn init(allocator: std.mem.Allocator, spec: TableSpec) !TableDef {
        try validateColumns(spec.columns);
        try validateIndexes(spec.columns, spec.indexes);

        const name = try allocator.dupe(u8, spec.name);
        errdefer allocator.free(name);

        var columns = try allocator.alloc(ColumnDef, spec.columns.len);
        errdefer allocator.free(columns);

        var initialized: usize = 0;
        errdefer {
            for (columns[0..initialized]) |*column_def| column_def.deinit(allocator);
        }

        for (spec.columns, 0..) |column_spec, index| {
            columns[index] = try ColumnDef.init(allocator, column_spec);
            initialized += 1;
        }

        var indexes = try allocator.alloc(IndexDef, spec.indexes.len);
        errdefer allocator.free(indexes);

        var index_initialized: usize = 0;
        errdefer {
            for (indexes[0..index_initialized]) |*index_def| index_def.deinit(allocator);
        }
        for (spec.indexes, 0..) |index_spec, index| {
            indexes[index] = try IndexDef.init(allocator, index_spec);
            if (index_spec.kind == .primary) {
                for (index_spec.columns) |column_name| {
                    const column_index = columnIndexInSpecs(spec.columns, column_name) orelse return error.UnknownObject;
                    columns[column_index].primary_key = true;
                    columns[column_index].nullable = false;
                }
            }
            index_initialized += 1;
        }

        return .{ .name = name, .columns = columns, .indexes = indexes };
    }

    pub fn deinit(self: *TableDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.columns) |*column_def| column_def.deinit(allocator);
        allocator.free(self.columns);
        for (self.indexes) |*index_def| index_def.deinit(allocator);
        allocator.free(self.indexes);
        self.* = undefined;
    }

    pub fn columnIndex(self: TableDef, name: []const u8) ?usize {
        for (self.columns, 0..) |column_def, index| {
            if (namesEqual(column_def.name, name)) return index;
        }
        return null;
    }

    pub fn column(self: *const TableDef, name: []const u8) ?*const ColumnDef {
        const index = self.columnIndex(name) orelse return null;
        return &self.columns[index];
    }

    pub fn columnAt(self: *const TableDef, index: usize) ?*const ColumnDef {
        if (index >= self.columns.len) return null;
        return &self.columns[index];
    }
};

pub const ViewDef = struct {
    name: []u8,
    body: []u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, body: []const u8) !ViewDef {
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        return .{
            .name = owned_name,
            .body = try allocator.dupe(u8, body),
        };
    }

    pub fn deinit(self: *ViewDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const ProcedureDef = struct {
    name: []u8,
    body: []u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, body: []const u8) !ProcedureDef {
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        return .{
            .name = owned_name,
            .body = try allocator.dupe(u8, body),
        };
    }

    pub fn deinit(self: *ProcedureDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const DatabaseCatalog = struct {
    allocator: std.mem.Allocator,
    tables: std.ArrayList(TableDef) = .empty,
    views: std.ArrayList(ViewDef) = .empty,
    procedures: std.ArrayList(ProcedureDef) = .empty,

    pub fn init(allocator: std.mem.Allocator) DatabaseCatalog {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DatabaseCatalog) void {
        for (self.tables.items) |*table| table.deinit(self.allocator);
        self.tables.deinit(self.allocator);

        for (self.views.items) |*view| view.deinit(self.allocator);
        self.views.deinit(self.allocator);

        for (self.procedures.items) |*procedure| procedure.deinit(self.allocator);
        self.procedures.deinit(self.allocator);

        self.* = undefined;
    }

    pub fn createTable(self: *DatabaseCatalog, spec: TableSpec) !void {
        if (self.findTableIndex(spec.name) != null) return error.DuplicateObject;
        if (self.nameUsedOutsideTables(spec.name)) return error.NameConflict;

        var table = try TableDef.init(self.allocator, spec);
        errdefer table.deinit(self.allocator);

        try self.tables.append(self.allocator, table);
    }

    pub fn dropTable(self: *DatabaseCatalog, name: []const u8) CatalogError!void {
        const index = self.findTableIndex(name) orelse return error.UnknownObject;
        var table = self.tables.orderedRemove(index);
        table.deinit(self.allocator);
    }

    pub fn getTable(self: *const DatabaseCatalog, name: []const u8) ?*const TableDef {
        const index = self.findTableIndex(name) orelse return null;
        return &self.tables.items[index];
    }

    pub fn listTables(self: *const DatabaseCatalog) []const TableDef {
        return self.tables.items;
    }

    pub fn registerView(self: *DatabaseCatalog, name: []const u8, body: []const u8) !void {
        if (self.findViewIndex(name) != null) return error.DuplicateObject;
        if (self.nameUsedOutsideViews(name)) return error.NameConflict;

        var view = try ViewDef.init(self.allocator, name, body);
        errdefer view.deinit(self.allocator);

        try self.views.append(self.allocator, view);
    }

    pub fn dropView(self: *DatabaseCatalog, name: []const u8) CatalogError!void {
        const index = self.findViewIndex(name) orelse return error.UnknownObject;
        var view = self.views.orderedRemove(index);
        view.deinit(self.allocator);
    }

    pub fn getView(self: *const DatabaseCatalog, name: []const u8) ?*const ViewDef {
        const index = self.findViewIndex(name) orelse return null;
        return &self.views.items[index];
    }

    pub fn listViews(self: *const DatabaseCatalog) []const ViewDef {
        return self.views.items;
    }

    pub fn registerProcedure(self: *DatabaseCatalog, name: []const u8, body: []const u8) !void {
        if (self.findProcedureIndex(name) != null) return error.DuplicateObject;
        if (self.nameUsedOutsideProcedures(name)) return error.NameConflict;

        var procedure = try ProcedureDef.init(self.allocator, name, body);
        errdefer procedure.deinit(self.allocator);

        try self.procedures.append(self.allocator, procedure);
    }

    pub fn dropProcedure(self: *DatabaseCatalog, name: []const u8) CatalogError!void {
        const index = self.findProcedureIndex(name) orelse return error.UnknownObject;
        var procedure = self.procedures.orderedRemove(index);
        procedure.deinit(self.allocator);
    }

    pub fn getProcedure(self: *const DatabaseCatalog, name: []const u8) ?*const ProcedureDef {
        const index = self.findProcedureIndex(name) orelse return null;
        return &self.procedures.items[index];
    }

    pub fn listProcedures(self: *const DatabaseCatalog) []const ProcedureDef {
        return self.procedures.items;
    }

    fn findTableIndex(self: *const DatabaseCatalog, name: []const u8) ?usize {
        for (self.tables.items, 0..) |table, index| {
            if (namesEqual(table.name, name)) return index;
        }
        return null;
    }

    fn findViewIndex(self: *const DatabaseCatalog, name: []const u8) ?usize {
        for (self.views.items, 0..) |view, index| {
            if (namesEqual(view.name, name)) return index;
        }
        return null;
    }

    fn findProcedureIndex(self: *const DatabaseCatalog, name: []const u8) ?usize {
        for (self.procedures.items, 0..) |procedure, index| {
            if (namesEqual(procedure.name, name)) return index;
        }
        return null;
    }

    fn nameUsedOutsideTables(self: *const DatabaseCatalog, name: []const u8) bool {
        return self.findViewIndex(name) != null or self.findProcedureIndex(name) != null;
    }

    fn nameUsedOutsideViews(self: *const DatabaseCatalog, name: []const u8) bool {
        return self.findTableIndex(name) != null or self.findProcedureIndex(name) != null;
    }

    fn nameUsedOutsideProcedures(self: *const DatabaseCatalog, name: []const u8) bool {
        return self.findTableIndex(name) != null or self.findViewIndex(name) != null;
    }
};

fn validateColumns(columns: []const ColumnSpec) CatalogError!void {
    for (columns, 0..) |column, index| {
        try column.column_type.validate();
        if (column.auto_increment and column.column_type != .integer) return error.TypeMismatch;
        for (columns[0..index]) |previous| {
            if (namesEqual(column.name, previous.name)) return error.DuplicateColumn;
        }
    }
}

fn validateIndexes(columns: []const ColumnSpec, indexes: []const IndexSpec) CatalogError!void {
    var primary_count: usize = 0;
    for (indexes, 0..) |index, offset| {
        if (index.kind == .primary) primary_count += 1;
        if (primary_count > 1) return error.DuplicateObject;

        if (index.name) |name| {
            for (indexes[0..offset]) |previous| {
                if (previous.name) |previous_name| {
                    if (namesEqual(name, previous_name)) return error.DuplicateObject;
                }
            }
        }

        for (index.columns) |column_name| {
            if (columnIndexInSpecs(columns, column_name) == null) return error.UnknownObject;
        }
    }
}

fn columnIndexInSpecs(columns: []const ColumnSpec, name: []const u8) ?usize {
    for (columns, 0..) |column, index| {
        if (namesEqual(column.name, name)) return index;
    }
    return null;
}

fn namesEqual(a: []const u8, b: []const u8) bool {
    return ddl.namesEqual(a, b);
}

test "table metadata supports lookup, ordinals, and vector columns" {
    const allocator = std.testing.allocator;

    var table = try TableDef.init(allocator, .{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text },
            .{
                .name = "embedding",
                .column_type = .{ .vector = .{ .dimension = 3 } },
                .nullable = false,
            },
        },
    });
    defer table.deinit(allocator);

    try std.testing.expectEqualStrings("memories", table.name);
    try std.testing.expectEqual(@as(usize, 0), table.columnIndex("ID").?);
    try std.testing.expectEqual(@as(usize, 2), table.columnIndex("embedding").?);
    try std.testing.expect(table.columnIndex("missing") == null);

    const embedding = table.column("embedding").?;
    try std.testing.expectEqual(@as(usize, 3), embedding.column_type.vector.dimension);
    try std.testing.expectEqualStrings("body", table.columnAt(1).?.name);
}

test "table metadata rejects duplicate columns and invalid vector dimensions" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.DuplicateColumn, TableDef.init(allocator, .{
        .name = "bad",
        .columns = &.{
            .{ .name = "id", .column_type = .integer },
            .{ .name = "ID", .column_type = .integer },
        },
    }));

    try std.testing.expectError(error.InvalidVectorDimension, TableDef.init(allocator, .{
        .name = "bad_vector",
        .columns = &.{
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 0 } } },
        },
    }));
}

test "table metadata stores primary autoincrement defaults and indexes" {
    const allocator = std.testing.allocator;

    var default_body = try value.Value.initText(allocator, "seed");
    defer default_body.deinit(allocator);

    var table = try TableDef.init(allocator, .{
        .name = "memories",
        .columns = &.{
            .{
                .name = "id",
                .column_type = .integer,
                .nullable = true,
                .primary_key = true,
                .auto_increment = true,
            },
            .{ .name = "body", .column_type = .text, .nullable = false, .default_value = default_body },
            .{ .name = "tag", .column_type = .text },
        },
        .indexes = &.{
            .{ .columns = &.{"id"}, .kind = .primary },
            .{ .name = "idx_tag", .columns = &.{"tag"} },
        },
    });
    defer table.deinit(allocator);

    try std.testing.expect(table.column("id").?.primary_key);
    try std.testing.expect(table.column("id").?.auto_increment);
    try std.testing.expect(!table.column("id").?.nullable);
    try std.testing.expectEqualStrings("seed", table.column("body").?.default_value.?.text);
    try std.testing.expectEqual(@as(usize, 2), table.indexes.len);
    try std.testing.expectEqualStrings("PRIMARY", table.indexes[0].name);
    try std.testing.expectEqualStrings("idx_tag", table.indexes[1].name);
    try std.testing.expectEqualStrings("tag", table.indexes[1].columns[0]);
}

test "table metadata rejects invalid indexes and auto increment columns" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TypeMismatch, TableDef.init(allocator, .{
        .name = "bad_auto",
        .columns = &.{
            .{ .name = "id", .column_type = .text, .auto_increment = true },
        },
    }));

    try std.testing.expectError(error.UnknownObject, TableDef.init(allocator, .{
        .name = "bad_index",
        .columns = &.{
            .{ .name = "id", .column_type = .integer },
        },
        .indexes = &.{
            .{ .name = "idx_missing", .columns = &.{"missing"} },
        },
    }));

    try std.testing.expectError(error.DuplicateObject, TableDef.init(allocator, .{
        .name = "duplicate_primary",
        .columns = &.{
            .{ .name = "id", .column_type = .integer },
            .{ .name = "other_id", .column_type = .integer },
        },
        .indexes = &.{
            .{ .columns = &.{"id"}, .kind = .primary },
            .{ .columns = &.{"other_id"}, .kind = .primary },
        },
    }));
}

test "column values validate scalar and vector types" {
    const allocator = std.testing.allocator;

    var vector_value = try value.Value.initVector(allocator, .float32, 2, &.{ 0.5, 0.25 });
    defer vector_value.deinit(allocator);

    var wrong_dim = try value.Value.initVector(allocator, .float32, 3, &.{ 0.5, 0.25, 0.125 });
    defer wrong_dim.deinit(allocator);

    const embedding = ColumnDef{
        .name = @constCast("embedding"),
        .column_type = .{ .vector = .{ .dimension = 2 } },
        .nullable = false,
    };

    try embedding.validateValue(vector_value);
    try std.testing.expectError(error.VectorDimensionMismatch, embedding.validateValue(wrong_dim));
    try std.testing.expectError(error.TypeMismatch, embedding.validateValue(.null));

    const body = ColumnDef{
        .name = @constCast("body"),
        .column_type = .text,
        .nullable = true,
    };
    try body.validateValue(.null);
    try std.testing.expectError(error.TypeMismatch, body.validateValue(.{ .integer = 42 }));
}

test "catalog creates, lists, gets, and drops tables" {
    const allocator = std.testing.allocator;

    var catalog = DatabaseCatalog.init(allocator);
    defer catalog.deinit();

    try catalog.createTable(.{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text },
        },
    });

    try std.testing.expectEqual(@as(usize, 1), catalog.listTables().len);
    try std.testing.expectEqualStrings("memories", catalog.getTable("MEMORIES").?.name);
    try std.testing.expectError(error.DuplicateObject, catalog.createTable(.{
        .name = "Memories",
        .columns = &.{.{ .name = "id", .column_type = .integer }},
    }));

    try catalog.dropTable("memories");
    try std.testing.expect(catalog.getTable("memories") == null);
    try std.testing.expectEqual(@as(usize, 0), catalog.listTables().len);
    try std.testing.expectError(error.UnknownObject, catalog.dropTable("memories"));
}

test "catalog prevents name conflicts across tables views and procedures" {
    const allocator = std.testing.allocator;

    var catalog = DatabaseCatalog.init(allocator);
    defer catalog.deinit();

    try catalog.createTable(.{
        .name = "memories",
        .columns = &.{.{ .name = "id", .column_type = .integer }},
    });

    try std.testing.expectError(
        error.NameConflict,
        catalog.registerView("memories", "SELECT id FROM memories"),
    );
    try std.testing.expectError(
        error.NameConflict,
        catalog.registerProcedure("MEMORIES", "BEGIN SELECT id FROM memories; END"),
    );

    try catalog.registerView("recent_memories", "SELECT id FROM memories");
    try std.testing.expectError(error.NameConflict, catalog.createTable(.{
        .name = "recent_memories",
        .columns = &.{.{ .name = "id", .column_type = .integer }},
    }));

    try catalog.registerProcedure("remember", "BEGIN SELECT id FROM memories; END");
    try std.testing.expectError(
        error.DuplicateObject,
        catalog.registerProcedure("remember", "BEGIN SELECT 1; END"),
    );
}

test "catalog manages view and procedure metadata lifecycles" {
    const allocator = std.testing.allocator;

    var catalog = DatabaseCatalog.init(allocator);
    defer catalog.deinit();

    try catalog.registerView("recent_memories", "SELECT body FROM memories ORDER BY id DESC");
    try catalog.registerProcedure("remember", "BEGIN INSERT INTO memories VALUES (1); END");

    try std.testing.expectEqual(@as(usize, 1), catalog.listViews().len);
    try std.testing.expectEqual(@as(usize, 1), catalog.listProcedures().len);
    try std.testing.expectEqualStrings(
        "SELECT body FROM memories ORDER BY id DESC",
        catalog.getView("RECENT_MEMORIES").?.body,
    );
    try std.testing.expectEqualStrings(
        "BEGIN INSERT INTO memories VALUES (1); END",
        catalog.getProcedure("remember").?.body,
    );

    try catalog.dropView("recent_memories");
    try catalog.dropProcedure("remember");
    try std.testing.expect(catalog.getView("recent_memories") == null);
    try std.testing.expect(catalog.getProcedure("remember") == null);
    try std.testing.expectError(error.UnknownObject, catalog.dropView("recent_memories"));
    try std.testing.expectError(error.UnknownObject, catalog.dropProcedure("remember"));
}

test "catalog diagnostics map stable typed errors" {
    try std.testing.expectEqual(DiagnosticKind.duplicate_column, diagnosticFromError(error.DuplicateColumn).?);
    try std.testing.expectEqual(DiagnosticKind.duplicate_object, diagnosticFromError(error.DuplicateObject).?);
    try std.testing.expectEqual(DiagnosticKind.unknown_object, diagnosticFromError(error.UnknownObject).?);
    try std.testing.expectEqual(DiagnosticKind.name_conflict, diagnosticFromError(error.NameConflict).?);
    try std.testing.expectEqual(DiagnosticKind.type_mismatch, diagnosticFromError(error.TypeMismatch).?);
    try std.testing.expectEqual(
        DiagnosticKind.vector_dimension_mismatch,
        diagnosticFromError(error.VectorDimensionMismatch).?,
    );
    try std.testing.expectEqual(
        DiagnosticKind.invalid_vector_dimension,
        diagnosticFromError(error.InvalidVectorDimension).?,
    );
    try std.testing.expect(diagnosticFromError(error.OutOfMemory) == null);
}
