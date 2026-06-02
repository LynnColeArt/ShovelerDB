const std = @import("std");
const ast = @import("ast.zig");
const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");

const BodyParseError = error{
    OutOfMemory,
    UnsupportedProcedure,
};

pub const Body = struct {
    statements: []Statement = &.{},

    pub fn deinit(self: *Body, allocator: std.mem.Allocator) void {
        for (self.statements) |*statement| statement.deinit(allocator);
        if (self.statements.len > 0) allocator.free(self.statements);
        self.* = undefined;
    }
};

pub const Statement = union(enum) {
    declare_var: DeclareVar,
    set_var: SetVar,
    sql: SqlStatement,
    if_statement: IfStatement,
    while_statement: WhileStatement,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .declare_var => |*statement| statement.deinit(allocator),
            .set_var => |*statement| statement.deinit(allocator),
            .sql => |*statement| statement.deinit(allocator),
            .if_statement => |*statement| statement.deinit(allocator),
            .while_statement => |*statement| statement.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const DeclareVar = struct {
    name: []const u8,
    default_value: ?ast.Expression = null,

    pub fn deinit(self: *DeclareVar, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.default_value) |default| default.deinit(allocator);
        self.* = undefined;
    }
};

pub const SetVar = struct {
    name: []const u8,
    value: ast.Expression,

    pub fn deinit(self: *SetVar, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const SqlStatement = struct {
    statement: ast.Statement,

    pub fn deinit(self: *SqlStatement, allocator: std.mem.Allocator) void {
        self.statement.deinit(allocator);
        self.* = undefined;
    }
};

pub const IfStatement = struct {
    condition: ast.Expression,
    then_body: Body,
    else_body: Body = .{},

    pub fn deinit(self: *IfStatement, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
        self.then_body.deinit(allocator);
        if (self.else_body.statements.len > 0) self.else_body.deinit(allocator);
        self.* = undefined;
    }
};

pub const WhileStatement = struct {
    condition: ast.Expression,
    body: Body,

    pub fn deinit(self: *WhileStatement, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

pub fn parse(allocator: std.mem.Allocator, body_sql: []const u8) BodyParseError!Body {
    var body_parser = try BodyParser.init(allocator, body_sql);
    defer body_parser.deinit();
    return body_parser.parseBody();
}

const StopSet = struct {
    else_keyword: bool = false,
    end_keyword: bool = false,
};

const BodyParser = struct {
    allocator: std.mem.Allocator,
    sql: []const u8,
    tokens: []tokenizer.Token,
    index: usize = 0,

    fn init(allocator: std.mem.Allocator, sql: []const u8) !BodyParser {
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

    fn deinit(self: *BodyParser) void {
        self.allocator.free(self.tokens);
    }

    fn parseBody(self: *BodyParser) BodyParseError!Body {
        try self.expectKeyword("BEGIN");
        var body = try self.parseStatementsUntil(.{ .end_keyword = true });
        errdefer body.deinit(self.allocator);
        try self.expectKeyword("END");
        while (self.matchSymbol(";")) {}
        if (self.peek() != null) return error.UnsupportedProcedure;
        return body;
    }

    fn parseStatementsUntil(self: *BodyParser, stop: StopSet) BodyParseError!Body {
        var statements: std.ArrayList(Statement) = .empty;
        errdefer {
            for (statements.items) |*statement| statement.deinit(self.allocator);
            statements.deinit(self.allocator);
        }

        while (self.peek()) |token| {
            if (stop.else_keyword and token.eqlIgnoreCase("ELSE")) break;
            if (stop.end_keyword and token.eqlIgnoreCase("END")) break;
            try statements.append(self.allocator, try self.parseStatement());
        }

        return .{ .statements = try statements.toOwnedSlice(self.allocator) };
    }

    fn parseStatement(self: *BodyParser) BodyParseError!Statement {
        const token = self.peek() orelse return error.UnsupportedProcedure;
        if (token.eqlIgnoreCase("DECLARE")) {
            _ = self.advance();
            return .{ .declare_var = try self.parseDeclare() };
        }
        if (token.eqlIgnoreCase("SET")) {
            _ = self.advance();
            return .{ .set_var = try self.parseSet() };
        }
        if (token.eqlIgnoreCase("IF")) {
            _ = self.advance();
            return .{ .if_statement = try self.parseIf() };
        }
        if (token.eqlIgnoreCase("WHILE")) {
            _ = self.advance();
            return .{ .while_statement = try self.parseWhile() };
        }
        if (isUnsupportedStoredProgramToken(token)) return error.UnsupportedProcedure;
        return .{ .sql = try self.parseSqlStatement() };
    }

    fn parseDeclare(self: *BodyParser) BodyParseError!DeclareVar {
        var name: ?[]const u8 = try self.expectIdentifierOwned("variable name");
        errdefer if (name) |owned| self.allocator.free(owned);

        var default_value: ?ast.Expression = null;
        errdefer if (default_value) |default| default.deinit(self.allocator);

        while (self.peek()) |token| {
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, ";")) {
                _ = self.advance();
                return .{ .name = takeName(&name), .default_value = null };
            }
            if (token.eqlIgnoreCase("CURSOR") or token.eqlIgnoreCase("HANDLER") or token.eqlIgnoreCase("CONDITION")) {
                return error.UnsupportedProcedure;
            }
            if (token.eqlIgnoreCase("DEFAULT")) {
                _ = self.advance();
                default_value = try self.parseExpressionUntilSemicolon();
                return .{ .name = takeName(&name), .default_value = takeExpression(&default_value) };
            }
            _ = self.advance();
        }

        return error.UnsupportedProcedure;
    }

    fn parseSet(self: *BodyParser) BodyParseError!SetVar {
        var name: ?[]const u8 = try self.expectIdentifierOwned("variable name");
        errdefer if (name) |owned| self.allocator.free(owned);
        try self.expectSymbol("=");

        var expression: ?ast.Expression = try self.parseExpressionUntilSemicolon();
        errdefer if (expression) |value| value.deinit(self.allocator);

        return .{ .name = takeName(&name), .value = takeExpression(&expression) };
    }

    fn parseIf(self: *BodyParser) BodyParseError!IfStatement {
        var condition: ?ast.Expression = try self.parseExpressionUntilKeyword("THEN");
        errdefer if (condition) |value| value.deinit(self.allocator);

        var then_body = try self.parseStatementsUntil(.{ .else_keyword = true, .end_keyword = true });
        errdefer then_body.deinit(self.allocator);

        var else_body = Body{};
        errdefer if (else_body.statements.len > 0) else_body.deinit(self.allocator);
        if (self.matchKeyword("ELSE")) {
            else_body = try self.parseStatementsUntil(.{ .end_keyword = true });
        }

        try self.expectKeyword("END");
        try self.expectKeyword("IF");
        try self.expectSymbol(";");

        return .{
            .condition = takeExpression(&condition),
            .then_body = takeBody(&then_body),
            .else_body = takeBody(&else_body),
        };
    }

    fn parseWhile(self: *BodyParser) BodyParseError!WhileStatement {
        var condition: ?ast.Expression = try self.parseExpressionUntilKeyword("DO");
        errdefer if (condition) |value| value.deinit(self.allocator);

        var body = try self.parseStatementsUntil(.{ .end_keyword = true });
        errdefer body.deinit(self.allocator);

        try self.expectKeyword("END");
        try self.expectKeyword("WHILE");
        try self.expectSymbol(";");

        return .{
            .condition = takeExpression(&condition),
            .body = takeBody(&body),
        };
    }

    fn parseSqlStatement(self: *BodyParser) BodyParseError!SqlStatement {
        const statement_sql = try self.collectUntilSemicolon();
        var parsed = try parser.parse(self.allocator, statement_sql);
        errdefer parsed.deinit(self.allocator);

        const statement = switch (parsed) {
            .diagnostic => return error.UnsupportedProcedure,
            .statement => |statement| statement,
        };

        switch (statement) {
            .insert, .update, .delete, .select => {},
            else => {
                var owned = statement;
                owned.deinit(self.allocator);
                return error.UnsupportedProcedure;
            },
        }

        parsed = .{ .diagnostic = .{ .code = .unexpected_end, .offset = 0 } };
        return .{ .statement = statement };
    }

    fn parseExpressionUntilSemicolon(self: *BodyParser) BodyParseError!ast.Expression {
        return self.parseExpressionSlice(try self.collectUntilSemicolon());
    }

    fn parseExpressionUntilKeyword(self: *BodyParser, keyword: []const u8) BodyParseError!ast.Expression {
        return self.parseExpressionSlice(try self.collectUntilKeyword(keyword));
    }

    fn parseExpressionSlice(self: *BodyParser, expression_sql: []const u8) BodyParseError!ast.Expression {
        if (expression_sql.len == 0) return error.UnsupportedProcedure;
        var result = try parser.parseExpressionOnly(self.allocator, expression_sql);
        errdefer result.deinit(self.allocator);

        return switch (result) {
            .diagnostic => error.UnsupportedProcedure,
            .expression => |expression| blk: {
                result = .{ .diagnostic = .{ .code = .unexpected_end, .offset = 0 } };
                break :blk expression;
            },
        };
    }

    fn collectUntilSemicolon(self: *BodyParser) BodyParseError![]const u8 {
        const first = self.peek() orelse return error.UnsupportedProcedure;
        const start = first.offset;
        var depth: usize = 0;

        while (self.advance()) |token| {
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "(")) {
                depth += 1;
            } else if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, ")")) {
                if (depth > 0) depth -= 1;
            } else if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, ";") and depth == 0) {
                return trim(self.sql[start..token.offset]);
            }
        }

        return error.UnsupportedProcedure;
    }

    fn collectUntilKeyword(self: *BodyParser, keyword: []const u8) BodyParseError![]const u8 {
        const first = self.peek() orelse return error.UnsupportedProcedure;
        const start = first.offset;
        var depth: usize = 0;

        while (self.peek()) |token| {
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "(")) {
                depth += 1;
            } else if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, ")")) {
                if (depth > 0) depth -= 1;
            } else if (depth == 0 and token.eqlIgnoreCase(keyword)) {
                const expression_sql = trim(self.sql[start..token.offset]);
                try self.expectKeyword(keyword);
                return expression_sql;
            }
            _ = self.advance();
        }

        return error.UnsupportedProcedure;
    }

    fn expectKeyword(self: *BodyParser, keyword: []const u8) BodyParseError!void {
        const token = self.advance() orelse return error.UnsupportedProcedure;
        if (!token.eqlIgnoreCase(keyword)) return error.UnsupportedProcedure;
    }

    fn matchKeyword(self: *BodyParser, keyword: []const u8) bool {
        const token = self.peek() orelse return false;
        if (!token.eqlIgnoreCase(keyword)) return false;
        self.index += 1;
        return true;
    }

    fn expectSymbol(self: *BodyParser, symbol: []const u8) BodyParseError!void {
        const token = self.advance() orelse return error.UnsupportedProcedure;
        if (token.kind != .symbol or !std.mem.eql(u8, token.lexeme, symbol)) return error.UnsupportedProcedure;
    }

    fn matchSymbol(self: *BodyParser, symbol: []const u8) bool {
        const token = self.peek() orelse return false;
        if (token.kind != .symbol or !std.mem.eql(u8, token.lexeme, symbol)) return false;
        self.index += 1;
        return true;
    }

    fn expectIdentifierOwned(self: *BodyParser, expected: []const u8) BodyParseError![]const u8 {
        _ = expected;
        const token = self.advance() orelse return error.UnsupportedProcedure;
        if (token.kind != .identifier) return error.UnsupportedProcedure;
        return self.allocator.dupe(u8, normalizedIdentifier(token));
    }

    fn peek(self: *const BodyParser) ?tokenizer.Token {
        if (self.index >= self.tokens.len) return null;
        return self.tokens[self.index];
    }

    fn advance(self: *BodyParser) ?tokenizer.Token {
        const token = self.peek() orelse return null;
        self.index += 1;
        return token;
    }
};

