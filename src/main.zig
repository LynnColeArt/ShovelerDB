const std = @import("std");
const shovelerdb = @import("shovelerdb");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len == 1) {
        try stdout.print("{s}: {s}, implemented in {s}\n", .{
            shovelerdb.Project.name,
            shovelerdb.Project.dialect,
            shovelerdb.Project.implementation_language,
        });
        try stdout.print("usage: shoveler check-sql <sql>\n", .{});
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, args[1], "check-sql")) {
        if (args.len < 3) {
            try stdout.print("usage: shoveler check-sql <sql>\n", .{});
            try stdout.flush();
            std.process.exit(64);
        }

        const sql = args[2];
        if (shovelerdb.sql.policy.firstViolation(sql)) |found| {
            try stdout.print("rejected: {s} at byte {d} near `{s}`\n", .{
                found.message(),
                found.offset,
                found.token,
            });
            try stdout.flush();
            std.process.exit(2);
        }

        try stdout.print("accepted\n", .{});
        try stdout.flush();
        return;
    }

    try stdout.print("unknown command: {s}\n", .{args[1]});
    try stdout.flush();
    std.process.exit(64);
}

test "main module imports project metadata" {
    try std.testing.expectEqualStrings("ShovelerDB", shovelerdb.Project.name);
    try std.testing.expect(shovelerdb.FeaturePolicy.transactions);
}
