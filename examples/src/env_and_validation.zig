//! Value resolution priority: CLI flags override environment variables, which override defaults.
//!
//! Test combinations:
//! - zig build env --
//! - zig build env -- --region eu --json
//! - APP_REGION=asia APP_WORKERS=8 zig build env
//! - zig build env -- --json --yaml

const std = @import("std");
const xarp = @import("xarp_zig");

fn buildApp(allocator: std.mem.Allocator) !xarp.Xarp {
    var app = xarp.Xarp.new(allocator, "deployer")
        .withVersion("0.1.2")
        .withAbout("Reads deployment settings from flags, environment, and defaults");
    try app.addArg(xarp.Arg.new("region").withLong("region").withValueName("REGION").withHelp("Target region").withPossibleValues(&.{ "us", "eu", "asia" }).withEnv("APP_REGION").withDefault("us"));
    try app.addArg(xarp.Arg.new("workers").withShort('w').withLong("workers").withValueName("COUNT").withHelp("Worker thread count").withEnv("APP_WORKERS").withDefault("4"));

    var json = xarp.Arg.new("json").withLong("json").withHelp("Emit JSON output").withAction(.set_true);
    try json.conflictsWith(allocator, "yaml");
    try app.addArg(json);
    try app.addArg(xarp.Arg.new("yaml").withLong("yaml").withHelp("Emit YAML output").withAction(.set_true));
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

    const region = matches.getOne("region") orelse "us";
    const workers = (try matches.tryGetOne(u16, "workers")) orelse 4;
    const format = if (matches.getFlag("json")) "json" else if (matches.getFlag("yaml")) "yaml" else "text";

    std.debug.print("Resolved configuration:\n", .{});
    std.debug.print("  - Region:  {s}\n", .{region});
    std.debug.print("  - Workers: {d}\n", .{workers});
    std.debug.print("  - Format:  {s}\n", .{format});
}