fn takeName(name: *?[]const u8) []const u8 {
    const value = name.*.?;
    name.* = null;
    return value;
}

fn takeExpression(expression: *?ast.Expression) ast.Expression {
    const value = expression.*.?;
    expression.* = null;
    return value;
}

fn takeBody(body: *Body) Body {
    const value = body.*;
    body.* = .{};
    return value;
}

fn isUnsupportedStoredProgramToken(token: tokenizer.Token) bool {
    return token.eqlIgnoreCase("CURSOR") or
        token.eqlIgnoreCase("HANDLER") or
        token.eqlIgnoreCase("PREPARE") or
        token.eqlIgnoreCase("EXECUTE") or
        token.eqlIgnoreCase("DEALLOCATE") or
        token.eqlIgnoreCase("OPEN") or
        token.eqlIgnoreCase("FETCH") or
        token.eqlIgnoreCase("CLOSE") or
        token.eqlIgnoreCase("LEAVE") or
        token.eqlIgnoreCase("ITERATE") or
        token.eqlIgnoreCase("REPEAT") or
        token.eqlIgnoreCase("LOOP") or
        token.eqlIgnoreCase("CASE") or
        token.eqlIgnoreCase("SIGNAL") or
        token.eqlIgnoreCase("RESIGNAL") or
        token.eqlIgnoreCase("RETURN");
}

