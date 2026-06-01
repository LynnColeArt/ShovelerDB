const std = @import("std");
const distance = @import("distance.zig");

pub const DistanceMetric = enum {
    squared_l2,
    l2,
    cosine,
};

pub const Candidate = struct {
    key: u64,
    vector: []const f32,
};

pub const SearchResult = struct {
    key: u64,
    distance: f64,
};

pub fn topK(
    allocator: std.mem.Allocator,
    query: []const f32,
    candidates: []const Candidate,
    limit: usize,
    metric: DistanceMetric,
) ![]SearchResult {
    if (limit == 0 or candidates.len == 0) return allocator.alloc(SearchResult, 0);

    var scored: std.ArrayList(SearchResult) = .empty;
    defer scored.deinit(allocator);

    for (candidates) |candidate| {
        try scored.append(allocator, .{
            .key = candidate.key,
            .distance = try score(metric, query, candidate.vector),
        });
    }

    sortResults(scored.items);

    const result_count = @min(limit, scored.items.len);
    const results = try allocator.alloc(SearchResult, result_count);
    @memcpy(results, scored.items[0..result_count]);
    return results;
}

fn score(metric: DistanceMetric, query: []const f32, candidate: []const f32) !f64 {
    return switch (metric) {
        .squared_l2 => try distance.squaredL2(query, candidate),
        .l2 => try distance.l2(query, candidate),
        .cosine => try distance.cosineDistance(query, candidate),
    };
}

fn sortResults(results: []SearchResult) void {
    if (results.len < 2) return;

    var i: usize = 1;
    while (i < results.len) : (i += 1) {
        var j = i;
        while (j > 0 and resultComesAfter(results[j - 1], results[j])) : (j -= 1) {
            std.mem.swap(SearchResult, &results[j - 1], &results[j]);
        }
    }
}

fn resultComesAfter(left: SearchResult, right: SearchResult) bool {
    if (left.distance > right.distance) return true;
    if (left.distance < right.distance) return false;
    return left.key > right.key;
}

test "topK returns nearest vectors by squared L2 distance" {
    const allocator = std.testing.allocator;

    const candidates = [_]Candidate{
        .{ .key = 30, .vector = &.{ 10, 10 } },
        .{ .key = 10, .vector = &.{ 1, 1 } },
        .{ .key = 20, .vector = &.{ 2, 2 } },
    };

    const results = try topK(allocator, &.{ 0, 0 }, &candidates, 2, .squared_l2);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqual(@as(u64, 10), results[0].key);
    try std.testing.expectEqual(@as(u64, 20), results[1].key);
}

test "topK handles ties by key and limit larger than candidates" {
    const allocator = std.testing.allocator;

    const candidates = [_]Candidate{
        .{ .key = 2, .vector = &.{ 1, 0 } },
        .{ .key = 1, .vector = &.{ -1, 0 } },
        .{ .key = 3, .vector = &.{ 0, 2 } },
    };

    const results = try topK(allocator, &.{ 0, 0 }, &candidates, 10, .squared_l2);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
    try std.testing.expectEqual(@as(u64, 1), results[0].key);
    try std.testing.expectEqual(@as(u64, 2), results[1].key);
    try std.testing.expectEqual(@as(u64, 3), results[2].key);
}

test "topK handles empty input and zero limit" {
    const allocator = std.testing.allocator;

    const empty = try topK(allocator, &.{ 0, 0 }, &.{}, 5, .l2);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    const candidates = [_]Candidate{.{ .key = 1, .vector = &.{ 0, 0 } }};
    const none = try topK(allocator, &.{ 0, 0 }, &candidates, 0, .l2);
    defer allocator.free(none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "topK supports cosine distance for non-normalized vectors" {
    const allocator = std.testing.allocator;

    const candidates = [_]Candidate{
        .{ .key = 1, .vector = &.{ 0, 5 } },
        .{ .key = 2, .vector = &.{ 10, 0 } },
        .{ .key = 3, .vector = &.{ -1, 0 } },
    };

    const results = try topK(allocator, &.{ 2, 0 }, &candidates, 3, .cosine);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(u64, 2), results[0].key);
    try std.testing.expectEqual(@as(u64, 1), results[1].key);
    try std.testing.expectEqual(@as(u64, 3), results[2].key);
}

test "topK returns dimension mismatch errors" {
    const allocator = std.testing.allocator;
    const candidates = [_]Candidate{.{ .key = 1, .vector = &.{ 1, 2, 3 } }};

    try std.testing.expectError(
        error.VectorDimensionMismatch,
        topK(allocator, &.{ 1, 2 }, &candidates, 1, .l2),
    );
}
