const std = @import("std");
const Io = std.Io;
const xarp = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    const banner: xarp.Color = .bright_cyan;
    const accent: xarp.Color = .bright_green;

    try writer.print("\x1b[{f}mXarp CLI Engine\x1b[0m (\x1b[{f}mready\x1b[0m)\n", .{ banner, accent });
    try writer.flush();
}