fn normalizedIdentifier(token: tokenizer.Token) []const u8 {
    if (token.lexeme.len >= 2 and token.lexeme[0] == '`' and token.lexeme[token.lexeme.len - 1] == '`') {
        return token.lexeme[1 .. token.lexeme.len - 1];
    }
    return token.lexeme;
}

fn trim(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

test "procedure body parses variables control flow and SQL statements" {
    const allocator = std.testing.allocator;

    var body = try parse(allocator,
        \\BEGIN
        \\  DECLARE attempts INT DEFAULT 0;
        \\  IF p_id > 0 THEN
        \\    WHILE attempts < 1 DO
        \\      INSERT INTO memories (id, body) VALUES (p_id, p_body);
        \\      SET attempts = attempts + 1;
        \\    END WHILE;
        \\  END IF;
        \\END
    );
    defer body.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), body.statements.len);
    try std.testing.expectEqualStrings("attempts", body.statements[0].declare_var.name);
    try std.testing.expectEqual(@as(i64, 0), body.statements[0].declare_var.default_value.?.literal.integer);

    const branch = body.statements[1].if_statement;
    try std.testing.expectEqual(ast.BinaryOperator.greater_than, branch.condition.binary.operator);
    try std.testing.expectEqual(@as(usize, 1), branch.then_body.statements.len);

    const loop = branch.then_body.statements[0].while_statement;
    try std.testing.expectEqual(ast.BinaryOperator.less_than, loop.condition.binary.operator);
    try std.testing.expectEqual(@as(usize, 2), loop.body.statements.len);
    try std.testing.expectEqual(@as(std.meta.Tag(ast.Statement), .insert), std.meta.activeTag(loop.body.statements[0].sql.statement));
    try std.testing.expectEqual(ast.BinaryOperator.add, loop.body.statements[1].set_var.value.binary.operator);
}

test "procedure body rejects unsupported stored-program surfaces" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(
        error.UnsupportedProcedure,
        parse(allocator, "BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        parse(allocator, "BEGIN PREPARE stmt FROM 'SELECT 1'; END"),
    );
}
