const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });

    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/kernel_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const query_source_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/query_source_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const aggregate_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/aggregate_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "shoveler",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the ShovelerDB CLI");
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = lib_module,
    });
    const exe_tests = b.addTest(.{
        .root_module = exe_module,
    });
    const integration_tests = b.addTest(.{
        .root_module = integration_module,
    });
    const query_source_integration_tests = b.addTest(.{
        .root_module = query_source_integration_module,
    });
    const aggregate_integration_tests = b.addTest(.{
        .root_module = aggregate_integration_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_query_source_integration_tests = b.addRunArtifact(query_source_integration_tests);
    const run_aggregate_integration_tests = b.addRunArtifact(aggregate_integration_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_query_source_integration_tests.step);
    test_step.dependOn(&run_aggregate_integration_tests.step);
}
