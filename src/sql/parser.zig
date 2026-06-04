const std = @import("std");
const ast = @import("ast.zig");
const policy = @import("policy.zig");
const tokenizer = @import("tokenizer.zig");

const ParseError = error{ ParseFailed, OutOfMemory };

const ColumnAttributes = struct {
    nullable: bool = true,
    default_value: ?ast.Expression = null,
    primary_key: bool = false,
    auto_increment: bool = false,

    fn deinit(self: *ColumnAttributes, allocator: std.mem.Allocator) void {
        if (self.default_value) |default| default.deinit(allocator);
        self.* = undefined;
    }
};

pub const DiagnosticCode = enum {
    policy_violation,
    unexpected_token,
    unexpected_end,
    invalid_number,
    unsupported_syntax,
};

pub const Diagnostic = struct {
    code: DiagnosticCode,
    offset: usize,
    token: []const u8 = "",
    expected: []const u8 = "",
    policy_feature: ?policy.UnsupportedFeature = null,
};

pub const ParseResult = union(enum) {
    statement: ast.Statement,
    diagnostic: Diagnostic,

    pub fn deinit(self: ParseResult, allocator: std.mem.Allocator) void {
        switch (self) {
            .statement => |statement| statement.deinit(allocator),
            .diagnostic => {},
        }
    }
};

pub const ExpressionResult = union(enum) {
    expression: ast.Expression,
    diagnostic: Diagnostic,

    pub fn deinit(self: ExpressionResult, allocator: std.mem.Allocator) void {
        switch (self) {
            .expression => |expression| expression.deinit(allocator),
            .diagnostic => {},
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, sql: []const u8) !ParseResult {
    if (policy.firstViolation(sql)) |violation| {
        return .{
            .diagnostic = .{
                .code = .policy_violation,
                .offset = violation.offset,
                .token = violation.token,
                .expected = violation.message(),
                .policy_feature = violation.feature,
            },
        };
    }

    var parser = try Parser.init(allocator, sql);
    defer parser.deinit();

    const statement = parser.parseStatement() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseFailed => return .{ .diagnostic = parser.diagnostic },
    };

    parser.consumeSemicolons();
    if (parser.peek()) |token| {
        var owned_statement = statement;
        owned_statement.deinit(allocator);
        return .{ .diagnostic = parser.unexpected(token, "end of statement") };
    }

    return .{ .statement = statement };
}

pub fn parseExpressionOnly(allocator: std.mem.Allocator, sql: []const u8) !ExpressionResult {
    var parser = try Parser.init(allocator, sql);
    defer parser.deinit();

    const expression = parser.parseExpression() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseFailed => return .{ .diagnostic = parser.diagnostic },
    };

    if (parser.peek()) |token| {
        var owned_expression = expression;
        owned_expression.deinit(allocator);
        return .{ .diagnostic = parser.unexpected(token, "end of expression") };
    }

    return .{ .expression = expression };
}

