//! Advanced CLI example demonstrating typed integer parsing and repeatable flags.
//!
//! Uses a mock argument array so you can run it directly without CLI arguments.
//! Parses arguments into the `serve` subcommand and prints the resolved values.

const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var serve = xarp.Xarp.new(allocator, "serve").withAbout("Start the local HTTP server");
    try serve.addArg(xarp.Arg.new("port").withShort('p').withLong("port").withValueName("PORT").withHelp("TCP port to bind").withDefault("8080"));
    try serve.addArg(xarp.Arg.new("headers").withShort('H').withLong("header").withValueName("KEY:VAL").withHelp("HTTP header to add to responses").withAction(.append));
    try serve.addArg(xarp.Arg.new("root").withShort('r').withLong("root").withValueName("DIR").withHelp("Root directory for static files").withDefault("."));

    var cli = xarp.Xarp.new(allocator, "nexus")
        .withVersion("0.1.2")
        .withAbout("Service runner and toolchain");
    defer cli.deinit();
    try cli.addArg(xarp.Arg.new("workers").withShort('w').withLong("workers").withValueName("COUNT").withHelp("Number of worker threads").withDefault("4"));
    try cli.addSubcommand(serve);

    const mock_args = [_][]const u8{
        "nexus",
        "serve",
        "--port",
        "3000",
        "-H",
        "Cache-Control: no-cache",
        "-H",
        "X-Debug-Mode: true",
        "--root",
        "/var/www/html",
    };

    std.debug.print("Simulating input:", .{});
    for (mock_args) |arg| std.debug.print(" {s}", .{arg});
    std.debug.print("\n\n", .{});

    var outcome = try cli.tryGetMatchesFrom(&mock_args);
    defer outcome.deinit(allocator);
    switch (outcome) {
        .err => |err| {
            std.debug.print("Command parsing failed:\n{s}\n", .{err.message()});
            return;
        },
        .matches => |*matches| {
            const name, const sub = matches.getSubcommand() orelse return;
            if (!std.mem.eql(u8, name, "serve")) return;

            const port = (try sub.tryGetOne(u16, "port")) orelse return error.BadPort;
            const root = sub.getOne("root") orelse return error.MissingRoot;
            const headers = sub.getMany("headers") orelse &.{};

            std.debug.print("Server configuration:\n", .{});
            std.debug.print("  Listening on port : {d}\n", .{port});
            std.debug.print("  Document root     : {s}\n", .{root});
            std.debug.print("  Injected headers  : ({d} headers registered)\n", .{headers.len});
            for (headers, 0..) |header, idx| {
                std.debug.print("    [{d}] {s}\n", .{ idx, header });
            }
        },
    }
}
