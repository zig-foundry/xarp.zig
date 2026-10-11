const std = @import("std");

/// Registers an executable target and an accompanying run step for an example.
fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    xarp: *std.Build.Module,
    step_name: []const u8,
    file_name: []const u8,
    exe_name: []const u8,
    desc: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(file_name),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "xarp_zig", .module = xarp },
            },
        }),
    });
    b.installArtifact(exe);

    const step = b.step(step_name, desc);
    const run = b.addRunArtifact(exe);
    step.dependOn(&run.step);

    if (b.args) |args| {
        run.addArgs(args);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xarp = b.dependency("xarp_zig", .{
        .target = target,
        .optimize = optimize,
    }).module("xarp_zig");

    addExample(b, target, optimize, xarp, "basic", "src/basic_demo.zig", "basic_demo", "Run basic_demo");
    addExample(b, target, optimize, xarp, "next", "src/next_cli.zig", "next_cli", "Run basic_demo");
    addExample(b, target, optimize, xarp, "advanced", "src/advanced_cli.zig", "advanced_cli", "Run advanced_cli");
    addExample(b, target, optimize, xarp, "env", "src/env_and_validation.zig", "env_and_validation", "Run env_and_validation");
    addExample(b, target, optimize, xarp, "errors", "src/error_handling.zig", "error_handling", "Run error_handling");
    addExample(b, target, optimize, xarp, "vcs", "src/git_style_subcommands.zig", "git_style_subcommands", "Run git_style_subcommands");
    addExample(b, target, optimize, xarp, "style", "src/styling_and_theming.zig", "styling_and_theming", "Run styling_and_theming");
}
