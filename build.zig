const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_docs = b.option(bool, "gen-docs", "Generates documentation files") orelse false;
    const gen_coverage = b.option(bool, "gen-coverage", "Generates test coverage reports") orelse false;

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
    // TODO: figure out how to make this work using Zig's build system.
    // i.e. make it move the generated files to the install folder.
    if (gen_coverage) {
        lib_unit_tests.setExecCmd(&.{
            "kcov",
            "--include-path=src",
            "--clean",
            "kcov-out",
            null, // to get zig to use the --test-cmd-bin flag
        });
    }

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