const Parser = struct {
    allocator: std.mem.Allocator,
    sql: []const u8,
    tokens: []tokenizer.Token,
    index: usize = 0,
    diagnostic: Diagnostic = .{ .code = .unexpected_end, .offset = 0 },

    fn init(allocator: std.mem.Allocator, sql: []const u8) !Parser {
        var token_list: std.ArrayList(tokenizer.Token) = .empty;
        errdefer token_list.deinit(allocator);

        var stream = tokenizer.Tokenizer.init(sql);
        while (stream.next()) |token| {
            try token_list.append(allocator, token);
        }

        return .{
            .allocator = allocator,
            .sql = sql,
            .tokens = try token_list.toOwnedSlice(allocator),
        };
    }

    fn deinit(self: *Parser) void {
        self.allocator.free(self.tokens);
    }

    fn parseStatement(self: *Parser) ParseError!ast.Statement {
        if (self.matchKeyword("CREATE")) {
            if (self.matchKeyword("TABLE")) return .{ .create_table = try self.parseCreateTable() };
            if (self.matchKeyword("VIEW")) return .{ .create_view = try self.parseCreateView() };
            if (self.matchKeyword("PROCEDURE")) return .{ .create_procedure = try self.parseCreateProcedure() };
            return self.failCurrent(.unsupported_syntax, "TABLE, VIEW, or PROCEDURE");
        }

        if (self.matchKeyword("DROP")) {
            if (self.matchKeyword("TABLE")) return .{ .drop_table = try self.parseDropTable() };
            if (self.matchKeyword("VIEW")) return .{ .drop_view = .{ .name = try self.expectIdentifierOwned("view name") } };
            if (self.matchKeyword("PROCEDURE")) return .{ .drop_procedure = .{ .name = try self.expectIdentifierOwned("procedure name") } };
            return self.failCurrent(.unsupported_syntax, "TABLE, VIEW, or PROCEDURE");
        }

        if (self.matchKeyword("INSERT")) return .{ .insert = try self.parseInsert() };
        if (self.matchKeyword("SELECT")) return .{ .select = try self.parseSelectAfterSelect() };
        if (self.matchKeyword("WITH")) return .{ .select = try self.parseSelectAfterWith() };
        if (self.matchKeyword("UPDATE")) return .{ .update = try self.parseUpdate() };
        if (self.matchKeyword("DELETE")) return .{ .delete = try self.parseDelete() };
        if (self.matchKeyword("BEGIN")) return .begin;
        if (self.matchKeyword("COMMIT")) return .commit;
        if (self.matchKeyword("ROLLBACK")) return .rollback;
        if (self.matchKeyword("CALL")) return .{ .call = try self.parseCall() };

        return self.failCurrent(.unexpected_token, "supported ShovelerDB statement");
    }

    fn parseCreateTable(self: *Parser) ParseError!ast.CreateTableStatement {
        var if_not_exists = false;
        if (self.matchKeyword("IF")) {
            try self.expectKeyword("NOT");
            try self.expectKeyword("EXISTS");
            if_not_exists = true;
        }

        const name = try self.expectIdentifierOwned("table name");
        errdefer self.allocator.free(name);

        try self.expectSymbol("(");
        var columns: std.ArrayList(ast.ColumnDef) = .empty;
        errdefer {
            for (columns.items) |column| column.deinit(self.allocator);
            columns.deinit(self.allocator);
        }
        var indexes: std.ArrayList(ast.IndexDef) = .empty;
        errdefer {
            for (indexes.items) |index| index.deinit(self.allocator);
            indexes.deinit(self.allocator);
        }

        while (!self.matchSymbol(")")) {
            if (self.isTableIndexStart()) {
                try indexes.append(self.allocator, try self.parseTableIndex());
                if (self.matchSymbol(",")) continue;
                try self.expectSymbol(")");
                break;
            }

            var column_name: ?[]const u8 = try self.expectIdentifierOwned("column name");
            errdefer if (column_name) |owned| self.allocator.free(owned);
            const column_type = try self.parseColumnType();
            var attributes = try self.parseColumnAttributes();
            errdefer attributes.deinit(self.allocator);

            try columns.append(self.allocator, .{
                .name = column_name.?,
                .column_type = column_type,
                .nullable = attributes.nullable,
                .default_value = attributes.default_value,
                .primary_key = attributes.primary_key,
                .auto_increment = attributes.auto_increment,
            });
            column_name = null;
            attributes.default_value = null;

            if (self.matchSymbol(",")) continue;
            try self.expectSymbol(")");
            break;
        }

        const column_slice = try columns.toOwnedSlice(self.allocator);
        errdefer {
            for (column_slice) |column| column.deinit(self.allocator);
            self.allocator.free(column_slice);
        }
        const index_slice = try indexes.toOwnedSlice(self.allocator);
        errdefer {
            for (index_slice) |index| index.deinit(self.allocator);
            self.allocator.free(index_slice);
        }

        return .{
            .name = name,
            .if_not_exists = if_not_exists,
            .columns = column_slice,
            .indexes = index_slice,
        };
    }

    fn parseDropTable(self: *Parser) ParseError!ast.NamedStatement {
        var if_exists = false;
        if (self.matchKeyword("IF")) {
            try self.expectKeyword("EXISTS");
            if_exists = true;
        }
        return .{
            .name = try self.expectIdentifierOwned("table name"),
            .if_exists = if_exists,
        };
    }

    fn parseColumnType(self: *Parser) ParseError!ast.ColumnType {
        const token = self.advance() orelse return self.failEnd("column type");
        if (!isIdentifier(token)) return self.failToken(token, .unexpected_token, "column type");

        if (token.eqlIgnoreCase("INTEGER") or token.eqlIgnoreCase("INT")) return .integer;
        if (token.eqlIgnoreCase("FLOAT") or token.eqlIgnoreCase("REAL") or token.eqlIgnoreCase("DOUBLE")) return .float;
        if (token.eqlIgnoreCase("BOOLEAN") or token.eqlIgnoreCase("BOOL")) return .boolean;
        if (token.eqlIgnoreCase("TEXT") or token.eqlIgnoreCase("VARCHAR") or token.eqlIgnoreCase("CHAR")) return .text;
        if (token.eqlIgnoreCase("BLOB")) return .blob;
        if (token.eqlIgnoreCase("VECTOR")) {
            try self.expectSymbol("(");
            const dimension_token = self.advance() orelse return self.failEnd("vector dimension");
            if (dimension_token.kind != .number) return self.failToken(dimension_token, .unexpected_token, "vector dimension");
            const dimension = std.fmt.parseUnsigned(usize, dimension_token.lexeme, 10) catch {
                return self.failToken(dimension_token, .invalid_number, "vector dimension");
            };
            try self.expectSymbol(")");
            return .{ .vector = dimension };
        }

        return self.failToken(token, .unsupported_syntax, "MVP column type");
    }

    fn parseColumnAttributes(self: *Parser) ParseError!ColumnAttributes {
        var attributes = ColumnAttributes{};
        errdefer attributes.deinit(self.allocator);

        while (!self.isAtColumnDefinitionBoundary()) {
            if (self.matchKeyword("PRIMARY")) {
                try self.expectKeyword("KEY");
                attributes.primary_key = true;
                attributes.nullable = false;
                continue;
            }
            if (self.matchKeyword("NOT")) {
                try self.expectKeyword("NULL");
                attributes.nullable = false;
                continue;
            }
            if (self.matchKeyword("NULL")) {
                attributes.nullable = true;
                continue;
            }
            if (self.matchKeyword("DEFAULT")) {
                if (attributes.default_value) |default| default.deinit(self.allocator);
                attributes.default_value = try self.parseExpression();
                continue;
            }
            if (self.matchKeyword("AUTO_INCREMENT")) {
                attributes.auto_increment = true;
                attributes.nullable = false;
                continue;
            }

            try self.skipOneAttributeToken();
        }

        return attributes;
    }

    fn parseTableIndex(self: *Parser) ParseError!ast.IndexDef {
        if (self.matchKeyword("PRIMARY")) {
            try self.expectKeyword("KEY");
            return .{
                .name = null,
                .columns = try self.parseIndexColumnList(),
                .primary = true,
            };
        }

        if (!self.matchKeyword("INDEX") and !self.matchKeyword("KEY")) {
            return self.failCurrent(.unexpected_token, "INDEX or KEY");
        }

        var name: ?[]const u8 = null;
        errdefer if (name) |owned| self.allocator.free(owned);
        if (!self.nextIsSymbol("(")) {
            name = try self.expectIdentifierOwned("index name");
        }

        return .{
            .name = name,
            .columns = try self.parseIndexColumnList(),
            .primary = false,
        };
    }

    fn parseIndexColumnList(self: *Parser) ParseError![][]const u8 {
        try self.expectSymbol("(");
        var columns: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (columns.items) |column| self.allocator.free(column);
            columns.deinit(self.allocator);
        }

        while (!self.matchSymbol(")")) {
            var column: ?[]const u8 = try self.expectIdentifierOwned("index column");
            errdefer if (column) |owned| self.allocator.free(owned);
            if (self.matchSymbol("(")) {
                try self.skipBalanced(")");
            }
            try columns.append(self.allocator, column.?);
            column = null;
            if (self.matchSymbol(",")) continue;
            try self.expectSymbol(")");
            break;
        }
        return columns.toOwnedSlice(self.allocator);
    }

    fn parseInsert(self: *Parser) ParseError!ast.InsertStatement {
        try self.expectKeyword("INTO");
        const table_name = try self.expectIdentifierOwned("table name");
        errdefer self.allocator.free(table_name);

        var columns: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (columns.items) |column| self.allocator.free(column);
            columns.deinit(self.allocator);
        }
        if (self.matchSymbol("(")) {
            while (!self.matchSymbol(")")) {
                const column_token = try self.expectIdentifierToken("column name");
                var column_name: ?[]const u8 = try self.cloneIdentifierToken(column_token);
                errdefer if (column_name) |owned| self.allocator.free(owned);
                try columns.append(self.allocator, column_name.?);
                column_name = null;
                if (self.matchSymbol(",")) continue;
                try self.expectSymbol(")");
                break;
            }
        }

        try self.expectKeyword("VALUES");
        try self.expectSymbol("(");
        var values: std.ArrayList(ast.Expression) = .empty;
        errdefer {
            for (values.items) |value| value.deinit(self.allocator);
            values.deinit(self.allocator);
        }
        while (!self.matchSymbol(")")) {
            try values.append(self.allocator, try self.parseExpression());
            if (self.matchSymbol(",")) continue;
            try self.expectSymbol(")");
            break;
        }

        return .{
            .table_name = table_name,
            .columns = try columns.toOwnedSlice(self.allocator),
            .values = try values.toOwnedSlice(self.allocator),
        };
    }

    fn parseUpdate(self: *Parser) ParseError!ast.UpdateStatement {
        const table_name = try self.expectIdentifierOwned("table name");
        errdefer self.allocator.free(table_name);
        try self.expectKeyword("SET");

        var assignments: std.ArrayList(ast.Assignment) = .empty;
        errdefer {
            for (assignments.items) |assignment| assignment.deinit(self.allocator);
            assignments.deinit(self.allocator);
        }

        while (true) {
            var column: ?[]const u8 = try self.expectIdentifierOwned("column name");
            errdefer if (column) |owned| self.allocator.free(owned);
            try self.expectSymbol("=");
            try assignments.append(self.allocator, .{
                .column = column.?,
                .value = try self.parseExpression(),
            });
            column = null;
            if (!self.matchSymbol(",")) break;
        }

        var where_clause: ?ast.Expression = null;
        if (self.matchKeyword("WHERE")) {
            where_clause = try self.parseExpression();
        }

        return .{
            .table_name = table_name,
            .assignments = try assignments.toOwnedSlice(self.allocator),
            .where_clause = where_clause,
        };
    }

    fn parseDelete(self: *Parser) ParseError!ast.DeleteStatement {
        try self.expectKeyword("FROM");
        const table_name = try self.expectIdentifierOwned("table name");
        errdefer self.allocator.free(table_name);

        var where_clause: ?ast.Expression = null;
        if (self.matchKeyword("WHERE")) {
            where_clause = try self.parseExpression();
        }

        return .{
            .table_name = table_name,
            .where_clause = where_clause,
        };
    }

    fn parseSelectAfterWith(self: *Parser) ParseError!ast.SelectStatement {
        var ctes: std.ArrayList(ast.CommonTableExpression) = .empty;
        errdefer {
            for (ctes.items) |cte| cte.deinit(self.allocator);
            ctes.deinit(self.allocator);
        }

        while (true) {
            var name: ?[]const u8 = try self.expectIdentifierOwned("CTE name");
            errdefer if (name) |owned| self.allocator.free(owned);
            try self.expectKeyword("AS");
            try self.expectSymbol("(");
            try self.expectKeyword("SELECT");

            const query = try self.allocator.create(ast.SelectStatement);
            errdefer self.allocator.destroy(query);
            query.* = try self.parseSelectAfterSelect();
            errdefer query.deinit(self.allocator);

            try self.expectSymbol(")");
            try ctes.append(self.allocator, .{
                .name = name.?,
                .query = query,
            });
            name = null;

            if (!self.matchSymbol(",")) break;
        }

        try self.expectKeyword("SELECT");
        var statement = try self.parseSelectAfterSelect();
        errdefer statement.deinit(self.allocator);
        statement.ctes = try ctes.toOwnedSlice(self.allocator);
        return statement;
    }

    fn parseSelectAfterSelect(self: *Parser) ParseError!ast.SelectStatement {
        var projection_items: std.ArrayList(ast.Projection) = .empty;
        errdefer {
            for (projection_items.items) |projection| projection.deinit(self.allocator);
            projection_items.deinit(self.allocator);
        }

        var projections: std.ArrayList(ast.Expression) = .empty;
        errdefer {
            for (projections.items) |projection| projection.deinit(self.allocator);
            projections.deinit(self.allocator);
        }

        while (!self.isAtClauseBoundary()) {
            var projection: ?ast.Projection = try self.parseProjection();
            errdefer if (projection) |owned| owned.deinit(self.allocator);
            try projections.append(self.allocator, try ast.cloneExpression(self.allocator, projection.?.expression));
            try projection_items.append(self.allocator, projection.?);
            projection = null;
            if (self.matchSymbol(",")) continue;
            break;
        }

        var from: ?[]const u8 = null;
        errdefer if (from) |table_name| self.allocator.free(table_name);
        var source: ?*ast.RowSource = null;
        errdefer if (source) |owned_source| {
            owned_source.deinit(self.allocator);
            self.allocator.destroy(owned_source);
        };
        if (self.matchKeyword("FROM")) {
            source = try self.parseRowSource();
            if (source.?.* == .base_table) {
                from = try self.allocator.dupe(u8, source.?.base_table.name);
            }
        }

        var where_clause: ?ast.Expression = null;
        if (self.matchKeyword("WHERE")) {
            where_clause = try self.parseExpression();
        }

        var group_by: std.ArrayList(ast.Expression) = .empty;
        errdefer {
            for (group_by.items) |group_key| group_key.deinit(self.allocator);
            group_by.deinit(self.allocator);
        }
        if (self.matchKeyword("GROUP")) {
            try self.expectKeyword("BY");
            while (true) {
                try group_by.append(self.allocator, try self.parseExpression());
                if (!self.matchSymbol(",")) break;
            }
        }

        var having: ?ast.Expression = null;
        errdefer if (having) |expr| expr.deinit(self.allocator);
        if (self.matchKeyword("HAVING")) {
            having = try self.parseExpression();
        }

        var order_by: std.ArrayList(ast.OrderKey) = .empty;
        errdefer {
            for (order_by.items) |order_key| order_key.deinit(self.allocator);
            order_by.deinit(self.allocator);
        }
        if (self.matchKeyword("ORDER")) {
            try self.expectKeyword("BY");
            while (true) {
                var order_key: ast.OrderKey = .{ .expression = try self.parseExpression() };
                if (self.matchKeyword("DESC")) {
                    order_key.direction = .desc;
                } else _ = self.matchKeyword("ASC");
                try order_by.append(self.allocator, order_key);
                if (!self.matchSymbol(",")) break;
            }
        }

        var limit: ?usize = null;
        if (self.matchKeyword("LIMIT")) {
            const token = self.advance() orelse return self.failEnd("limit value");
            if (token.kind != .number) return self.failToken(token, .unexpected_token, "limit value");
            limit = std.fmt.parseUnsigned(usize, token.lexeme, 10) catch {
                return self.failToken(token, .invalid_number, "limit value");
            };
        }

        return .{
            .projection_items = try projection_items.toOwnedSlice(self.allocator),
            .projections = try projections.toOwnedSlice(self.allocator),
            .from = from,
            .source = source,
            .where_clause = where_clause,
            .group_by = try group_by.toOwnedSlice(self.allocator),
            .having = having,
            .order_by = try order_by.toOwnedSlice(self.allocator),
            .limit = limit,
        };
    }

    fn parseProjection(self: *Parser) ParseError!ast.Projection {
        const expression = try self.parseExpression();
        errdefer expression.deinit(self.allocator);

        var alias: ?[]const u8 = null;
        errdefer if (alias) |owned| self.allocator.free(owned);
        if (self.matchKeyword("AS")) {
            alias = try self.expectIdentifierOwned("projection alias");
        } else if (self.canStartImplicitProjectionAlias(expression)) {
            alias = try self.parseOptionalImplicitAlias();
        }

        const projection = ast.Projection{
            .expression = expression,
            .alias = alias,
        };
        alias = null;
        return projection;
    }

    fn canStartImplicitProjectionAlias(self: *Parser, expression: ast.Expression) bool {
        _ = self;
        return switch (expression) {
            .function_call, .literal, .binary => true,
            .identifier => |identifier| std.mem.indexOfScalar(u8, identifier, '.') != null,
            .star => false,
        };
    }

    fn parseOptionalImplicitAlias(self: *Parser) ParseError!?[]const u8 {
        const token = self.peek() orelse return null;
        if (!isIdentifier(token) or isImplicitAliasBoundary(token)) return null;
        _ = self.advance();
        return try self.cloneIdentifierToken(token);
    }

    fn parseRowSource(self: *Parser) ParseError!*ast.RowSource {
        var left: ?*ast.RowSource = try self.parseRowSourceAtom();
        errdefer {
            if (left) |owned| {
                owned.deinit(self.allocator);
                self.allocator.destroy(owned);
            }
        }

        while (self.peekJoinType()) |join_type| {
            try self.consumeJoinType(join_type);
            var right: ?*ast.RowSource = try self.parseRowSourceAtom();
            errdefer {
                if (right) |owned| {
                    owned.deinit(self.allocator);
                    self.allocator.destroy(owned);
                }
            }

            var on: ?ast.Expression = null;
            errdefer if (on) |expr| expr.deinit(self.allocator);
            if (self.matchKeyword("ON")) {
                on = try self.parseExpression();
            } else if (join_type != .cross) {
                return self.failCurrent(.unexpected_token, "ON");
            }

            const joined = try self.allocator.create(ast.RowSource);
            errdefer self.allocator.destroy(joined);
            joined.* = .{
                .join = .{
                    .left = left.?,
                    .join_type = join_type,
                    .right = right.?,
                    .on = on,
                },
            };
            left = joined;
            right = null;
            on = null;
        }

        const result = left.?;
        left = null;
        return result;
    }

    fn parseRowSourceAtom(self: *Parser) ParseError!*ast.RowSource {
        if (self.matchSymbol("(")) {
            var query: ?*ast.SelectStatement = try self.allocator.create(ast.SelectStatement);
            errdefer if (query) |owned| self.allocator.destroy(owned);
            if (self.matchKeyword("SELECT")) {
                query.?.* = try self.parseSelectAfterSelect();
            } else if (self.matchKeyword("WITH")) {
                query.?.* = try self.parseSelectAfterWith();
            } else {
                return self.failCurrent(.unexpected_token, "SELECT");
            }
            errdefer query.?.deinit(self.allocator);
            try self.expectSymbol(")");

            var alias: ?[]const u8 = try self.parseRequiredTableAlias("derived table alias");
            errdefer if (alias) |owned| self.allocator.free(owned);

            const source = try self.allocator.create(ast.RowSource);
            errdefer self.allocator.destroy(source);
            source.* = .{
                .derived_table = .{
                    .query = query.?,
                    .alias = alias.?,
                },
            };
            query = null;
            alias = null;
            return source;
        }

        const name = try self.expectIdentifierOwned("table name");
        errdefer self.allocator.free(name);
        var alias = try self.parseOptionalTableAlias();
        errdefer if (alias) |owned| self.allocator.free(owned);

        const source = try self.allocator.create(ast.RowSource);
        errdefer self.allocator.destroy(source);
        source.* = .{
            .base_table = .{
                .name = name,
                .alias = alias,
            },
        };
        alias = null;
        return source;
    }

    fn parseRequiredTableAlias(self: *Parser, expected: []const u8) ParseError![]const u8 {
        _ = self.matchKeyword("AS");
        return self.expectIdentifierOwned(expected);
    }

    fn parseOptionalTableAlias(self: *Parser) ParseError!?[]const u8 {
        if (self.matchKeyword("AS")) return try self.expectIdentifierOwned("table alias");
        const token = self.peek() orelse return null;
        if (!isIdentifier(token) or isTableAliasBoundary(token)) return null;
        _ = self.advance();
        return try self.cloneIdentifierToken(token);
    }

    fn peekJoinType(self: *Parser) ?ast.JoinType {
        const token = self.peek() orelse return null;
        if (token.eqlIgnoreCase("JOIN")) return .inner;
        if (token.eqlIgnoreCase("INNER")) return .inner;
        if (token.eqlIgnoreCase("CROSS")) return .cross;
        if (token.eqlIgnoreCase("LEFT")) return .left;
        return null;
    }

    fn consumeJoinType(self: *Parser, join_type: ast.JoinType) ParseError!void {
        switch (join_type) {
            .inner => {
                if (self.matchKeyword("INNER")) {
                    try self.expectKeyword("JOIN");
                } else {
                    try self.expectKeyword("JOIN");
                }
            },
            .cross => {
                try self.expectKeyword("CROSS");
                try self.expectKeyword("JOIN");
            },
            .left => {
                try self.expectKeyword("LEFT");
                _ = self.matchKeyword("OUTER");
                try self.expectKeyword("JOIN");
            },
        }
    }

    fn parseCreateView(self: *Parser) ParseError!ast.CreateViewStatement {
        const name = try self.expectIdentifierOwned("view name");
        errdefer self.allocator.free(name);
        try self.expectKeyword("AS");
        const select_token = self.peek() orelse return self.failEnd("SELECT");
        try self.expectKeyword("SELECT");
        const body_start = select_token.offset;
        const query = try self.allocator.create(ast.SelectStatement);
        errdefer self.allocator.destroy(query);
        query.* = try self.parseSelectAfterSelect();
        const body_end = if (self.peek()) |token| token.offset else self.sql.len;
        const body_sql = try self.allocator.dupe(
            u8,
            std.mem.trim(u8, self.sql[body_start..body_end], &std.ascii.whitespace),
        );
        return .{ .name = name, .query = query, .body_sql = body_sql };
    }

    fn parseCreateProcedure(self: *Parser) ParseError!ast.ProcedureStatement {
        const name = try self.expectIdentifierOwned("procedure name");
        errdefer self.allocator.free(name);

        var params: std.ArrayList(ast.ProcedureParam) = .empty;
        errdefer {
            for (params.items) |param| param.deinit(self.allocator);
            params.deinit(self.allocator);
        }
        if (self.matchSymbol("(")) {
            while (!self.matchSymbol(")")) {
                const mode: ast.ProcedureParamMode = blk: {
                    if (self.matchKeyword("IN")) break :blk .in;
                    if (self.peek()) |token| {
                        if (token.eqlIgnoreCase("OUT") or token.eqlIgnoreCase("INOUT")) {
                            return self.failToken(token, .unsupported_syntax, "IN parameter");
                        }
                    }
                    break :blk .in;
                };

                var param_name: ?[]const u8 = try self.expectIdentifierOwned("parameter name");
                errdefer if (param_name) |owned| self.allocator.free(owned);
                const column_type = try self.parseColumnType();
                try params.append(self.allocator, .{
                    .name = param_name.?,
                    .column_type = column_type,
                    .mode = mode,
                });
                param_name = null;

                if (self.matchSymbol(",")) continue;
                try self.expectSymbol(")");
                break;
            }
        }

        const body_start = if (self.peek()) |token| token.offset else self.sql.len;
        var body_end = self.sql.len;
        while (self.peek()) |token| {
            if (token.eqlIgnoreCase("END")) {
                body_end = token.offset + token.lexeme.len;
            }
            _ = self.advance();
        }

        if (body_start >= body_end) {
            self.diagnostic = .{
                .code = .unsupported_syntax,
                .offset = body_start,
                .expected = "procedure body",
            };
            return error.ParseFailed;
        }

        const param_slice = try params.toOwnedSlice(self.allocator);
        errdefer {
            for (param_slice) |param| param.deinit(self.allocator);
            self.allocator.free(param_slice);
        }
        const body_sql = try self.allocator.dupe(u8, std.mem.trim(u8, self.sql[body_start..body_end], &std.ascii.whitespace));

        return .{
            .name = name,
            .params = param_slice,
            .body_sql = body_sql,
        };
    }

    fn parseCall(self: *Parser) ParseError!ast.CallStatement {
        const name = try self.expectIdentifierOwned("procedure name");
        errdefer self.allocator.free(name);
        var args: std.ArrayList(ast.Expression) = .empty;
        errdefer {
            for (args.items) |arg| arg.deinit(self.allocator);
            args.deinit(self.allocator);
        }

        if (self.matchSymbol("(")) {
            while (!self.matchSymbol(")")) {
                try args.append(self.allocator, try self.parseExpression());
                if (self.matchSymbol(",")) continue;
                try self.expectSymbol(")");
                break;
            }
        }

        return .{
            .name = name,
            .args = try args.toOwnedSlice(self.allocator),
        };
    }

    fn parseExpression(self: *Parser) ParseError!ast.Expression {
        return self.parseAndExpression();
    }

    fn parseAndExpression(self: *Parser) ParseError!ast.Expression {
        var left = try self.parseComparisonExpression();

        while (self.matchKeyword("AND")) {
            left = try self.makeBinary(left, .and_op, try self.parseComparisonExpression());
        }

        return left;
    }

    fn parseComparisonExpression(self: *Parser) ParseError!ast.Expression {
        var left = try self.parseAdditiveExpression();

        if (isComparisonStart(self.peek())) {
            left = try self.makeBinary(left, try self.parseComparisonOperator(), try self.parseAdditiveExpression());
        }

        return left;
    }

    fn parseAdditiveExpression(self: *Parser) ParseError!ast.Expression {
        var left = try self.parsePrimary();

        while (true) {
            const operator: ast.BinaryOperator = if (self.matchSymbol("+"))
                .add
            else if (self.matchSymbol("-"))
                .subtract
            else
                return left;
            left = try self.makeBinary(left, operator, try self.parsePrimary());
        }
    }

    fn makeBinary(self: *Parser, left: ast.Expression, operator: ast.BinaryOperator, right: ast.Expression) ParseError!ast.Expression {
        const left_ptr = try self.allocator.create(ast.Expression);
        errdefer self.allocator.destroy(left_ptr);
        left_ptr.* = left;
        const right_ptr = try self.allocator.create(ast.Expression);
        errdefer {
            left_ptr.deinit(self.allocator);
            self.allocator.destroy(left_ptr);
            self.allocator.destroy(right_ptr);
        }
        right_ptr.* = right;
        return .{
            .binary = .{
                .left = left_ptr,
                .operator = operator,
                .right = right_ptr,
            },
        };
    }

    fn parsePrimary(self: *Parser) ParseError!ast.Expression {
        const token = self.advance() orelse return self.failEnd("expression");

        if (token.kind == .string) {
            return .{ .literal = .{ .string = try self.cloneStringLiteral(token.lexeme) } };
        }

        if (token.kind == .number) {
            if (std.mem.indexOfScalar(u8, token.lexeme, '.') != null) {
                return .{ .literal = .{ .float = std.fmt.parseFloat(f64, token.lexeme) catch {
                    return self.failToken(token, .invalid_number, "number");
                } } };
            }
            return .{ .literal = .{ .integer = std.fmt.parseInt(i64, token.lexeme, 10) catch {
                return self.failToken(token, .invalid_number, "number");
            } } };
        }

        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "*")) return .star;

        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "[")) {
            var values: std.ArrayList(f64) = .empty;
            errdefer values.deinit(self.allocator);
            while (!self.matchSymbol("]")) {
                const sign: f64 = if (self.matchSymbol("-")) -1 else 1;
                const value_token = self.advance() orelse return self.failEnd("vector value");
                if (value_token.kind != .number) return self.failToken(value_token, .unexpected_token, "vector value");
                const parsed = std.fmt.parseFloat(f64, value_token.lexeme) catch {
                    return self.failToken(value_token, .invalid_number, "vector value");
                };
                try values.append(self.allocator, sign * parsed);
                if (self.matchSymbol(",")) continue;
                try self.expectSymbol("]");
                break;
            }
            return .{ .literal = .{ .vector = try values.toOwnedSlice(self.allocator) } };
        }

        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "(")) {
            const expression = try self.parseExpression();
            try self.expectSymbol(")");
            return expression;
        }

        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "-")) {
            const value_token = self.advance() orelse return self.failEnd("number");
            if (value_token.kind != .number) return self.failToken(value_token, .unexpected_token, "number");
            if (std.mem.indexOfScalar(u8, value_token.lexeme, '.') != null) {
                return .{ .literal = .{ .float = -(std.fmt.parseFloat(f64, value_token.lexeme) catch {
                    return self.failToken(value_token, .invalid_number, "number");
                }) } };
            }
            return .{ .literal = .{ .integer = -(std.fmt.parseInt(i64, value_token.lexeme, 10) catch {
                return self.failToken(value_token, .invalid_number, "number");
            }) } };
        }

        if (isIdentifier(token)) {
            if (token.eqlIgnoreCase("NULL")) return .{ .literal = .null };
            if (token.eqlIgnoreCase("TRUE")) return .{ .literal = .{ .boolean = true } };
            if (token.eqlIgnoreCase("FALSE")) return .{ .literal = .{ .boolean = false } };

            const name = try self.cloneIdentifierToken(token);
            errdefer self.allocator.free(name);
            if (self.matchSymbol("(")) {
                var args: std.ArrayList(ast.Expression) = .empty;
                errdefer {
                    for (args.items) |arg| arg.deinit(self.allocator);
                    args.deinit(self.allocator);
                }
                while (!self.matchSymbol(")")) {
                    try args.append(self.allocator, try self.parseExpression());
                    if (self.matchSymbol(",")) continue;
                    try self.expectSymbol(")");
                    break;
                }
                return .{
                    .function_call = .{
                        .name = name,
                        .args = try args.toOwnedSlice(self.allocator),
                    },
                };
            }
            if (self.matchSymbol(".")) {
                const member_token = try self.expectIdentifierToken("qualified identifier member");
                const member = normalizedIdentifier(member_token);
                const qualified = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ name, member });
                self.allocator.free(name);
                return .{ .identifier = qualified };
            }
            return .{ .identifier = name };
        }

        return self.failToken(token, .unexpected_token, "expression");
    }

    fn parseComparisonOperator(self: *Parser) ParseError!ast.BinaryOperator {
        const token = self.advance() orelse return self.failEnd("comparison operator");
        if (std.mem.eql(u8, token.lexeme, "=")) return .equal;
        if (std.mem.eql(u8, token.lexeme, "<")) {
            if (self.matchSymbol("=")) return .less_equal;
            if (self.matchSymbol(">")) return .not_equal;
            return .less_than;
        }
        if (std.mem.eql(u8, token.lexeme, ">")) {
            if (self.matchSymbol("=")) return .greater_equal;
            return .greater_than;
        }
        if (std.mem.eql(u8, token.lexeme, "!")) {
            try self.expectSymbol("=");
            return .not_equal;
        }
        return self.failToken(token, .unexpected_token, "comparison operator");
    }

    fn isAtColumnDefinitionBoundary(self: *Parser) bool {
        const token = self.peek() orelse return true;
        return token.kind == .symbol and
            (std.mem.eql(u8, token.lexeme, ",") or std.mem.eql(u8, token.lexeme, ")"));
    }

    fn isTableIndexStart(self: *Parser) bool {
        const token = self.peek() orelse return false;
        return token.eqlIgnoreCase("PRIMARY") or
            token.eqlIgnoreCase("INDEX") or
            token.eqlIgnoreCase("KEY");
    }

    fn skipOneAttributeToken(self: *Parser) ParseError!void {
        if (self.matchSymbol("(")) {
            try self.skipBalanced(")");
            return;
        }
        _ = self.advance() orelse return;
    }

    fn skipColumnAttributes(self: *Parser) void {
        while (self.peek()) |token| {
            if (token.kind == .symbol and (std.mem.eql(u8, token.lexeme, ",") or std.mem.eql(u8, token.lexeme, ")"))) return;
            _ = self.advance();
        }
    }

    fn skipBalanced(self: *Parser, closing: []const u8) ParseError!void {
        var depth: usize = 1;
        while (self.advance()) |token| {
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "(")) {
                depth += 1;
            } else if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, closing)) {
                depth -= 1;
                if (depth == 0) return;
            }
        }
        return self.failEnd(closing);
    }

    fn isAtClauseBoundary(self: *Parser) bool {
        const token = self.peek() orelse return true;
        return token.eqlIgnoreCase("FROM") or token.eqlIgnoreCase("WHERE") or
            token.eqlIgnoreCase("ORDER") or token.eqlIgnoreCase("LIMIT") or
            token.eqlIgnoreCase("GROUP") or token.eqlIgnoreCase("HAVING") or
            std.mem.eql(u8, token.lexeme, ";");
    }

    fn expectKeyword(self: *Parser, keyword: []const u8) ParseError!void {
        const token = self.advance() orelse return self.failEnd(keyword);
        if (!token.eqlIgnoreCase(keyword)) return self.failToken(token, .unexpected_token, keyword);
    }

    fn matchKeyword(self: *Parser, keyword: []const u8) bool {
        const token = self.peek() orelse return false;
        if (!token.eqlIgnoreCase(keyword)) return false;
        self.index += 1;
        return true;
    }

    fn expectSymbol(self: *Parser, symbol: []const u8) ParseError!void {
        const token = self.advance() orelse return self.failEnd(symbol);
        if (token.kind != .symbol or !std.mem.eql(u8, token.lexeme, symbol)) {
            return self.failToken(token, .unexpected_token, symbol);
        }
    }

    fn matchSymbol(self: *Parser, symbol: []const u8) bool {
        const token = self.peek() orelse return false;
        if (token.kind != .symbol or !std.mem.eql(u8, token.lexeme, symbol)) return false;
        self.index += 1;
        return true;
    }

    fn nextIsSymbol(self: *Parser, symbol: []const u8) bool {
        const token = self.peek() orelse return false;
        return token.kind == .symbol and std.mem.eql(u8, token.lexeme, symbol);
    }

    fn expectIdentifierOwned(self: *Parser, expected: []const u8) ParseError![]const u8 {
        const token = try self.expectIdentifierToken(expected);
        return self.cloneIdentifierToken(token);
    }

    fn expectIdentifierToken(self: *Parser, expected: []const u8) ParseError!tokenizer.Token {
        const token = self.advance() orelse return self.failEnd(expected);
        if (!isIdentifier(token)) return self.failToken(token, .unexpected_token, expected);
        return token;
    }

    fn cloneIdentifierToken(self: *Parser, token: tokenizer.Token) ParseError![]const u8 {
        return self.allocator.dupe(u8, normalizedIdentifier(token));
    }

    fn cloneStringLiteral(self: *Parser, lexeme: []const u8) ParseError![]const u8 {
        if (lexeme.len < 2) return self.allocator.dupe(u8, lexeme);
        return self.allocator.dupe(u8, lexeme[1 .. lexeme.len - 1]);
    }

    fn consumeSemicolons(self: *Parser) void {
        while (self.matchSymbol(";")) {}
    }

    fn peek(self: *Parser) ?tokenizer.Token {
        if (self.index >= self.tokens.len) return null;
        return self.tokens[self.index];
    }

    fn advance(self: *Parser) ?tokenizer.Token {
        const token = self.peek() orelse return null;
        self.index += 1;
        return token;
    }

    fn failCurrent(self: *Parser, code: DiagnosticCode, expected: []const u8) ParseError {
        if (self.peek()) |token| return self.failToken(token, code, expected);
        return self.failEnd(expected);
    }

    fn failToken(self: *Parser, token: tokenizer.Token, code: DiagnosticCode, expected: []const u8) ParseError {
        self.diagnostic = .{
            .code = code,
            .offset = token.offset,
            .token = token.lexeme,
            .expected = expected,
        };
        return error.ParseFailed;
    }

    fn failEnd(self: *Parser, expected: []const u8) ParseError {
        self.diagnostic = .{
            .code = .unexpected_end,
            .offset = self.sql.len,
            .expected = expected,
        };
        return error.ParseFailed;
    }

    fn unexpected(self: *Parser, token: tokenizer.Token, expected: []const u8) Diagnostic {
        _ = self;
        return .{
            .code = .unexpected_token,
            .offset = token.offset,
            .token = token.lexeme,
            .expected = expected,
        };
    }
};

