const std = @import("std");
const ast = @import("../sql/ast.zig");

pub const Function = enum {
    count,
    sum,
    avg,
    min,
    max,
};

pub fn functionForName(name: []const u8) ?Function {
    if (std.ascii.eqlIgnoreCase(name, "COUNT")) return .count;
    if (std.ascii.eqlIgnoreCase(name, "SUM")) return .sum;
    if (std.ascii.eqlIgnoreCase(name, "AVG")) return .avg;
    if (std.ascii.eqlIgnoreCase(name, "MIN")) return .min;
    if (std.ascii.eqlIgnoreCase(name, "MAX")) return .max;
    return null;
}

pub fn expressionContainsAggregate(expression: ast.Expression) bool {
    return switch (expression) {
        .function_call => |call| functionForName(call.name) != null or blk: {
            for (call.args) |arg| {
                if (expressionContainsAggregate(arg)) break :blk true;
            }
            break :blk false;
        },
        .binary => |binary| expressionContainsAggregate(binary.left.*) or expressionContainsAggregate(binary.right.*),
        .star, .identifier, .literal => false,
    };
}

pub fn expressionIsAggregateCall(expression: ast.Expression) bool {
    return expression == .function_call and functionForName(expression.function_call.name) != null;
}

test "recognizes supported aggregate functions case-insensitively" {
    try std.testing.expectEqual(Function.count, functionForName("count").?);
    try std.testing.expectEqual(Function.sum, functionForName("SUM").?);
    try std.testing.expectEqual(Function.avg, functionForName("Avg").?);
    try std.testing.expectEqual(Function.min, functionForName("min").?);
    try std.testing.expectEqual(Function.max, functionForName("MAX").?);
    try std.testing.expect(functionForName("l2_distance") == null);
}
