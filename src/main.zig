const std = @import("std");
const shovelerdb = @import("shovelerdb");

pub fn main() !void {
    std.debug.print("{s}: {s}, implemented in {s}\n", .{
        shovelerdb.Project.name,
        shovelerdb.Project.dialect,
        shovelerdb.Project.implementation_language,
    });
}