fn isIdentifier(token: tokenizer.Token) bool {
    return token.kind == .identifier;
}

fn normalizedIdentifier(token: tokenizer.Token) []const u8 {
    if (token.lexeme.len >= 2 and token.lexeme[0] == '`' and token.lexeme[token.lexeme.len - 1] == '`') {
        return token.lexeme[1 .. token.lexeme.len - 1];
    }
    return token.lexeme;
}

fn isComparisonStart(token: ?tokenizer.Token) bool {
    const actual = token orelse return false;
    if (actual.kind != .symbol) return false;
    return std.mem.eql(u8, actual.lexeme, "=") or
        std.mem.eql(u8, actual.lexeme, "<") or
        std.mem.eql(u8, actual.lexeme, ">") or
        std.mem.eql(u8, actual.lexeme, "!");
}

fn isImplicitAliasBoundary(token: tokenizer.Token) bool {
    return token.eqlIgnoreCase("FROM") or
        token.eqlIgnoreCase("WHERE") or
        token.eqlIgnoreCase("ORDER") or
        token.eqlIgnoreCase("GROUP") or
        token.eqlIgnoreCase("HAVING") or
        token.eqlIgnoreCase("LIMIT") or
        token.eqlIgnoreCase("JOIN") or
        token.eqlIgnoreCase("INNER") or
        token.eqlIgnoreCase("CROSS") or
        token.eqlIgnoreCase("LEFT") or
        token.eqlIgnoreCase("ON");
}

