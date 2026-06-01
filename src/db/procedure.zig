const std = @import("std");

pub const ProcedureError = error{
    DuplicateObject,
    UnknownObject,
    UnsupportedProcedure,
};

pub const DiagnosticKind = enum {
    duplicate_object,
    unknown_object,
    unsupported_procedure,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.DuplicateObject => .duplicate_object,
        error.UnknownObject => .unknown_object,
        error.UnsupportedProcedure => .unsupported_procedure,
        else => null,
    };
}

pub const StoredProcedure = struct {
    name: []u8,
    body_sql: []u8,

    pub fn deinit(self: *StoredProcedure, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.body_sql);
        self.* = undefined;
    }
};

pub const ProcedureRegistry = struct {
    allocator: std.mem.Allocator,
    procedures: std.ArrayList(StoredProcedure) = .empty,

    pub fn init(allocator: std.mem.Allocator) ProcedureRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ProcedureRegistry) void {
        for (self.procedures.items) |*stored| stored.deinit(self.allocator);
        self.procedures.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn create(self: *ProcedureRegistry, name: []const u8, body_sql: []const u8) !void {
        if (self.findIndex(name) != null) return error.DuplicateObject;

        const inner = supportedSingleStatementBody(body_sql) orelse return error.UnsupportedProcedure;
        var stored = StoredProcedure{
            .name = try self.allocator.dupe(u8, name),
            .body_sql = undefined,
        };
        errdefer self.allocator.free(stored.name);

        stored.body_sql = try self.allocator.dupe(u8, inner);
        errdefer self.allocator.free(stored.body_sql);

        try self.procedures.append(self.allocator, stored);
    }

    pub fn drop(self: *ProcedureRegistry, name: []const u8) ProcedureError!void {
        const index = self.findIndex(name) orelse return error.UnknownObject;
        var stored = self.procedures.orderedRemove(index);
        stored.deinit(self.allocator);
    }

    pub fn get(self: *const ProcedureRegistry, name: []const u8) ?*const StoredProcedure {
        const index = self.findIndex(name) orelse return null;
        return &self.procedures.items[index];
    }

    fn findIndex(self: *const ProcedureRegistry, name: []const u8) ?usize {
        for (self.procedures.items, 0..) |stored, index| {
            if (std.ascii.eqlIgnoreCase(stored.name, name)) return index;
        }
        return null;
    }
};

fn supportedSingleStatementBody(body_sql: []const u8) ?[]const u8 {
    const trimmed = trim(body_sql);
    if (!startsWithWord(trimmed, "BEGIN")) return null;
    if (!endsWithWord(trimmed, "END")) return null;
    if (containsForbiddenControlToken(trimmed)) return null;

    var inner = trim(trimmed["BEGIN".len .. trimmed.len - "END".len]);
    if (inner.len == 0) return null;
    if (std.mem.endsWith(u8, inner, ";")) {
        inner = trim(inner[0 .. inner.len - 1]);
    }
    if (inner.len == 0) return null;
    if (std.mem.indexOfScalar(u8, inner, ';') != null) return null;
    return inner;
}

fn containsForbiddenControlToken(input: []const u8) bool {
    const forbidden = [_][]const u8{
        "DECLARE",
        "IF",
        "LOOP",
        "WHILE",
        "REPEAT",
        "LEAVE",
        "SET",
    };

    var index: usize = 0;
    while (index < input.len) {
        while (index < input.len and !isWordStart(input[index])) index += 1;
        const start = index;
        while (index < input.len and isWordContinue(input[index])) index += 1;
        if (start == index) continue;

        const word = input[start..index];
        for (forbidden) |candidate| {
            if (std.ascii.eqlIgnoreCase(word, candidate)) return true;
        }
    }
    return false;
}

fn startsWithWord(input: []const u8, word: []const u8) bool {
    if (input.len < word.len) return false;
    if (!std.ascii.eqlIgnoreCase(input[0..word.len], word)) return false;
    return input.len == word.len or !isWordContinue(input[word.len]);
}

fn endsWithWord(input: []const u8, word: []const u8) bool {
    if (input.len < word.len) return false;
    const start = input.len - word.len;
    if (!std.ascii.eqlIgnoreCase(input[start..], word)) return false;
    return start == 0 or !isWordContinue(input[start - 1]);
}

fn isWordStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isWordContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn trim(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

test "procedure registry stores a constrained single statement body" {
    const allocator = std.testing.allocator;

    var registry = ProcedureRegistry.init(allocator);
    defer registry.deinit();

    try registry.create("remember", "BEGIN INSERT INTO memories VALUES (1, 'hi'); END");
    try std.testing.expectEqualStrings(
        "INSERT INTO memories VALUES (1, 'hi')",
        registry.get("REMEMBER").?.body_sql,
    );

    try std.testing.expectError(
        error.DuplicateObject,
        registry.create("remember", "BEGIN SELECT * FROM memories; END"),
    );

    try registry.drop("remember");
    try std.testing.expect(registry.get("remember") == null);
    try std.testing.expectError(error.UnknownObject, registry.drop("remember"));
}

test "procedure registry rejects unsupported control flow and multi statement bodies" {
    const allocator = std.testing.allocator;

    var registry = ProcedureRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expectError(
        error.UnsupportedProcedure,
        registry.create("branchy", "BEGIN IF TRUE THEN SELECT 1; END IF; END"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        registry.create("multi", "BEGIN SELECT 1; SELECT 2; END"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        registry.create("bare", "SELECT 1"),
    );
}
