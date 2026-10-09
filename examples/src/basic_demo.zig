//! Basic CLI example demonstrating required positionals, flags, defaults, and subcommands.
//!
//! Run with:
//! ```sh
//! zig build basic -- input.txt -v
//! zig build basic -- build --release
//! ```

const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const argv = try init.minimal.args.toSlice(allocator);
    defer allocator.free(argv);

    var build_cmd = xarp.Xarp.new(allocator, "build").withAbout("Compile source packages into binary distributions");
    try build_cmd.addArg(xarp.Arg.new("release").withLong("release").withHelp("Compile in release mode").withAction(.set_true));

    var app = xarp.Xarp.new(allocator, "mycli")
        .withVersion("0.1.2")
        .withAbout("A styled CLI tool built with xarp");
    defer app.deinit();

    try app.addArg(xarp.Arg.new("input").withHelp("The input file to process").withValueName("FILE").setRequired(true));
    try app.addArg(xarp.Arg.new("verbose").withShort('v').withLong("verbose").withHelp("Enable verbose debugging output").withAction(.set_true));
    try app.addArg(xarp.Arg.new("output").withShort('o').withLong("output").withHelp("Target path for generated output").withValueName("PATH").withDefault("dist/output.bin"));
    try app.addSubcommand(build_cmd);

    var matches = try app.getMatches(argv);
    defer matches.deinit();

    if (matches.getSubcommand()) |found| {
        const name, const sub_matches = found;
        if (std.mem.eql(u8, name, "build")) {
            std.debug.print("==> Subcommand: build\n", .{});
            std.debug.print("    Optimized release build: {}\n", .{sub_matches.getFlag("release")});
            return;
        }
    }

    const input = matches.getOne("input") orelse return error.MissingInput;
    const output = matches.getOne("output") orelse return error.MissingOutput;

    std.debug.print("Configuration loaded:\n", .{});
    std.debug.print("  - Input:   {s}\n", .{input});
    std.debug.print("  - Output:  {s}\n", .{output});
    std.debug.print("  - Verbose: {}\n", .{matches.getFlag("verbose")});
}
