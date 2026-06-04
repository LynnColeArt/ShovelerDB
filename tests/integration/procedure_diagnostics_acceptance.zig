const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

fn execOk(allocator: std.mem.Allocator, db: *executor.Database, session: *executor.Session, sql: []const u8) !void {
    var result = try exec(db, session, sql);
    result.deinit(allocator);
}

fn createBaseDb(allocator: std.mem.Allocator) !struct {
    db: executor.Database,
    session: executor.Session,
} {
    var db = executor.Database.init(allocator);
    errdefer db.deinit();
    var session = executor.Session.init(allocator);
    errdefer session.deinit();

    try execOk(allocator, &db, &session, "CREATE TABLE memories (id INTEGER, body TEXT);");
    return .{ .db = db, .session = session };
}

fn expectDiagnostic(err: anyerror, expected: executor.DiagnosticKind) !void {
    try std.testing.expectEqual(expected, executor.diagnosticFromError(err).?);
}

fn expectRejectedCreateLeavesNameReusable(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    create_sql: []const u8,
    procedure_name: []const u8,
    expected_error: anyerror,
    expected_diagnostic: executor.DiagnosticKind,
) !void {
    try std.testing.expectError(expected_error, exec(db, session, create_sql));
    try expectDiagnostic(expected_error, expected_diagnostic);

    const call_sql = try std.fmt.allocPrint(allocator, "CALL {s}();", .{procedure_name});
    defer allocator.free(call_sql);
    try std.testing.expectError(error.UnknownObject, exec(db, session, call_sql));

    const replacement_sql = try std.fmt.allocPrint(
        allocator,
        "CREATE PROCEDURE {s}() BEGIN SELECT * FROM memories; END;",
        .{procedure_name},
    );
    defer allocator.free(replacement_sql);
    try execOk(allocator, db, session, replacement_sql);

    const drop_sql = try std.fmt.allocPrint(allocator, "DROP PROCEDURE {s};", .{procedure_name});
    defer allocator.free(drop_sql);
    try execOk(allocator, db, session, drop_sql);
}

test "procedure body control flow covers variables if and bounded while" {
    const allocator = std.testing.allocator;
    var fixture = try createBaseDb(allocator);
    defer fixture.db.deinit();
    defer fixture.session.deinit();

    try execOk(allocator, &fixture.db, &fixture.session,
        \\CREATE PROCEDURE remember_many(IN p_limit INT)
        \\BEGIN
        \\  DECLARE current_id INT DEFAULT 1;
        \\  IF p_limit > 0 THEN
        \\    WHILE current_id <= p_limit DO
        \\      INSERT INTO memories (id, body) VALUES (current_id, 'from loop');
        \\      SET current_id = current_id + 1;
        \\    END WHILE;
        \\  END IF;
        \\END;
    );

    try execOk(allocator, &fixture.db, &fixture.session, "BEGIN;");
    var result = try exec(&fixture.db, &fixture.session, "CALL remember_many(3);");
    try std.testing.expectEqual(@as(usize, 3), result.mutation_count);
    result.deinit(allocator);

    result = try exec(&fixture.db, &fixture.session, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 3), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.result_set.rows[2].values[0].integer);
    try std.testing.expectEqualStrings("from loop", result.result_set.rows[2].values[1].text);
    result.deinit(allocator);

    try execOk(allocator, &fixture.db, &fixture.session, "ROLLBACK;");
}

test "procedure loop cap reports stable unsupported procedure diagnostic" {
    const allocator = std.testing.allocator;
    var fixture = try createBaseDb(allocator);
    defer fixture.db.deinit();
    defer fixture.session.deinit();

    try execOk(allocator, &fixture.db, &fixture.session,
        \\CREATE PROCEDURE spin()
        \\BEGIN
        \\  DECLARE attempts INT DEFAULT 0;
        \\  WHILE attempts <= 10000 DO
        \\    SET attempts = attempts + 1;
        \\  END WHILE;
        \\END;
    );

    try std.testing.expectError(error.UnsupportedProcedure, exec(&fixture.db, &fixture.session, "CALL spin();"));
    try expectDiagnostic(error.UnsupportedProcedure, .unsupported_procedure);
}

test "unsupported procedure creates reject without partial catalog mutation" {
    const allocator = std.testing.allocator;
    var fixture = try createBaseDb(allocator);
    defer fixture.db.deinit();
    defer fixture.session.deinit();

    const unsupported_procedures = [_]struct {
        name: []const u8,
        sql: []const u8,
    }{
        .{
            .name = "bad_cursor",
            .sql = "CREATE PROCEDURE bad_cursor() BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END;",
        },
        .{
            .name = "bad_handler",
            .sql = "CREATE PROCEDURE bad_handler() BEGIN DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET current_id = 1; END;",
        },
        .{
            .name = "bad_dynamic",
            .sql = "CREATE PROCEDURE bad_dynamic() BEGIN PREPARE stmt FROM 'SELECT 1'; END;",
        },
        .{
            .name = "bad_recursion",
            .sql = "CREATE PROCEDURE bad_recursion() BEGIN CALL bad_recursion(); END;",
        },
        .{
            .name = "bad_diagnostics",
            .sql = "CREATE PROCEDURE bad_diagnostics() BEGIN GET DIAGNOSTICS CONDITION 1 current_id = RETURNED_SQLSTATE; END;",
        },
        .{
            .name = "bad_signal",
            .sql = "CREATE PROCEDURE bad_signal() BEGIN SIGNAL SQLSTATE '45000'; END;",
        },
    };

    for (unsupported_procedures) |case| {
        try expectRejectedCreateLeavesNameReusable(
            allocator,
            &fixture.db,
            &fixture.session,
            case.sql,
            case.name,
            error.UnsupportedProcedure,
            .unsupported_procedure,
        );
    }
}

test "unsupported stored-program statement shapes keep parse diagnostics stable" {
    const allocator = std.testing.allocator;
    var fixture = try createBaseDb(allocator);
    defer fixture.db.deinit();
    defer fixture.session.deinit();

    const rejected_shapes = [_]struct {
        name: []const u8,
        sql: []const u8,
    }{
        .{
            .name = "bad_out",
            .sql = "CREATE PROCEDURE bad_out(OUT p_id INT) BEGIN SELECT * FROM memories; END;",
        },
        .{
            .name = "bad_inout",
            .sql = "CREATE PROCEDURE bad_inout(INOUT p_id INT) BEGIN SELECT * FROM memories; END;",
        },
        .{
            .name = "bad_function",
            .sql = "CREATE FUNCTION bad_function() RETURNS INT RETURN 1;",
        },
        .{
            .name = "bad_package",
            .sql = "CREATE PACKAGE bad_package AS PROCEDURE remember(); END;",
        },
    };

    for (rejected_shapes) |case| {
        try expectRejectedCreateLeavesNameReusable(
            allocator,
            &fixture.db,
            &fixture.session,
            case.sql,
            case.name,
            error.ParseDiagnostic,
            .parse_diagnostic,
        );
    }
}
