const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "iteropt-demo",
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/iteropt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run unit tests");
    const run_mod_unit_tests = b.addRunArtifact(mod_unit_tests);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    b.installArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
    test_step.dependOn(&run_mod_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
