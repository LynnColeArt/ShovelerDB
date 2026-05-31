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
        self.index += 1;
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            self.index += 1;

            if (c == '\\' and self.index < self.input.len) {
                self.index += 1;
                continue;
            }

            if (c == quote) {
                if (self.index < self.input.len and self.input[self.index] == quote) {
                    self.index += 1;
                    continue;
                }
                break;
            }
        }

        return .{
            .kind = if (quote == '`') .identifier else .string,
            .lexeme = self.input[start..self.index],
            .offset = start,
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

