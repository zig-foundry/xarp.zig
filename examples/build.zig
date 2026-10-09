const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xarp_dep = b.dependency("xarp_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const xarp = xarp_dep.module("xarp_zig");

    const basic = b.addExecutable(.{
        .name = "basic_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/basic_demo.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "xarp_zig", .module = xarp },
            },
        }),
    });
    b.installArtifact(basic);

    const advanced = b.addExecutable(.{
        .name = "advanced_cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/advanced_cli.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "xarp_zig", .module = xarp },
            },
        }),
    });
    b.installArtifact(advanced);

    const run_basic = b.step("basic", "Run basic_demo");
    const run_basic_cmd = b.addRunArtifact(basic);
    run_basic.dependOn(&run_basic_cmd.step);
    if (b.args) |args| run_basic_cmd.addArgs(args);

    const run_advanced = b.step("advanced", "Run advanced_cli");
    const run_advanced_cmd = b.addRunArtifact(advanced);
    run_advanced.dependOn(&run_advanced_cmd.step);
}
