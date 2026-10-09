//! Git-style nested subcommands (`vcs remote add <name> <url>`).
//!
//! Flags passed before the subcommand apply to the root parser.
//! Using `--` marks the boundary after which all tokens parse as positionals.
//!
//! Test combinations:
//! - zig build vcs -- commit -m "initial commit"
//! - zig build vcs -- --verbose remote add origin https://example.com/repo
//! - zig build vcs -- remote remove origin
//! - zig build vcs -- commit --message -m

const std = @import("std");
const xarp = @import("xarp_zig");

fn buildApp(allocator: std.mem.Allocator) !xarp.Xarp {
    var commit = xarp.Xarp.new(allocator, "commit").withAbout("Record a new commit");
    try commit.addArg(xarp.Arg.new("message").withShort('m').withLong("message").withValueName("MSG").withHelp("Commit message. Accepts literal strings like -m").setRequired(true));

    var remote_add = xarp.Xarp.new(allocator, "add").withAbout("Register a new remote");
    try remote_add.addArg(xarp.Arg.new("name").withValueName("NAME").withHelp("Remote name").setRequired(true));
    try remote_add.addArg(xarp.Arg.new("url").withValueName("URL").withHelp("Remote URL").setRequired(true));

    var remote_remove = xarp.Xarp.new(allocator, "remove").withAbout("Remove a registered remote");
    try remote_remove.addArg(xarp.Arg.new("name").withValueName("NAME").withHelp("Remote name").setRequired(true));

    var remote = xarp.Xarp.new(allocator, "remote").withAbout("Manage tracked remotes");
    try remote.addSubcommand(remote_add);
    try remote.addSubcommand(remote_remove);

    var app = xarp.Xarp.new(allocator, "vcs")
        .withVersion("0.1.2")
        .withAbout("A version-control CLI demonstration built with xarp");
    try app.addArg(xarp.Arg.new("verbose").withShort('v').withLong("verbose").withHelp("Enable verbose output").withAction(.set_true));
    try app.addArg(xarp.Arg.new("format").withLong("format").withValueName("FORMAT").withHelp("Output format").withPossibleValues(&.{ "short", "full" }).withDefault("short"));
    try app.addSubcommand(commit);
    try app.addSubcommand(remote);
    return app;
}

fn runRemote(matches: *const xarp.ArgMatches, verbose: bool, format: []const u8) void {
    const found = matches.getSubcommand() orelse {
        std.debug.print("Usage: vcs remote (add | remove) ...\n", .{});
        std.process.exit(2);
    };
    const name, const sub = found;
    if (std.mem.eql(u8, name, "add")) {
        const remote_name = sub.getOne("name") orelse "<missing>";
        const url = sub.getOne("url") orelse "<missing>";
        std.debug.print("Adding remote [{s}]: {s} -> {s} (verbose: {})\n", .{ format, remote_name, url, verbose });
        return;
    }
    if (std.mem.eql(u8, name, "remove")) {
        const remote_name = sub.getOne("name") orelse "<missing>";
        std.debug.print("Removing remote [{s}]: {s} (verbose: {})\n", .{ format, remote_name, verbose });
        return;
    }
    std.debug.print("Usage: vcs remote (add | remove) ...\n", .{});
    std.process.exit(2);
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

    const verbose = matches.getFlag("verbose");
    const format = matches.getOne("format") orelse "short";
    const found = matches.getSubcommand() orelse {
        try app.printHelp();
        return;
    };
    const name, const sub = found;
    if (std.mem.eql(u8, name, "commit")) {
        const message = sub.getOne("message") orelse "<missing>";
        std.debug.print("Committing [{s}]: {s} (verbose: {})\n", .{ format, message, verbose });
        return;
    }
    if (std.mem.eql(u8, name, "remote")) {
        runRemote(sub, verbose, format);
    }
}
