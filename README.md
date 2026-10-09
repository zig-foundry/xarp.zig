# xarp.zig

The official Zig port of the Rust [`xarp`](https://crates.io/crates/xarp) crate. Provides a zero-dependency argument parser with built-in ANSI terminal styling (named colors, 256-color, and 24-bit RGB).

Currently targets **Zig 0.16**.

> **Note:** The library links libc to read environment variables via `getenv` for `NO_COLOR` support and default environment fallbacks.

## Installation

Add `xarp_zig` to your `build.zig.zon`, then expose it in your `build.zig`:

```zig
const xarp_dep = b.dependency("xarp_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("xarp_zig", xarp_dep.module("xarp_zig"));

```

## Quick Start

```zig
const std = @import("std");
const xarp = @import("xarp_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const argv = try init.minimal.args.toSlice(allocator);
    defer allocator.free(argv);

    var app = xarp.Xarp.new(allocator, "demo")
        .withVersion("0.1.0")
        .withAbout("A small CLI");
    defer app.deinit();

    try app.addArg(xarp.Arg.new("verbose").withShort('v').withLong("verbose").withHelp("Enable verbose output").withAction(.set_true));
    try app.addArg(xarp.Arg.new("config").withShort('c').withLong("config").withValueName("PATH").withHelp("Configuration file path").withDefault("config.toml"));
    try app.addArg(xarp.Arg.new("input").withValueName("FILE").withHelp("Input file to process").setRequired(true));

    var outcome = try app.tryGetMatchesFrom(argv);
    defer outcome.deinit(allocator);

    switch (outcome) {
        .matches => |*matches| {
            const verbose = matches.getFlag("verbose");
            const config = matches.getOne("config").?;
            const input = matches.getOne("input").?;
            std.debug.print("Verbose: {}\nConfig: {s}\nInput: {s}\n", .{ verbose, config, input });
        },
        .err => |err| {
            std.debug.print("{s}\n", .{err.message()});
            if (err.isParse()) std.process.exit(2);
        },
    }
}

```

Use `getMatches` if you want the parser to automatically print help or version text and exit. For non-fatal, fine-grained control, use `tryGetMatchesFrom` and handle the returned `Outcome`.

## Argument Types

* **Flags:** Set `.withAction(.set_true)` and read via `matches.getFlag("id")`.
* **Options:** Default action is `.set`. Accepts values as `--opt value` or `--opt=value`. Repeated flags retain only the last provided value. A trailing `--` is treated as a delimiter, never as an option value.
* **Positionals:** Omit short and long flag names. Evaluated in declaration order. You cannot declare a required positional argument after an optional one, and only the final positional argument can use `.append`.
* **Multi-value arguments:** Set `.withAction(.append)` and read via `matches.getMany("id")`.

```zig
try app.addArg(xarp.Arg.new("tag").withShort('t').withLong("tag").withAction(.append));

```

## Validation & Environment Fallbacks

```zig
try app.addArg(xarp.Arg.new("mode").withLong("mode").withValueName("MODE").withPossibleValues(&.{ "fast", "safe" }).withDefault("fast"));
try app.addArg(xarp.Arg.new("port").withLong("port").withValueName("PORT").withEnv("APP_PORT"));

var json = xarp.Arg.new("json").withLong("json");
try json.conflictsWith(allocator, "mode");
try app.addArg(json);

```

Conflict checks only apply to values explicitly passed on the CLI or through environment variables—default values never trigger conflict errors.

If an argument is omitted, the parser falls back to libc's `getenv`. When writing tests, use `tryGetMatchesWithEnv` to pass an explicit environment map so local machine variables don't bleed into test runs.

## Typed Parsing

`getOne` returns raw string slices. To parse strings into native Zig types, use `tryGetOne`:

```zig
const port = (try matches.tryGetOne(u16, "port")) orelse 8080;

```

* `tryGetOne`: Returns `null` if omitted, the parsed value on success, or `error.InvalidValue` on bad input.
* `getOneParsed`: Returns `null` on both missing arguments and parse failures.
* `valueError`: Formats a standard parse error message including the `--help` suggestion.
* Booleans require exact matches for `"true"` or `"false"`. Integers and floats use standard `std.fmt` parsing rules.

## Subcommands

```zig
var commit = xarp.Xarp.new(allocator, "commit").withAbout("Commit staged changes");
try commit.addArg(xarp.Arg.new("message").withShort('m').withLong("message").setRequired(true));
try app.addSubcommand(commit);

const name, const sub = matches.getSubcommand() orelse return;
_ = name;
const message = sub.getOne("message").?;

```

The first unrecognized positional token is treated as a subcommand if a matching one is registered. Passing `--` forces all subsequent tokens to be parsed as raw positional arguments (e.g. `prog -- build` passes `"build"` as an argument rather than a subcommand).

## Terminal Colors & Styling

Built-in presets are available directly under the root module (`xarp.RED`, `xarp.BOLD`, etc.). Format with `{f}` to write the opening ANSI escape code, and print `xarp.RESET` to clear styling.

```zig
try writer.print("{f}{s}{s}\n", .{ xarp.GREEN, "Build succeeded", xarp.RESET });

const warning = xarp.Style.new().bold().fgColor(.yellow).bgColor(.black);
try writer.print("{f}\n", .{warning.paint("Disk usage above 90%")});

```

Because Zig doesn't support bitwise operator overloading on structs:

* Use `style.merge(other)` to combine styles.
* Use `style.withColor(color)` to set the foreground color if unset.
* Use `effects.bitOr(other)` to combine text effects.

`Styles.styled()` is enabled by default. If the `NO_COLOR` environment variable is set (even to an empty string), styles automatically degrade to plain text.

## License

Dual-licensed under either:

* MIT License
* Apache License, Version 2.0
