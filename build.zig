const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_docs = b.option(bool, "gen-docs", "Generates documentation files") orelse false;
    const report_coverage = b.option(bool, "report-coverage", "Generates a test code coverage using kcov") orelse false;

    _ = b.addModule("cricket", .{
        .root_source_file = b.path("src/cricket.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (gen_docs) {
        const docs = b.addObject(.{
            .name = "docs",
            .root_source_file = b.path("src/cricket.zig"),
            .target = target,
            .optimize = .Debug,
        });
        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        b.getInstallStep().dependOn(&install_docs.step);
    }

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/cricket.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run unit tests");

    if (report_coverage) {
        // Generate coverage report with kcov
        var run_kcov = b.addSystemCommand(&.{"kcov"});
        run_kcov.addPrefixedDirectoryArg("--include-path=", b.path("src"));
        run_kcov.addArg("--clean");

        const kcov_out_dir_path = run_kcov.addPrefixedOutputDirectoryArg("", "kcov-out");
        run_kcov.addFileArg(lib_unit_tests.getEmittedBin());

        run_kcov.has_side_effects = true;
        run_kcov.stdio = .inherit;

        const install_kcov_dir = b.addInstallDirectory(.{
            .source_dir = kcov_out_dir_path,
            .install_dir = .prefix,
            .install_subdir = "kcov-out",
        });
        install_kcov_dir.step.dependOn(&run_kcov.step);

        test_step.dependOn(&install_kcov_dir.step);
    } else {
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);
    }
}