fn isTableAliasBoundary(token: tokenizer.Token) bool {
    return token.eqlIgnoreCase("WHERE") or
        token.eqlIgnoreCase("ORDER") or
        token.eqlIgnoreCase("GROUP") or
        token.eqlIgnoreCase("HAVING") or
        token.eqlIgnoreCase("LIMIT") or
        token.eqlIgnoreCase("JOIN") or
        token.eqlIgnoreCase("INNER") or
        token.eqlIgnoreCase("CROSS") or
        token.eqlIgnoreCase("LEFT") or
        token.eqlIgnoreCase("ON");
}

test "parser dispatches transaction statements" {
    const allocator = std.testing.allocator;
    const result = try parse(allocator, "BEGIN;");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(std.meta.Tag(ast.Statement), .begin), std.meta.activeTag(result.statement));
}

test "parser parses create table with vector column" {
    const allocator = std.testing.allocator;
    const result = try parse(allocator, "CREATE TABLE memories (id INTEGER PRIMARY KEY, embedding VECTOR(4));");
    defer result.deinit(allocator);

    const statement = result.statement.create_table;
    try std.testing.expectEqualStrings("memories", statement.name);
    try std.testing.expectEqual(@as(usize, 2), statement.columns.len);
    try std.testing.expectEqual(@as(usize, 4), statement.columns[1].column_type.vector);
}

