const std = @import("std");

pub const TokenKind = enum {
    identifier,
    number,
    string,
    symbol,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    offset: usize,
    terminated: bool = true,

    pub fn eqlIgnoreCase(self: Token, expected: []const u8) bool {
        return self.kind == .identifier and std.ascii.eqlIgnoreCase(self.lexeme, expected);
    }
};

pub const Tokenizer = struct {
    input: []const u8,
    index: usize = 0,

    pub fn init(input: []const u8) Tokenizer {
        return .{ .input = input };
    }

    pub fn next(self: *Tokenizer) ?Token {
        self.skipTrivia();
        if (self.index >= self.input.len) return null;

        const start = self.index;
        const c = self.input[self.index];

        if (isIdentifierStart(c)) {
            self.index += 1;
            while (self.index < self.input.len and isIdentifierContinue(self.input[self.index])) {
                self.index += 1;
            }
            return .{
                .kind = .identifier,
                .lexeme = self.input[start..self.index],
                .offset = start,
            };
        }

        if (std.ascii.isDigit(c)) {
            self.index += 1;
            while (self.index < self.input.len and isNumberContinue(self.input[self.index])) {
                self.index += 1;
            }
            return .{
                .kind = .number,
                .lexeme = self.input[start..self.index],
                .offset = start,
            };
        }

        if (c == '\'' or c == '"' or c == '`') {
            return self.readQuoted(c, start);
        }

        self.index += 1;
        return .{
            .kind = .symbol,
            .lexeme = self.input[start..self.index],
            .offset = start,
        };
    }

    fn skipTrivia(self: *Tokenizer) void {
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            if (std.ascii.isWhitespace(c)) {
                self.index += 1;
                continue;
            }

            if (c == '#') {
                self.skipLineComment();
                continue;
            }

            if (c == '-' and self.index + 1 < self.input.len and self.input[self.index + 1] == '-') {
                self.index += 2;
                self.skipLineComment();
                continue;
            }

            if (c == '/' and self.index + 1 < self.input.len and self.input[self.index + 1] == '*') {
                self.index += 2;
                self.skipBlockComment();
                continue;
            }

            break;
        }
    }

    fn skipLineComment(self: *Tokenizer) void {
        while (self.index < self.input.len and self.input[self.index] != '\n') {
            self.index += 1;
        }
    }

    fn skipBlockComment(self: *Tokenizer) void {
        while (self.index + 1 < self.input.len) {
            if (self.input[self.index] == '*' and self.input[self.index + 1] == '/') {
                self.index += 2;
                return;
            }
            self.index += 1;
        }
        self.index = self.input.len;
    }

    fn readQuoted(self: *Tokenizer, quote: u8, start: usize) Token {
        var terminated = false;
        self.index += 1;
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            self.index += 1;

            if (c == '\\' and quote != '\'' and self.index < self.input.len) {
                self.index += 1;
                continue;
            }

            if (c == quote) {
                if (self.index < self.input.len and self.input[self.index] == quote) {
                    self.index += 1;
                    continue;
                }
                terminated = true;
                break;
            }
        }

        return .{
            .kind = if (quote == '`') .identifier else .string,
            .lexeme = self.input[start..self.index],
            .offset = start,
            .terminated = terminated,
        };
    }
};

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
}

fn isNumberContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_';
}

test "tokenizer ignores comments and quoted strings for policy consumers" {
    var tokenizer = Tokenizer.init(
        \\-- CREATE TEMPORARY TABLE ignored_comment
        \\CREATE TABLE memories (body TEXT DEFAULT 'foreign key');
    );

    try std.testing.expect((tokenizer.next() orelse return error.MissingToken).eqlIgnoreCase("CREATE"));
    try std.testing.expect((tokenizer.next() orelse return error.MissingToken).eqlIgnoreCase("TABLE"));
    try std.testing.expect((tokenizer.next() orelse return error.MissingToken).eqlIgnoreCase("memories"));
}

