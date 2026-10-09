//! Demo application demonstrating argument parsing and styled console output.
//!
//! Example usage:
//! ```sh
//! zig build run -- --name ada
//! ```

const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const argv = try init.minimal.args.toSlice(allocator);
    defer allocator.free(argv);

    const no_color = init.minimal.environ.getPosix("NO_COLOR") != null;
    var app = xarp.Xarp.new(allocator, "xarp_zig").withStyles(xarp.Styles.styledUnless(no_color));
    defer app.deinit();

    app = app.withVersion("0.1.0").withAbout("Zero-dependency argument parser");
    try app.addArg(xarp.Arg.new("name").withLong("name").withShort('n').withHelp("Name to greet"));

    var outcome = try app.tryGetMatchesFrom(argv);
    switch (outcome) {
        .matches => |*matches| {
            defer matches.deinit();
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
            const writer = &stdout_writer.interface;

            const name = matches.getOne("name") orelse "world";
            try writer.print("{f}{s}{s}\n", .{ xarp.BRIGHT_CYAN, name, xarp.RESET });
            try writer.flush();
        },
        .err => |err| {
            defer err.deinit(allocator);
            var buffer: [1024]u8 = undefined;
            const file: std.Io.File = if (err.isParse()) .stderr() else .stdout();
            var file_writer: std.Io.File.Writer = .init(file, io, &buffer);
            const writer = &file_writer.interface;

            try writer.print("{s}\n", .{err.message()});
            try writer.flush();
            if (err.isParse()) std.process.exit(2);
        },
    }
}
