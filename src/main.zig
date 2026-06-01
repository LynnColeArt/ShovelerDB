const std = @import("std");
const shovelerdb = @import("shovelerdb");
const commands = @import("cli/commands.zig");

pub fn main(init: std.process.Init) !void {
    try commands.run(init);
}

test "main module imports project metadata" {
    try std.testing.expectEqualStrings("ShovelerDB", shovelerdb.Project.name);
    try std.testing.expect(shovelerdb.FeaturePolicy.transactions);
}

test {
    std.testing.refAllDecls(commands);
}