test "parser parses mysql-style ddl metadata" {
    const allocator = std.testing.allocator;
    const create = try parse(
        allocator,
        "CREATE TABLE IF NOT EXISTS memories (id INTEGER PRIMARY KEY AUTO_INCREMENT, body TEXT NOT NULL DEFAULT 'seed', tag TEXT NULL, INDEX idx_tag (tag), KEY body_key (body));",
    );
    defer create.deinit(allocator);

    const statement = create.statement.create_table;
    try std.testing.expect(statement.if_not_exists);
    try std.testing.expectEqual(@as(usize, 3), statement.columns.len);
    try std.testing.expect(statement.columns[0].primary_key);
    try std.testing.expect(statement.columns[0].auto_increment);
    try std.testing.expect(!statement.columns[1].nullable);
    try std.testing.expectEqualStrings("seed", statement.columns[1].default_value.?.literal.string);
    try std.testing.expectEqual(@as(usize, 2), statement.indexes.len);
    try std.testing.expectEqualStrings("idx_tag", statement.indexes[0].name.?);
    try std.testing.expectEqualStrings("tag", statement.indexes[0].columns[0]);
    try std.testing.expectEqualStrings("body_key", statement.indexes[1].name.?);

    const drop = try parse(allocator, "DROP TABLE IF EXISTS memories;");
    defer drop.deinit(allocator);
    try std.testing.expect(drop.statement.drop_table.if_exists);
    try std.testing.expectEqualStrings("memories", drop.statement.drop_table.name);
}

