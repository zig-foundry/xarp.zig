//! Non-fatal argument parsing and error reporting.
//!
//! Help and version requests print formatted text and exit with status 0.
//! Malformed inputs exit with status 2.
//!
//! Test combinations:
//! - zig build errors -- --help
//! - zig build errors -- --port 8080 --mode fast
//! - zig build errors -- --port abc
//! - zig build errors -- --mode wild

const std = @import("std");
const xarp = @import("xarp_zig");

fn buildApp(allocator: std.mem.Allocator) !xarp.Xarp {
    var app = xarp.Xarp.new(allocator, "deploy")
        .withVersion("0.1.2")
        .withAbout("Demonstrates non-fatal error handling and input validation");
    try app.addArg(xarp.Arg.new("port").withShort('p').withLong("port").withValueName("PORT").withHelp("TCP port to listen on").withDefault("8080"));
    try app.addArg(xarp.Arg.new("mode").withLong("mode").withValueName("MODE").withHelp("Deployment mode").withPossibleValues(&.{ "fast", "safe" }).withDefault("safe"));
    try app.addArg(xarp.Arg.new("verbose").withShort('v').withLong("verbose").withHelp("Enable verbose output").withAction(.set_true));
    return app;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const argv = try init.minimal.args.toSlice(allocator);
    defer allocator.free(argv);

    var app = try buildApp(allocator);
    defer app.deinit();
    var outcome = try app.tryGetMatchesFrom(argv);
    defer outcome.deinit(allocator);

    const matches = switch (outcome) {
        .err => |err| {
            std.debug.print("{s}\n", .{err.message()});
            if (err.isParse()) std.process.exit(2);
            return;
        },
        .matches => |*matches| matches,
    };

    const port = (try matches.tryGetOne(u16, "port")) orelse 8080;
    const mode = matches.getOne("mode") orelse "safe";
    std.debug.print("Configuration loaded:\n", .{});
    std.debug.print("  - Port:    {d}\n", .{port});
    std.debug.print("  - Mode:    {s}\n", .{mode});
    std.debug.print("  - Verbose: {}\n", .{matches.getFlag("verbose")});
}
