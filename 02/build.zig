const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("kv", .{
        .root_source_file = b.path("src/kv.zig"),
        .target = target,
        .optimize = optimize,
    });

    const module_tests = b.addTest(.{
        .root_module = module,
    });
    const module_tests_run = b.addRunArtifact(module_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&module_tests_run.step);
}
