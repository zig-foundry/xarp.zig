//! Demonstrates terminal styling presets, chained styles, TrueColor RGB, and custom CLI help themes.
//!
//! Zig does not support operator overloading for styling. Chain builder methods
//! like `fgColor(...)`, `bold()`, and `underline()` to compose styles.
//! Calling `printHelp()` renders output using the theme configured via `withStyles`.

const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    std.debug.print("=== 1. Built-in Style Presets ===\n", .{});
    std.debug.print("  {f}\n", .{xarp.GREEN.paint("✔ Build succeeded")});
    std.debug.print("  {f}\n", .{xarp.RED.paint("✖ Error: connection reset by peer")});
    std.debug.print("  {f}\n", .{xarp.GOLD.paint("⚠ Warning: low disk space")});
    std.debug.print("  {f}\n", .{xarp.INDIGO.paint("ℹ Note: migrations pending")});

    std.debug.print("\n=== 2. Custom Styles ===\n", .{});
    const badge = xarp.Style.new().bold().fgColor(.black).bgColor(.bright_cyan);
    const dim_text = xarp.Style.new().dim().italic();
    std.debug.print("  {f} {f}\n", .{
        badge.paint(" RELEASE "),
        dim_text.paint("v2.4.0 (x86_64-linux)"),
    });

    std.debug.print("\n=== 3. Composed Styles ===\n", .{});
    const critical = xarp.Style.new().fgColor(.bright_red).bold().underline();
    const highlight = xarp.Style.new().fgColor(.lime).italic();
    std.debug.print("  {f}\n", .{critical.paint("CRITICAL FAULT DETECTED")});
    std.debug.print("  {f}\n", .{highlight.paint("Resource allocation verified")});

    std.debug.print("\n=== 4. TrueColor (RGB) and Extended 256 Colors ===\n", .{});
    const sunset = xarp.Style.new().fgColor(.{ .rgb = .{ .r = 255, .g = 110, .b = 64 } }).bold();
    const ocean = xarp.Style.new().fgColor(.{ .rgb = .{ .r = 0, .g = 210, .b = 255 } }).bgColor(.{ .rgb = .{ .r = 15, .g = 23, .b = 42 } });
    const mauve = xarp.Style.new().fgColor(.{ .ansi256 = 141 }).bold();
    std.debug.print("  {f}\n", .{sunset.paint("TrueColor RGB (255, 110, 64)")});
    std.debug.print("  {f}\n", .{ocean.paint(" RGB Foreground + Background ")});
    std.debug.print("  {f}\n", .{mauve.paint("ANSI-256 code #141 (Mauve)")});

    std.debug.print("\n=== 5. Custom CLI Help Theme Configuration ===\n", .{});
    const theme = xarp.Styles.plain()
        .setHeader(xarp.Style.new().bold().fgColor(.gold).underline())
        .setUsage(xarp.Style.new().bold().fgColor(.bright_cyan))
        .setLiteral(xarp.Style.new().bold().fgColor(.lime))
        .setPlaceholder(xarp.Style.new().italic().fgColor(.silver))
        .setError(xarp.Style.new().bold().bgColor(.bright_red).fgColor(.white))
        .setValid(xarp.Style.new().bold().fgColor(.bright_green))
        .setWarning(xarp.Style.new().bold().fgColor(.orange));

    var app = xarp.Xarp.new(allocator, "themed-tool")
        .withVersion("1.0.0")
        .withAbout("A tool showcasing custom help screen aesthetics")
        .withStyles(theme);
    defer app.deinit();
    try app.addArg(xarp.Arg.new("target").withHelp("Compilation target architecture").withValueName("ARCH").setRequired(true));
    try app.addArg(xarp.Arg.new("optimize").withShort('O').withLong("optimize").withHelp("Optimization level (0-3)").withValueName("LEVEL").withDefault("3"));
    try app.addArg(xarp.Arg.new("quiet").withShort('q').withLong("quiet").withHelp("Silence standard logs").withAction(.set_true));
    try app.printHelp();
}
