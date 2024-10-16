const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("iteropt", .{
        .root_source_file = b.path("iteropt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_unit_tests = b.addTest(.{
        .root_source_file = b.path("iteropt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    const run_mod_unit_tests = b.addRunArtifact(mod_unit_tests);

    test_step.dependOn(&run_mod_unit_tests.step);
}
