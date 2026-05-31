const std = @import("std");
const shovelerdb = @import("shovelerdb");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}: {s}, implemented in {s}\n", .{
        shovelerdb.Project.name,
        shovelerdb.Project.dialect,
        shovelerdb.Project.implementation_language,
    });
}