test "parser rejects policy violations before grammar" {
    const allocator = std.testing.allocator;
    const result = try parse(allocator, "CREATE TEMPORARY TABLE stage (id INTEGER);");

    try std.testing.expectEqual(DiagnosticCode.policy_violation, result.diagnostic.code);
    try std.testing.expectEqual(policy.UnsupportedFeature.temporary_table, result.diagnostic.policy_feature.?);
}

test "parser parses insert update delete and select" {
    const allocator = std.testing.allocator;

    const insert = try parse(allocator, "INSERT INTO memories (id, embedding) VALUES (1, [0, 1, 2]);");
    defer insert.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), insert.statement.insert.columns.len);
    try std.testing.expectEqual(@as(usize, 2), insert.statement.insert.values.len);

    const update = try parse(allocator, "UPDATE memories SET body = 'hi' WHERE id = 1;");
    defer update.deinit(allocator);
    try std.testing.expect(update.statement.update.where_clause != null);

    const delete = try parse(allocator, "DELETE FROM memories WHERE id = 1;");
    defer delete.deinit(allocator);
    try std.testing.expect(delete.statement.delete.where_clause != null);

    const select = try parse(allocator, "SELECT id, l2_distance(embedding, [0, 0, 0]) FROM memories WHERE id = 1 ORDER BY id DESC LIMIT 5;");
    defer select.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), select.statement.select.projections.len);
    try std.testing.expectEqual(@as(usize, 2), select.statement.select.projection_items.len);
    try std.testing.expectEqual(@as(usize, 1), select.statement.select.order_by.len);
    try std.testing.expectEqual(@as(usize, 5), select.statement.select.limit.?);
}

