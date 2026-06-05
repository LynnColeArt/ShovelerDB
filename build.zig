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
    const benchmark_metrics_module = b.createModule(.{
        .root_source_file = b.path("src/cli/benchmark_metrics.zig"),
        .target = target,
        .optimize = optimize,
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
    const view_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/view_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const view_persistence_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/view_persistence_acceptance.zig"),
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
    const ddl_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/ddl_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const procedure_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/procedure_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const procedure_transaction_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/procedure_transaction_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const procedure_diagnostics_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/procedure_diagnostics_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const concurrency_contract_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/concurrency_contract_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const snapshot_generation_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/snapshot_generation_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const commit_queue_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/commit_queue_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const checkpoint_vector_overlay_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/checkpoint_vector_overlay_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const concurrency_stress_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/concurrency_stress_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shovelerdb", .module = lib_module },
        },
    });
    const benchmark_output_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/benchmark_output_acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "benchmark_metrics", .module = benchmark_metrics_module },
        },
    });
    const adapted_fixture_integration_module = b.createModule(.{
        .root_source_file = b.path("tests/adapted_fixture_acceptance.zig"),
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
    const view_integration_tests = b.addTest(.{
        .root_module = view_integration_module,
    });
    const view_persistence_integration_tests = b.addTest(.{
        .root_module = view_persistence_integration_module,
    });
    const aggregate_integration_tests = b.addTest(.{
        .root_module = aggregate_integration_module,
    });
    const ddl_integration_tests = b.addTest(.{
        .root_module = ddl_integration_module,
    });
    const procedure_integration_tests = b.addTest(.{
        .root_module = procedure_integration_module,
    });
    const procedure_transaction_integration_tests = b.addTest(.{
        .root_module = procedure_transaction_integration_module,
    });
    const procedure_diagnostics_integration_tests = b.addTest(.{
        .root_module = procedure_diagnostics_integration_module,
    });
    const concurrency_contract_integration_tests = b.addTest(.{
        .root_module = concurrency_contract_integration_module,
    });
    const snapshot_generation_integration_tests = b.addTest(.{
        .root_module = snapshot_generation_integration_module,
    });
    const commit_queue_integration_tests = b.addTest(.{
        .root_module = commit_queue_integration_module,
    });
    const checkpoint_vector_overlay_integration_tests = b.addTest(.{
        .root_module = checkpoint_vector_overlay_integration_module,
    });
    const concurrency_stress_integration_tests = b.addTest(.{
        .root_module = concurrency_stress_integration_module,
    });
    const benchmark_output_integration_tests = b.addTest(.{
        .root_module = benchmark_output_integration_module,
    });
    const adapted_fixture_integration_tests = b.addTest(.{
        .root_module = adapted_fixture_integration_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_query_source_integration_tests = b.addRunArtifact(query_source_integration_tests);
    const run_view_integration_tests = b.addRunArtifact(view_integration_tests);
    const run_view_persistence_integration_tests = b.addRunArtifact(view_persistence_integration_tests);
    const run_aggregate_integration_tests = b.addRunArtifact(aggregate_integration_tests);
    const run_ddl_integration_tests = b.addRunArtifact(ddl_integration_tests);
    const run_procedure_integration_tests = b.addRunArtifact(procedure_integration_tests);
    const run_procedure_transaction_integration_tests = b.addRunArtifact(procedure_transaction_integration_tests);
    const run_procedure_diagnostics_integration_tests = b.addRunArtifact(procedure_diagnostics_integration_tests);
    const run_concurrency_contract_integration_tests = b.addRunArtifact(concurrency_contract_integration_tests);
    const run_snapshot_generation_integration_tests = b.addRunArtifact(snapshot_generation_integration_tests);
    const run_commit_queue_integration_tests = b.addRunArtifact(commit_queue_integration_tests);
    const run_checkpoint_vector_overlay_integration_tests = b.addRunArtifact(checkpoint_vector_overlay_integration_tests);
    const run_concurrency_stress_integration_tests = b.addRunArtifact(concurrency_stress_integration_tests);
    const run_benchmark_output_integration_tests = b.addRunArtifact(benchmark_output_integration_tests);
    const run_adapted_fixture_integration_tests = b.addRunArtifact(adapted_fixture_integration_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_query_source_integration_tests.step);
    test_step.dependOn(&run_view_integration_tests.step);
    test_step.dependOn(&run_view_persistence_integration_tests.step);
    test_step.dependOn(&run_aggregate_integration_tests.step);
    test_step.dependOn(&run_ddl_integration_tests.step);
    test_step.dependOn(&run_procedure_integration_tests.step);
    test_step.dependOn(&run_procedure_transaction_integration_tests.step);
    test_step.dependOn(&run_procedure_diagnostics_integration_tests.step);
    test_step.dependOn(&run_concurrency_contract_integration_tests.step);
    test_step.dependOn(&run_snapshot_generation_integration_tests.step);
    test_step.dependOn(&run_commit_queue_integration_tests.step);
    test_step.dependOn(&run_checkpoint_vector_overlay_integration_tests.step);
    test_step.dependOn(&run_concurrency_stress_integration_tests.step);
    test_step.dependOn(&run_benchmark_output_integration_tests.step);
    test_step.dependOn(&run_adapted_fixture_integration_tests.step);
}
