const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_docs = b.option(bool, "gen-docs", "Generates documentation files") orelse false;
    const report_coverage = b.option(bool, "report-coverage", "Generates a test code coverage using kcov") orelse false;

    const cricket = b.addModule("cricket", .{
        .root_source_file = b.path("src/cricket.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Examples
    const examples_step = b.step("examples", "Build all examples");
    const example_files = [_][]const u8{
        "signer_verifier.zig",
    };

    for (example_files) |filename| {
        const example_name = blk: {
            var split_iter = std.mem.splitScalar(u8, filename, '.');
            break :blk split_iter.next().?;
        };

        const example_exec = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.pathJoin(&.{ "examples", filename })),
            .target = target,
            .optimize = optimize,
        });
        // Make cricket.zig available for examples
        example_exec.root_module.addImport("cricket", cricket);

        const install_example = b.addInstallArtifact(example_exec, .{});

        examples_step.dependOn(&install_example.step);
    }

    // Docs
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

    // Tests
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