test "parser parses group by and having clauses" {
    const allocator = std.testing.allocator;

    const result = try parse(
        allocator,
        "SELECT tag, COUNT(*) AS total, AVG(score) AS average_score FROM memory_scores GROUP BY tag HAVING total > 1 ORDER BY average_score DESC;",
    );
    defer result.deinit(allocator);

    const statement = result.statement.select;
    try std.testing.expectEqual(@as(usize, 1), statement.group_by.len);
    try std.testing.expectEqualStrings("tag", statement.group_by[0].identifier);
    try std.testing.expect(statement.having != null);
    try std.testing.expectEqual(ast.BinaryOperator.greater_than, statement.having.?.binary.operator);
    try std.testing.expectEqual(@as(usize, 1), statement.order_by.len);
    try std.testing.expectEqual(ast.OrderDirection.desc, statement.order_by[0].direction);
}

test "parser parses projection aliases table aliases and qualified identifiers" {
    const allocator = std.testing.allocator;

    const result = try parse(
        allocator,
        "SELECT m.id, m.body body_text, l2_distance(m.embedding, [1, 0]) AS distance FROM memories AS m WHERE m.id = 1 ORDER BY distance ASC LIMIT 5;",
    );
    defer result.deinit(allocator);

    const statement = result.statement.select;
    try std.testing.expectEqual(@as(usize, 3), statement.projection_items.len);
    try std.testing.expectEqualStrings("m.id", statement.projection_items[0].expression.identifier);
    try std.testing.expect(statement.projection_items[0].alias == null);
    try std.testing.expectEqualStrings("body_text", statement.projection_items[1].alias.?);
    try std.testing.expectEqualStrings("distance", statement.projection_items[2].alias.?);

    const parts = ast.identifierParts(statement.projection_items[0].expression.identifier);
    try std.testing.expectEqualStrings("m", parts.qualifier.?);
    try std.testing.expectEqualStrings("id", parts.name);

    const source = statement.source.?.base_table;
    try std.testing.expectEqualStrings("memories", source.name);
    try std.testing.expectEqualStrings("m", source.alias.?);
    try std.testing.expectEqualStrings("memories", statement.from.?);
}