test "tokenizer preserves offsets" {
    var tokenizer = Tokenizer.init("  SELECT 1");
    const token = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expectEqual(@as(usize, 2), token.offset);
    try std.testing.expect(token.eqlIgnoreCase("select"));
}

test "single-quoted trailing backslash is ordinary data" {
    try expectLiteralBoundary("'tail\\' NEXT", "'tail\\'", "NEXT");
}

test "single-quoted hostile data keeps a doubled apostrophe inside" {
    try expectLiteralBoundary("'\\'' OR 1=1 --' NEXT", "'\\'' OR 1=1 --'", "NEXT");
}

test "single-quoted raw backslash boundary closes before SQL-looking suffix" {
    try expectLiteralBoundary("'\\' OR 1=1 --", "'\\'", "OR");
}

test "incomplete single-quoted literals retain explicit unterminated evidence" {
    const cases = [_][]const u8{
        &.{0x27},
        &.{ 0x27, 0x61, 0x62, 0x63 },
        &.{ 0x27, 0x61, 0x5c },
    };

    for (cases) |source| {
        var tokenizer = Tokenizer.init(source);
        const token = tokenizer.next() orelse return error.MissingToken;
        try std.testing.expectEqual(TokenKind.string, token.kind);
        try std.testing.expectEqual(@as(usize, 0), token.offset);
        try std.testing.expectEqualSlices(u8, source, token.lexeme);
        try std.testing.expect(!token.terminated);
    }
}

test "doubled apostrophe pair at EOF is explicitly unterminated" {
    const source = [_]u8{ 0x27, 0x27, 0x27 };
    var tokenizer = Tokenizer.init(&source);
    const token = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expectEqual(TokenKind.string, token.kind);
    try std.testing.expectEqual(@as(usize, 0), token.offset);
    try std.testing.expectEqualSlices(u8, &source, token.lexeme);
    try std.testing.expect(!token.terminated);
}

test "single-quoted doubled apostrophes remain in the borrowed lexeme" {
    var tokenizer = Tokenizer.init("  'O''Reilly' tail");
    const literal = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expectEqual(TokenKind.string, literal.kind);
    try std.testing.expectEqual(@as(usize, 2), literal.offset);
    try std.testing.expectEqualStrings("'O''Reilly'", literal.lexeme);

    const tail = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expect(tail.eqlIgnoreCase("tail"));
}

test "double-quoted strings and backtick identifiers retain their boundaries" {
    var double_quoted = Tokenizer.init("\"a\\\"b\" tail");
    const string = double_quoted.next() orelse return error.MissingToken;
    try std.testing.expectEqual(TokenKind.string, string.kind);
    try std.testing.expectEqualStrings("\"a\\\"b\"", string.lexeme);
    try std.testing.expect(string.terminated);
    try std.testing.expect((double_quoted.next() orelse return error.MissingToken).eqlIgnoreCase("tail"));

    var backtick_quoted = Tokenizer.init("`a\\`b` tail");
    const identifier = backtick_quoted.next() orelse return error.MissingToken;
    try std.testing.expectEqual(TokenKind.identifier, identifier.kind);
    try std.testing.expectEqualStrings("`a\\`b`", identifier.lexeme);
    try std.testing.expect(identifier.terminated);
    try std.testing.expect((backtick_quoted.next() orelse return error.MissingToken).eqlIgnoreCase("tail"));
}

fn expectLiteralBoundary(source: []const u8, expected_literal: []const u8, expected_next: []const u8) !void {
    var tokenizer = Tokenizer.init(source);
    const literal = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expectEqual(TokenKind.string, literal.kind);
    try std.testing.expectEqual(@as(usize, 0), literal.offset);
    try std.testing.expectEqualStrings(expected_literal, literal.lexeme);
    try std.testing.expect(literal.terminated);

    const next = tokenizer.next() orelse return error.MissingToken;
    try std.testing.expectEqualStrings(expected_next, next.lexeme);
}