test "parser rejects ambiguous implicit projection aliases" {
    const allocator = std.testing.allocator;

    const result = try parse(allocator, "SELECT id body FROM memories;");

    try std.testing.expectEqual(DiagnosticCode.unexpected_token, result.diagnostic.code);
    try std.testing.expectEqualStrings("body", result.diagnostic.token);
}

test "parser parses joins in CTE query sources" {
    const allocator = std.testing.allocator;

    const result = try parse(allocator,
        \\WITH ranked AS (
        \\  SELECT m.id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
        \\  FROM memories AS m
        \\  JOIN memory_tags AS t ON t.memory_id = m.id
        \\  WHERE t.name = 'project'
        \\)
        \\SELECT id, body
        \\FROM ranked
        \\WHERE distance < 1.0
        \\ORDER BY distance
        \\LIMIT 10;
    );
    defer result.deinit(allocator);

    const statement = result.statement.select;
    try std.testing.expectEqual(@as(usize, 1), statement.ctes.len);
    try std.testing.expectEqualStrings("ranked", statement.ctes[0].name);
    try std.testing.expectEqualStrings("ranked", statement.source.?.base_table.name);

    const cte_query = statement.ctes[0].query.*;
    try std.testing.expectEqual(@as(usize, 3), cte_query.projection_items.len);
    try std.testing.expectEqualStrings("distance", cte_query.projection_items[2].alias.?);

    const join = cte_query.source.?.join;
    try std.testing.expectEqual(ast.JoinType.inner, join.join_type);
    try std.testing.expectEqualStrings("memories", join.left.base_table.name);
    try std.testing.expectEqualStrings("m", join.left.base_table.alias.?);
    try std.testing.expectEqualStrings("memory_tags", join.right.base_table.name);
    try std.testing.expectEqualStrings("t", join.right.base_table.alias.?);
    try std.testing.expect(join.on != null);
    try std.testing.expectEqual(ast.BinaryOperator.equal, join.on.?.binary.operator);
}

test "parser parses derived left joins and cross joins" {
    const allocator = std.testing.allocator;

    const left_join = try parse(
        allocator,
        "SELECT d.id FROM (SELECT id FROM memories) AS d LEFT JOIN tags t ON t.id = d.id;",
    );
    defer left_join.deinit(allocator);

    const joined = left_join.statement.select.source.?.join;
    try std.testing.expectEqual(ast.JoinType.left, joined.join_type);
    try std.testing.expectEqualStrings("d", joined.left.derived_table.alias);
    try std.testing.expectEqualStrings("tags", joined.right.base_table.name);
    try std.testing.expectEqualStrings("t", joined.right.base_table.alias.?);
    try std.testing.expect(joined.on != null);
    try std.testing.expect(left_join.statement.select.from == null);

    const cross_join = try parse(allocator, "SELECT * FROM memories m CROSS JOIN tags t;");
    defer cross_join.deinit(allocator);

    const cross = cross_join.statement.select.source.?.join;
    try std.testing.expectEqual(ast.JoinType.cross, cross.join_type);
    try std.testing.expect(cross.on == null);
    try std.testing.expectEqualStrings("memories", cross.left.base_table.name);
    try std.testing.expectEqualStrings("tags", cross.right.base_table.name);
}

test "parser preserves policy first rejections for non-goal surfaces" {
    const allocator = std.testing.allocator;

    const cases = [_]struct {
        sql: []const u8,
        feature: policy.UnsupportedFeature,
    }{
        .{ .sql = "CREATE TABLE child (parent_id INTEGER REFERENCES parent(id));", .feature = .foreign_key },
        .{ .sql = "CREATE TEMP TABLE stage (id INTEGER);", .feature = .temporary_table },
        .{ .sql = "CREATE TABLE t (id INTEGER) ENGINE=InnoDB;", .feature = .storage_engine_selection },
        .{ .sql = "GRANT SELECT ON *.* TO 'agent'@'localhost';", .feature = .user_auth },
        .{ .sql = "INSTALL PLUGIN foo SONAME 'foo.so';", .feature = .plugin },
        .{ .sql = "SHOW BINLOG EVENTS;", .feature = .replication },
    };

    for (cases) |case| {
        const result = try parse(allocator, case.sql);
        try std.testing.expectEqual(DiagnosticCode.policy_violation, result.diagnostic.code);
        try std.testing.expectEqual(case.feature, result.diagnostic.policy_feature.?);
    }
}

test "parser parses view procedure and call statements" {
    const allocator = std.testing.allocator;

    const view = try parse(allocator, "CREATE VIEW recent AS SELECT * FROM memories LIMIT 10;");
    defer view.deinit(allocator);
    try std.testing.expectEqualStrings("recent", view.statement.create_view.name);
    try std.testing.expectEqualStrings("SELECT * FROM memories LIMIT 10", view.statement.create_view.body_sql);

    const procedure = try parse(
        allocator,
        "CREATE PROCEDURE remember(IN p_id INT, IN p_body TEXT) BEGIN INSERT INTO memories (id, body) VALUES (p_id, p_body); END;",
    );
    defer procedure.deinit(allocator);
    try std.testing.expectEqualStrings("remember", procedure.statement.create_procedure.name);
    try std.testing.expectEqual(@as(usize, 2), procedure.statement.create_procedure.params.len);
    try std.testing.expectEqualStrings("p_id", procedure.statement.create_procedure.params[0].name);
    try std.testing.expectEqual(ast.ColumnType.integer, procedure.statement.create_procedure.params[0].column_type);
    try std.testing.expectEqualStrings("p_body", procedure.statement.create_procedure.params[1].name);
    try std.testing.expectEqual(ast.ColumnType.text, procedure.statement.create_procedure.params[1].column_type);

    const call = try parse(allocator, "CALL remember(1, 'hi');");
    defer call.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), call.statement.call.args.len);

    const expression = try parseExpressionOnly(allocator, "attempts + 1");
    defer expression.deinit(allocator);
    try std.testing.expectEqual(ast.BinaryOperator.add, expression.expression.binary.operator);
}

test "parser accepts negative scalar and vector numbers" {
    const allocator = std.testing.allocator;

    const result = try parse(allocator, "INSERT INTO memories VALUES (-1, [-0.25, 1.5]);");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(i64, -1), result.statement.insert.values[0].literal.integer);
    try std.testing.expectEqual(@as(f64, -0.25), result.statement.insert.values[1].literal.vector[0]);
}

test "parser gives comparisons higher precedence than AND" {
    const allocator = std.testing.allocator;

    const result = try parse(allocator, "SELECT * FROM memories WHERE id = 1 AND body = 'hi';");
    defer result.deinit(allocator);

    const where_clause = result.statement.select.where_clause.?.binary;
    try std.testing.expectEqual(ast.BinaryOperator.and_op, where_clause.operator);
    try std.testing.expectEqual(ast.BinaryOperator.equal, where_clause.left.*.binary.operator);
    try std.testing.expectEqual(ast.BinaryOperator.equal, where_clause.right.*.binary.operator);
}
