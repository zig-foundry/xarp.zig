//! ```zig
//! var app = Xarp.new(allocator, "demo");
//! defer app.deinit();
//! try app.addArg(Arg.new("input").setRequired(true));
//! var outcome = try app.tryGetMatchesFrom(argv);
//! defer outcome.deinit(allocator);
//! ```
//!
//! Parses argv into `ArgMatches`. Returns `Outcome`: `.matches` or `.err`.
//! `try` only signals allocation failure; help, version, and bad input
//! come back as `.err` so you can print them yourself.
//!
//! - Borrowed strings (`id`, help, defaults) must outlive the parser; literals do.
//! - Parsed values are copied; call `deinit` on both `Xarp` and `Outcome`.
//! - `tryGetMatchesWithEnv` reads only the map you pass; `tryGetMatchesFrom` reads libc `getenv`.

const std = @import("std");
const Style = @import("style.zig").Style;
const Styles = @import("style.zig").Styles;
const RESET = @import("color.zig").RESET;
const XarpError = @import("errors.zig").XarpError;

/// Env map for `tryGetMatchesWithEnv`. Missing keys count as unset.
pub const EnvMap = std.StringHashMapUnmanaged([]const u8);

/// Parse result. `.matches` holds values; `.err` holds help, version, or parse text.
pub const Outcome = union(enum) {
    /// Successful parse. Read flags and values from here.
    matches: ArgMatches,
    /// Help, version, or parse failure. Print `err.message()`.
    err: XarpError,

    /// `true` for `.matches`, `false` for `.err`.
    pub fn isOk(self: Outcome) bool {
        return switch (self) {
            .matches => true,
            else => false,
        };
    }

    /// Frees stored values and the subcommand. Call it or you leak memory.
    pub fn deinit(self: *Outcome, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .matches => |*matches| matches.deinit(),
            .err => |err| err.deinit(allocator),
        }
    }
};

/// Specifies the parsing action to take when an argument is encountered.
pub const ArgAction = enum {
    /// Flag without a value (`-v`, `--verbose`). Sets the flag to `true`.
    set_true,
    /// Option or positional that captures a single value. Last occurrence wins.
    set,
    /// Collects every occurrence. On a positional, only the last one may append.
    append,
};

/// A command-line argument definition. Copy it with `with*` builders, then pass to `addArg`.
pub const Arg = struct {
    /// Unique identifier. Must outlive the matches (a string literal is fine).
    id: []const u8,
    /// Short single-byte flag (`'v'` for `-v`).
    short: ?u8 = null,
    /// Long flag name (`"verbose"` for `--verbose`).
    long: ?[]const u8 = null,
    /// Description displayed in help messages.
    help: ?[]const u8 = null,
    /// Placeholder name displayed in help messages.
    value_name: ?[]const u8 = null,
    /// Whether the argument must be supplied by the user.
    required: bool = false,
    /// Parsing action performed when this argument is encountered.
    action: ArgAction = .set,
    /// Fallback used when the argument is not explicitly provided.
    default_value: ?[]const u8 = null,
    /// Environment variable used when the argument is not explicitly passed.
    env: ?[]const u8 = null,
    /// Allowed input choices. The slice must outlive the parser.
    possible_values: []const []const u8 = &.{},
    /// IDs of arguments that cannot be supplied alongside this one.
    conflicts_with: std.ArrayListUnmanaged([]const u8) = .empty,

    /// Starts a definition. `id` must stay alive as long as matches are used.
    pub fn new(id: []const u8) Arg {
        return .{ .id = id };
    }

    /// Limits values to `values`. Bad input fails parsing; defaults are checked too.
    pub fn withPossibleValues(self: Arg, values: []const []const u8) Arg {
        var next = self;
        next.possible_values = values;
        return next;
    }

    /// Reads this arg from `env_var` when the CLI omits it. CLI input always wins.
    pub fn withEnv(self: Arg, env_var: []const u8) Arg {
        var next = self;
        next.env = env_var;
        return next;
    }

    /// Marks `other_id` as conflicting. Pass both and parsing fails. Defaults don't count.
    pub fn conflictsWith(self: *Arg, allocator: std.mem.Allocator, other_id: []const u8) !void {
        try self.conflicts_with.append(allocator, other_id);
    }

    /// Sets `-x`. Must not be `-`, `=`, whitespace, or a duplicate.
    pub fn withShort(self: Arg, short: u8) Arg {
        var next = self;
        next.short = short;
        return next;
    }

    /// Sets `--name`. Must not be empty, start with `-`, or contain `=` / spaces.
    pub fn withLong(self: Arg, long: []const u8) Arg {
        var next = self;
        next.long = long;
        return next;
    }

    /// Help text shown in the Flags & Options list.
    pub fn withHelp(self: Arg, help: []const u8) Arg {
        var next = self;
        next.help = help;
        return next;
    }

    /// Placeholder shown in help (`<PATH>`). Falls back to `id` when unset.
    pub fn withValueName(self: Arg, name: []const u8) Arg {
        var next = self;
        next.value_name = name;
        return next;
    }

    /// `true` fails parsing when no CLI value, env value, or default exists.
    pub fn setRequired(self: Arg, required: bool) Arg {
        var next = self;
        next.required = required;
        return next;
    }

    /// Picks `.set_true` (flag), `.set` (single value, last wins), or `.append` (collects all).
    pub fn withAction(self: Arg, action: ArgAction) Arg {
        var next = self;
        next.action = action;
        return next;
    }

    /// Fallback value when CLI and env both omit the arg. Never triggers conflicts.
    pub fn withDefault(self: Arg, default: []const u8) Arg {
        var next = self;
        next.default_value = default;
        return next;
    }

    /// `true` when no short or long flag is set. Positionals fill in declaration order.
    pub fn isPositional(self: Arg) bool {
        return self.short == null and self.long == null;
    }
};

/// Parsed flags, values, and an optional subcommand. Call `deinit` or you leak copies.
pub const ArgMatches = struct {
    /// Backing allocator for value copies. Don't swap it after parsing.
    allocator: std.mem.Allocator,
    /// Set flags by arg `id`. Read with `getFlag`; don't write directly.
    flags: std.StringHashMapUnmanaged(void) = .empty,
    /// Stored values by arg `id`. Read with `getOne` / `getMany`; don't write directly.
    values: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]u8)) = .empty,
    /// Matched subcommand, if any. Read with `getSubcommand`.
    subcommand: ?Subcommand = null,

    const Subcommand = struct {
        name: []u8,
        matches: *ArgMatches,
    };
    /// Frees value copies and the boxed subcommand.
    pub fn deinit(self: *ArgMatches) void {
        self.flags.deinit(self.allocator);
        var values = self.values.iterator();
        while (values.next()) |entry| {
            for (entry.value_ptr.items) |item| self.allocator.free(item);
            entry.value_ptr.deinit(self.allocator);
        }
        self.values.deinit(self.allocator);
        if (self.subcommand) |sub| {
            self.allocator.free(sub.name);
            sub.matches.deinit();
            self.allocator.destroy(sub.matches);
        }
    }

    /// `true` when the `.set_true` flag was passed (or enabled via env/default).
    pub fn getFlag(self: *const ArgMatches, id: []const u8) bool {
        return self.flags.contains(id);
    }

    /// First value, or `null` when absent. Returns the raw string; use `tryGetOne` for typed values.
    pub fn getOne(self: *const ArgMatches, id: []const u8) ?[]const u8 {
        const list = self.values.get(id) orelse return null;
        if (list.items.len == 0) return null;
        return list.items[0];
    }

    /// All stored values. Borrowed from matches; don't free them. `null` when absent.
    pub fn getMany(self: *const ArgMatches, id: []const u8) ?[]const []u8 {
        const list = self.values.get(id) orelse return null;
        return list.items;
    }

    /// Suffix added so typed failures point at `--help` like other parse errors.
    const try_help_hint = "\n\nFor more information, try '--help'.";

    /// Parses the first value as `T`. Returns `null` when absent, `InvalidValue` on bad input.
    ///
    /// ```zig
    /// const port = (try matches.tryGetOne(u16, "port")) orelse 8080;
    /// ```
    ///
    /// Bools need exactly `"true"` / `"false"`; ints and floats use `std.fmt` rules.
    pub fn tryGetOne(self: *const ArgMatches, comptime T: type, id: []const u8) error{InvalidValue}!?T {
        const raw = self.getOne(id) orelse return null;
        return parseValue(T, raw) orelse error.InvalidValue;
    }

    /// Builds the parse message for a bad typed value. Caller owns the returned error.
    pub fn valueError(self: *const ArgMatches, id: []const u8, raw: []const u8) !XarpError {
        const msg = try std.fmt.allocPrint(self.allocator, "invalid value '{s}' for '{s}'{s}", .{ raw, id, try_help_hint });
        return .{ .parse = msg };
    }

    /// First value parsed as `T`. Returns `null` when absent or when parsing fails.
    pub fn getOneParsed(self: *const ArgMatches, comptime T: type, id: []const u8) ?T {
        const raw = self.getOne(id) orelse return null;
        return parseValue(T, raw);
    }

    /// Fills `out` with values that parse; skips bad ones. Returns `null` when absent.
    pub fn getManyParsed(self: *const ArgMatches, comptime T: type, id: []const u8, out: []T) ?[]T {
        const raws = self.getMany(id) orelse return null;
        var n: usize = 0;
        for (raws) |raw| {
            if (n >= out.len) break;
            if (parseValue(T, raw)) |value| {
                out[n] = value;
                n += 1;
            }
        }
        return out[0..n];
    }

    /// Strict multi-value parse. Fails with `InvalidValue` on the first bad item, `ShortBuffer` when `out` is too small.
    pub fn tryGetMany(self: *const ArgMatches, comptime T: type, id: []const u8, out: []T) error{ InvalidValue, ShortBuffer }!?[]T {
        const raws = self.getMany(id) orelse return null;
        if (out.len < raws.len) return error.ShortBuffer;
        for (raws, 0..) |raw, i| {
            out[i] = parseValue(T, raw) orelse return error.InvalidValue;
        }
        return out[0..raws.len];
    }

    /// Matched subcommand name and its matches. `null` when no subcommand was passed.
    pub fn getSubcommand(self: *const ArgMatches) ?struct { []const u8, *const ArgMatches } {
        const sub = self.subcommand orelse return null;
        return .{ sub.name, sub.matches };
    }

    // Records a `.set_true` flag.
    fn setFlag(self: *ArgMatches, id: []const u8) !void {
        try self.flags.put(self.allocator, id, {});
    }

    // Stores a single value, replacing any prior one. Copies `raw`.
    fn setValue(self: *ArgMatches, id: []const u8, raw: []const u8) !void {
        const copy = try self.allocator.dupe(u8, raw);
        errdefer self.allocator.free(copy);
        if (self.values.getPtr(id)) |list| {
            for (list.items) |item| self.allocator.free(item);
            list.clearRetainingCapacity();
            try list.append(self.allocator, copy);
            return;
        }
        var list: std.ArrayListUnmanaged([]u8) = .empty;
        try list.append(self.allocator, copy);
        try self.values.put(self.allocator, id, list);
    }

    // Appends one value, keeping prior ones. Copies `raw`.
    fn appendValue(self: *ArgMatches, id: []const u8, raw: []const u8) !void {
        const copy = try self.allocator.dupe(u8, raw);
        errdefer self.allocator.free(copy);
        if (self.values.getPtr(id)) |list| {
            try list.append(self.allocator, copy);
            return;
        }
        var list: std.ArrayListUnmanaged([]u8) = .empty;
        try list.append(self.allocator, copy);
        try self.values.put(self.allocator, id, list);
    }
};

fn parseValue(comptime T: type, raw: []const u8) ?T {
    if (T == []const u8) return raw;
    if (T == bool) {
        if (std.mem.eql(u8, raw, "true")) return true;
        if (std.mem.eql(u8, raw, "false")) return false;
        return null;
    }
    switch (@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, raw, 10) catch null,
        .float => return std.fmt.parseFloat(T, raw) catch null,
        else => return null,
    }
}

/// App config and parser. Build it, add args, then call a `tryGetMatches*` variant.
pub const Xarp = struct {
    /// Backing allocator for help text and stored definitions.
    allocator: std.mem.Allocator,
    /// Program name. Shows in help, version, and usage lines.
    name: []const u8,
    /// Version string for `-V` / `--version`. `null` disables the flag.
    version: ?[]const u8 = null,
    /// One-line description at the top of `--help`.
    about: ?[]const u8 = null,
    /// Theme for help and error output.
    styles: Styles,
    /// Registered argument definitions. Fill with `addArg` / `addArgs`.
    args: std.ArrayListUnmanaged(Arg) = .empty,
    /// Registered nested commands. Fill with `addSubcommand`.
    subcommands: std.ArrayListUnmanaged(Xarp) = .empty,

    /// Starts a parser. `name` shows in help and version output.
    pub fn new(allocator: std.mem.Allocator, name: []const u8) Xarp {
        return .{
            .allocator = allocator,
            .name = name,
            .styles = Styles.styled(),
        };
    }

    /// Frees arg conflict lists and subcommands. Stored values live in `ArgMatches`, not here.
    pub fn deinit(self: *Xarp) void {
        for (self.args.items) |*arg| arg.conflicts_with.deinit(self.allocator);
        self.args.deinit(self.allocator);
        for (self.subcommands.items) |*sub| sub.deinit();
        self.subcommands.deinit(self.allocator);
    }

    /// Sets the version string shown by `-V` / `--version`.
    pub fn withVersion(self: Xarp, version: []const u8) Xarp {
        var next = self;
        next.version = version;
        return next;
    }

    /// Sets the one-line description shown at the top of `--help`.
    pub fn withAbout(self: Xarp, about: []const u8) Xarp {
        var next = self;
        next.about = about;
        return next;
    }

    /// Replaces the help/error theme. Use `Styles.plain()` to disable colors.
    pub fn withStyles(self: Xarp, styles: Styles) Xarp {
        var next = self;
        next.styles = styles;
        return next;
    }

    /// Adds one argument definition.
    pub fn addArg(self: *Xarp, arg: Arg) !void {
        try self.args.append(self.allocator, arg);
    }

    /// Adds several argument definitions at once.
    pub fn addArgs(self: *Xarp, args: []const Arg) !void {
        try self.args.appendSlice(self.allocator, args);
    }

    /// Registers a nested command. The first positional token matching `sub.name` routes to it.
    pub fn addSubcommand(self: *Xarp, sub: Xarp) !void {
        try self.subcommands.append(self.allocator, sub);
    }

    /// Parses `argv` (argv[0] is the program name) or exits.
    /// Help and version exit `0`; parse failures exit `2`.
    ///
    /// ```zig
    /// const argv = try init.minimal.args.toSlice(allocator);
    /// var matches = try app.getMatches(argv);
    /// ```
    pub fn getMatches(self: *const Xarp, argv: []const []const u8) !ArgMatches {
        switch (try self.parseImpl(argv, null)) {
            .matches => |matches| return matches,
            .err => |err| {
                const fd: i32 = if (err.isParse()) 2 else 1;
                writeAll(fd, err.message());
                if (err.isVersion()) writeAll(fd, "\n");
                err.deinit(self.allocator);
                std.process.exit(if (err.isParse()) 2 else 0);
            },
        }
    }

    /// Parses `argv` without exiting. Check `.matches` vs `.err` yourself.
    /// Call `outcome.deinit(allocator)` when done or you leak buffers.
    pub fn tryGetMatchesFrom(self: *const Xarp, argv: []const []const u8) !Outcome {
        return self.parseImpl(argv, null);
    }

    /// Parses with an explicit env map. `env_map` is the only env source; missing keys count as unset.
    ///
    /// ```zig
    /// var env: EnvMap = .empty;
    /// var out = try app.tryGetMatchesWithEnv(argv, &env);
    /// ```
    ///
    /// Build the map from `init.environ_map` in real code. Tests pass a small literal map
    /// so host variables don't leak into results.
    pub fn tryGetMatchesWithEnv(self: *const Xarp, argv: []const []const u8, env_map: *const EnvMap) !Outcome {
        return self.parseImpl(argv, env_map);
    }

    fn isTruthy(val: []const u8) bool {
        return std.mem.eql(u8, val, "1") or std.ascii.eqlIgnoreCase(val, "true");
    }

    fn lookupEnv(env_map: ?*const EnvMap, key: []const u8) ?[]const u8 {
        if (env_map) |map| return map.get(key);
        return processGetenv(key);
    }

    fn processGetenv(key: []const u8) ?[]const u8 {
        var terminated: [256]u8 = undefined;
        if (key.len >= terminated.len) return null;
        @memcpy(terminated[0..key.len], key);
        terminated[key.len] = 0;
        const value = std.c.getenv(terminated[0..key.len :0]) orelse return null;
        return std.mem.span(value);
    }

    fn abandon(parsed: *ArgMatches, err: XarpError) Outcome {
        parsed.deinit();
        return .{ .err = err };
    }

    fn parseImpl(self: *const Xarp, args: []const []const u8, env_map: ?*const EnvMap) !Outcome {
        if (try self.validateDefinitions()) |err| return .{ .err = err };

        var matches = ArgMatches{ .allocator = self.allocator };
        errdefer matches.deinit();
        var explicit: std.StringHashMapUnmanaged(void) = .empty;
        defer explicit.deinit(self.allocator);
        const tokens = if (args.len == 0) args else args[1..];

        var effective: std.ArrayListUnmanaged(Arg) = .empty;
        defer effective.deinit(self.allocator);
        try effective.appendSlice(self.allocator, self.args.items);

        const has_help_collision = hasCollision(effective.items, "help", 'h', "help");
        if (!has_help_collision) {
            try effective.append(self.allocator, Arg.new("help").withShort('h').withLong("help").withHelp("Print help information").withAction(.set_true));
        }
        const has_version_collision = hasCollision(effective.items, "version", 'V', "version");
        if (self.version != null and !has_version_collision) {
            try effective.append(self.allocator, Arg.new("version").withShort('V').withLong("version").withHelp("Print version information").withAction(.set_true));
        }
        const help_injected = !has_help_collision;
        const version_injected = self.version != null and !has_version_collision;

        var positional_idx: usize = 0;
        var positional_ids: std.ArrayListUnmanaged(usize) = .empty;
        defer positional_ids.deinit(self.allocator);
        for (effective.items, 0..) |arg, idx| {
            if (arg.isPositional()) try positional_ids.append(self.allocator, idx);
        }
        if (positional_ids.items.len > 1) {
            for (positional_ids.items, 0..) |idx, n| {
                if (effective.items[idx].action == .append and n + 1 != positional_ids.items.len) {
                    return abandon(&matches, try self.parseError("the argument '{s}' with Append action must be the last positional", .{effective.items[idx].id}));
                }
            }
        }

        var i: usize = 0;
        var only_positionals = false;
        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];
            if (std.mem.eql(u8, token, "--") and !only_positionals) {
                only_positionals = true;
                continue;
            }

            if (!only_positionals and !std.mem.startsWith(u8, token, "-") and positional_idx == 0) {
                if (findSub(self.subcommands.items, token)) |sub| {
                    if (try self.applyEnvDefaults(effective.items, &matches, &explicit, env_map, true)) |err| return abandon(&matches, err);
                    if (try self.validateValues(effective.items, &matches, &explicit)) |err| return abandon(&matches, err);
                    const child = try sub.parseImpl(tokens[i..], env_map);
                    switch (child) {
                        .err => |err| return abandon(&matches, err),
                        .matches => |child_matches| {
                            const boxed = try self.allocator.create(ArgMatches);
                            boxed.* = child_matches;
                            matches.subcommand = .{
                                .name = try self.allocator.dupe(u8, sub.name),
                                .matches = boxed,
                            };
                            return .{ .matches = matches };
                        },
                    }
                }
            }

            if (!only_positionals and std.mem.startsWith(u8, token, "--")) {
                const long_name = token[2..];
                const name, const inline_val = splitOnce(long_name, '=');
                const matched = findLong(effective.items, name) orelse {
                    return abandon(&matches, try self.parseError("unexpected argument '--{s}' found", .{name}));
                };
                if (matched.action == .set_true and inline_val != null) {
                    return abandon(&matches, try self.parseError("argument '--{s}' does not take a value", .{name}));
                }
                if (std.mem.eql(u8, matched.id, "help") and help_injected) {
                    return abandon(&matches, .{ .help = try self.renderHelp() });
                }
                if (std.mem.eql(u8, matched.id, "version") and version_injected) {
                    return abandon(&matches, .{ .version = try self.renderVersion() });
                }
                switch (matched.action) {
                    .set_true => {
                        try matches.setFlag(matched.id);
                        try explicit.put(self.allocator, matched.id, {});
                    },
                    .set, .append => {
                        const value = inline_val orelse blk: {
                            i += 1;
                            if (i >= tokens.len or std.mem.eql(u8, tokens[i], "--")) {
                                return abandon(&matches, try self.parseError("argument '--{s}' requires a value", .{name}));
                            }
                            break :blk tokens[i];
                        };
                        if (matched.action == .set) {
                            try matches.setValue(matched.id, value);
                        } else {
                            try matches.appendValue(matched.id, value);
                        }
                        try explicit.put(self.allocator, matched.id, {});
                    },
                }
            } else if (!only_positionals and token.len > 1 and token[0] == '-') {
                var c_idx: usize = 1;
                while (c_idx < token.len) {
                    const short_char = token[c_idx];
                    const matched = findShort(effective.items, short_char) orelse {
                        return abandon(&matches, try self.parseError("unexpected argument '-{c}' found", .{short_char}));
                    };
                    switch (matched.action) {
                        .set_true => {
                            if (std.mem.eql(u8, matched.id, "help") and help_injected) {
                                return abandon(&matches, .{ .help = try self.renderHelp() });
                            }
                            if (std.mem.eql(u8, matched.id, "version") and version_injected) {
                                return abandon(&matches, .{ .version = try self.renderVersion() });
                            }
                            try matches.setFlag(matched.id);
                            try explicit.put(self.allocator, matched.id, {});
                            c_idx += 1;
                        },
                        .set, .append => {
                            const raw_value = if (c_idx + 1 < token.len) token[c_idx + 1 ..] else blk: {
                                i += 1;
                                if (i >= tokens.len or std.mem.eql(u8, tokens[i], "--")) {
                                    return abandon(&matches, try self.parseError("argument '-{c}' requires a value", .{short_char}));
                                }
                                break :blk tokens[i];
                            };
                            const once = if (std.mem.startsWith(u8, raw_value, "=")) raw_value[1..] else raw_value;
                            if (matched.action == .set) {
                                try matches.setValue(matched.id, once);
                            } else {
                                try matches.appendValue(matched.id, once);
                            }
                            try explicit.put(self.allocator, matched.id, {});
                            break;
                        },
                    }
                }
            } else if (positional_idx < positional_ids.items.len) {
                const pos = effective.items[positional_ids.items[positional_idx]];
                switch (pos.action) {
                    .set_true => {
                        try matches.setFlag(pos.id);
                        try explicit.put(self.allocator, pos.id, {});
                        positional_idx += 1;
                    },
                    .set => {
                        try matches.setValue(pos.id, token);
                        try explicit.put(self.allocator, pos.id, {});
                        positional_idx += 1;
                    },
                    .append => {
                        try matches.appendValue(pos.id, token);
                        try explicit.put(self.allocator, pos.id, {});
                    },
                }
            } else {
                return abandon(&matches, try self.parseError("unexpected argument '{s}' found", .{token}));
            }
        }

        if (try self.applyEnvDefaults(effective.items, &matches, &explicit, env_map, false)) |err| return abandon(&matches, err);
        if (try self.validateValues(effective.items, &matches, &explicit)) |err| return abandon(&matches, err);
        return .{ .matches = matches };
    }

    fn validateDefinitions(self: *const Xarp) !?XarpError {
        if (try self.validateNames()) |err| return err;
        if (try self.validateFlags()) |err| return err;
        if (try self.validateRelations()) |err| return err;
        return null;
    }

    fn validateNames(self: *const Xarp) !?XarpError {
        if (self.name.len == 0) return try self.parseError("application name must not be empty", .{});
        var ids: std.StringHashMapUnmanaged(void) = .empty;
        defer ids.deinit(self.allocator);
        for (self.args.items) |arg| {
            if (arg.id.len == 0) return try self.parseError("argument id must not be empty", .{});
            if (ids.contains(arg.id)) return try self.parseError("duplicate argument id '{s}' found", .{arg.id});
            try ids.put(self.allocator, arg.id, {});
        }
        var names: std.StringHashMapUnmanaged(void) = .empty;
        defer names.deinit(self.allocator);
        for (self.subcommands.items) |sub| {
            if (sub.name.len == 0 or std.mem.startsWith(u8, sub.name, "-")) {
                return try self.parseError("invalid subcommand name '{s}': must be non-empty and not start with '-'", .{sub.name});
            }
            if (names.contains(sub.name)) return try self.parseError("duplicate subcommand '{s}' found", .{sub.name});
            try names.put(self.allocator, sub.name, {});
        }
        return null;
    }

    fn validateFlags(self: *const Xarp) !?XarpError {
        var shorts: std.AutoHashMapUnmanaged(u8, void) = .empty;
        defer shorts.deinit(self.allocator);
        for (self.args.items) |arg| {
            if (arg.short) |short| {
                if (short == '-' or short == '=' or std.ascii.isWhitespace(short) or std.ascii.isControl(short)) {
                    return try self.parseError("invalid short flag '-{c}' for '{s}': must not be '-', '=' or whitespace", .{ short, arg.id });
                }
                if (shorts.contains(short)) return try self.parseError("duplicate short flag '-{c}' found", .{short});
                try shorts.put(self.allocator, short, {});
            }
        }
        var longs: std.StringHashMapUnmanaged(void) = .empty;
        defer longs.deinit(self.allocator);
        for (self.args.items) |arg| {
            if (arg.long) |long| {
                if (long.len == 0 or std.mem.startsWith(u8, long, "-") or std.mem.indexOfScalar(u8, long, '=') != null or hasSpace(long)) {
                    return try self.parseError("invalid long flag '--{s}' for '{s}'", .{ long, arg.id });
                }
                if (longs.contains(long)) return try self.parseError("duplicate long flag '--{s}' found", .{long});
                try longs.put(self.allocator, long, {});
            }
        }
        return null;
    }

    fn validateRelations(self: *const Xarp) !?XarpError {
        var ids: std.StringHashMapUnmanaged(void) = .empty;
        defer ids.deinit(self.allocator);
        for (self.args.items) |arg| try ids.put(self.allocator, arg.id, {});
        const help_collision = hasCollision(self.args.items, "help", 'h', "help");
        const version_collision = hasCollision(self.args.items, "version", 'V', "version");
        for (self.args.items) |arg| {
            for (arg.conflicts_with.items) |conflict_id| {
                const known = ids.contains(conflict_id) or
                    (!help_collision and std.mem.eql(u8, conflict_id, "help")) or
                    (self.version != null and !version_collision and std.mem.eql(u8, conflict_id, "version"));
                if (!known) {
                    return try self.parseError("the argument '{s}' conflicts with unknown argument '{s}'", .{ arg.id, conflict_id });
                }
            }
        }
        var seen_optional = false;
        for (self.args.items) |arg| {
            if (!arg.isPositional()) continue;
            if (arg.required) {
                if (seen_optional) {
                    return try self.parseError("required positional '{s}' must not follow an optional positional", .{arg.id});
                }
            } else seen_optional = true;
        }
        return null;
    }

    fn applyEnvDefaults(
        self: *const Xarp,
        effective_args: []const Arg,
        matches: *ArgMatches,
        explicit: *std.StringHashMapUnmanaged(void),
        env_map: ?*const EnvMap,
        skip_required: bool,
    ) !?XarpError {
        for (effective_args) |arg| {
            if (matches.values.contains(arg.id) or matches.flags.contains(arg.id)) continue;
            if (arg.env) |env_key| {
                if (lookupEnv(env_map, env_key)) |env_val| {
                    if (arg.action == .set_true) {
                        if (isTruthy(env_val)) {
                            try matches.setFlag(arg.id);
                            try explicit.put(self.allocator, arg.id, {});
                        } else if (arg.required and !skip_required) {
                            return try self.parseError("the required argument '{s}' was not provided", .{arg.id});
                        }
                        continue;
                    }
                    try matches.setValue(arg.id, env_val);
                    try explicit.put(self.allocator, arg.id, {});
                    continue;
                }
            }
            if (arg.default_value) |default| {
                if (arg.action == .set_true) {
                    if (isTruthy(default)) try matches.setFlag(arg.id);
                } else {
                    try matches.setValue(arg.id, default);
                }
            } else if (arg.required and !skip_required) {
                return try self.parseError("the required argument '{s}' was not provided", .{arg.id});
            }
        }
        return null;
    }

    fn validateValues(
        self: *const Xarp,
        effective_args: []const Arg,
        matches: *const ArgMatches,
        explicit: *const std.StringHashMapUnmanaged(void),
    ) !?XarpError {
        for (effective_args) |arg| {
            if (arg.possible_values.len == 0) continue;
            const vals = matches.getMany(arg.id) orelse continue;
            for (vals) |value| {
                if (!containsString(arg.possible_values, value)) {
                    const allowed = try join(self.allocator, arg.possible_values);
                    defer self.allocator.free(allowed);
                    return try self.parseError("invalid value '{s}' for '{s}'. [possible values: {s}]", .{ value, arg.id, allowed });
                }
            }
        }
        for (effective_args) |arg| {
            if (!explicit.contains(arg.id)) continue;
            for (arg.conflicts_with.items) |conflict_id| {
                if (explicit.contains(conflict_id)) {
                    return try self.parseError("the argument '{s}' cannot be used with '{s}'", .{ arg.id, conflict_id });
                }
            }
        }
        return null;
    }

    /// Writes `name version` to stdout. Caller keeps ownership; nothing to free.
    pub fn printVersion(self: *const Xarp) !void {
        const text = try self.renderVersion();
        defer self.allocator.free(text);
        writeAll(1, text);
        writeAll(1, "\n");
    }

    /// Writes rendered help to stdout. Caller keeps ownership; nothing to free.
    pub fn printHelp(self: *const Xarp) !void {
        const text = try self.renderHelp();
        defer self.allocator.free(text);
        writeAll(1, text);
    }

    /// Renders `name version`. Caller must free the returned slice.
    pub fn renderVersion(self: *const Xarp) ![]u8 {
        var buf = Buf.init(self.allocator);
        errdefer buf.deinit();
        try buf.paint(self.styles.literal, self.name);
        try buf.write(" ");
        try buf.paint(self.styles.placeholder, self.version orelse "unknown");
        return buf.toOwned();
    }

    /// Renders full help text. Caller must free the returned slice.
    pub fn renderHelp(self: *const Xarp) ![]u8 {
        var buf = Buf.init(self.allocator);
        errdefer buf.deinit();
        const bar = self.styles.header;
        const badge = self.styles.literal;
        const pill = self.styles.placeholder;
        const about_style = self.styles.muted;
        const arrow = self.styles.header;
        const title = self.styles.header;
        const prompt = self.styles.muted;
        const cmd = self.styles.literal;
        const sub_syntax = self.styles.usage;
        const pos_syntax = self.styles.placeholder;
        const opt_syntax = self.styles.usage;
        const cmd_item = self.styles.literal;
        const arg_item = self.styles.placeholder;
        const opt_flag = self.styles.literal;
        const opt_val = self.styles.placeholder;
        const item_help = Style.new();
        const req_tag = self.styles.warning;
        const opt_tag = self.styles.muted;
        const def_tag = self.styles.muted;
        const tip_badge = self.styles.valid;
        const tip_text = self.styles.muted;

        try buf.newline();
        const version = self.version orelse "unknown";
        var upper: [128]u8 = undefined;
        const name_badge = if (self.name.len + 2 <= upper.len) blk: {
            upper[0] = ' ';
            for (self.name, 0..) |c, i| upper[i + 1] = std.ascii.toUpper(c);
            upper[self.name.len + 1] = ' ';
            break :blk upper[0 .. self.name.len + 2];
        } else self.name;
        var ver_buf: [160]u8 = undefined;
        const ver_text = std.fmt.bufPrint(&ver_buf, "v{s}", .{version}) catch version;
        try buf.paint(bar, "┃");
        try buf.write(" ");
        try buf.paint(badge, name_badge);
        try buf.write("  ");
        try buf.paint(pill, ver_text);
        try buf.write(" ");
        if (self.about) |about| {
            try buf.write(" ");
            try buf.paint(about_style, about);
        }
        try buf.newline();
        try buf.paint(bar, "┃");
        try buf.newline();
        try buf.paint(bar, "┃");
        try buf.write(" ");
        try buf.paint(prompt, "$");
        try buf.write(" ");
        try buf.paint(cmd, self.name);
        if (hasOptional(self.args.items)) {
            try buf.write(" ");
            try buf.paint(opt_syntax, "[OPTIONS]");
        }
        for (self.args.items) |pos| {
            if (!pos.isPositional()) continue;
            const val = pos.value_name orelse pos.id;
            try buf.write(" ");
            if (pos.required) {
                var wrapped: [128]u8 = undefined;
                if (val.len + 2 <= wrapped.len) {
                    wrapped[0] = '<';
                    @memcpy(wrapped[1..][0..val.len], val);
                    wrapped[val.len + 1] = '>';
                    try buf.paint(pos_syntax, wrapped[0 .. val.len + 2]);
                } else try buf.paint(pos_syntax, val);
            } else {
                var wrapped: [128]u8 = undefined;
                if (val.len + 2 <= wrapped.len) {
                    wrapped[0] = '[';
                    @memcpy(wrapped[1..][0..val.len], val);
                    wrapped[val.len + 1] = ']';
                    try buf.paint(opt_syntax, wrapped[0 .. val.len + 2]);
                } else try buf.paint(opt_syntax, val);
            }
        }
        if (self.subcommands.items.len != 0) {
            try buf.write(" ");
            try buf.paint(sub_syntax, "[COMMAND]");
        }
        try buf.newline();
        try buf.newline();

        if (self.subcommands.items.len != 0) {
            try buf.paint(arrow, "›");
            try buf.write(" ");
            try buf.paint(title, "Commands");
            try buf.newline();
            for (self.subcommands.items) |sub| {
                try buf.write("  ");
                try buf.paintPadded(cmd_item, sub.name, 16);
                try buf.write("  ");
                try buf.write(sub.about orelse "");
                try buf.newline();
            }
            try buf.newline();
        }

        var positionals: usize = 0;
        for (self.args.items) |arg| {
            if (arg.isPositional()) positionals += 1;
        }
        if (positionals != 0) {
            try buf.paint(arrow, "›");
            try buf.write(" ");
            try buf.paint(title, "Arguments");
            try buf.newline();
            for (self.args.items) |arg| {
                if (!arg.isPositional()) continue;
                const name = arg.value_name orelse arg.id;
                try buf.write("  ");
                try buf.paintPadded(arg_item, name, 16);
                try buf.write("  ");
                try buf.paintPadded(item_help, arg.help orelse "", 44);
                try buf.write(" ");
                try buf.paint(if (arg.required) req_tag else opt_tag, if (arg.required) "[required]" else "[optional]");
                if (arg.default_value) |default| {
                    try buf.write(" ");
                    try buf.paint(def_tag, "(default: \"");
                    try buf.paint(def_tag, default);
                    try buf.paint(def_tag, "\")");
                }
                try buf.newline();
            }
            try buf.newline();
        }

        try buf.paint(arrow, "›");
        try buf.write(" ");
        try buf.paint(title, "Flags & Options");
        try buf.newline();
        for (self.args.items) |arg| {
            if (arg.isPositional()) continue;
            try buf.write("  ");
            if (arg.short) |short| {
                try buf.paint(opt_flag, "-");
                try buf.paint(opt_flag, &.{short});
                try buf.paint(opt_flag, ", ");
            } else try buf.paint(opt_flag, "    ");
            if (arg.long) |long| {
                try buf.paint(opt_flag, "--");
                try buf.paint(opt_flag, long);
            }
            if (arg.action != .set_true) {
                try buf.write(" ");
                try buf.paint(opt_val, "<");
                try buf.paint(opt_val, arg.value_name orelse "VAL");
                try buf.paint(opt_val, ">");
            }
            try buf.write("  ");
            try buf.paintPadded(item_help, arg.help orelse "", 40);
            try buf.write(" ");
            if (arg.required) try buf.paint(req_tag, "[required]");
            if (arg.default_value) |default| {
                try buf.write(" ");
                try buf.paint(def_tag, "(default: \"");
                try buf.paint(def_tag, default);
                try buf.paint(def_tag, "\")");
            }
            try buf.newline();
        }
        if (!hasCollision(self.args.items, "help", 'h', "help")) {
            try buf.write("  ");
            try buf.paint(opt_flag, "-h, --help");
            try buf.write("  ");
            try buf.paint(item_help, "Show this help guide");
            try buf.newline();
        }
        if (self.version != null and !hasCollision(self.args.items, "version", 'V', "version")) {
            try buf.write("  ");
            try buf.paint(opt_flag, "-V, --version");
            try buf.write("  ");
            try buf.paint(item_help, "Show version number");
            try buf.newline();
        }
        if (self.subcommands.items.len != 0) {
            try buf.newline();
            try buf.write("  ");
            try buf.paint(tip_badge, " TIP ");
            try buf.write(" ");
            try buf.paint(tip_text, "Run");
            try buf.write(" ");
            try buf.paint(opt_flag, self.name);
            try buf.paint(opt_flag, " <command> --help");
            try buf.write(" ");
            try buf.paint(tip_text, "for details on a specific subcommand.");
            try buf.newline();
        }
        try buf.newline();
        return buf.toOwned();
    }

    fn parseError(self: *const Xarp, comptime fmt: []const u8, args: anytype) !XarpError {
        const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(msg);
        var buf = Buf.init(self.allocator);
        errdefer buf.deinit();
        try buf.paint(self.styles.@"error", "error");
        try buf.write(": ");
        try buf.write(msg);
        try buf.write("\n\nFor more information, try '");
        try buf.paint(self.styles.literal, "--help");
        try buf.write("'.");
        return .{ .parse = try buf.toOwned() };
    }
};

fn writeAll(fd: i32, bytes: []const u8) void {
    var left = bytes;
    while (left.len != 0) {
        const n = std.c.write(fd, left.ptr, left.len);
        if (n <= 0) return;
        left = left[@intCast(n)..];
    }
}

fn hasCollision(args: []const Arg, id: []const u8, short: u8, long: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.id, id)) return true;
        if (arg.short == short) return true;
        if (arg.long) |name| if (std.mem.eql(u8, name, long)) return true;
    }
    return false;
}

fn hasOptional(args: []const Arg) bool {
    for (args) |arg| if (!arg.isPositional()) return true;
    return false;
}

fn findSub(subs: []const Xarp, name: []const u8) ?*const Xarp {
    for (subs) |*sub| if (std.mem.eql(u8, sub.name, name)) return sub;
    return null;
}

fn findLong(args: []const Arg, name: []const u8) ?Arg {
    for (args) |arg| {
        if (arg.long) |long| if (std.mem.eql(u8, long, name)) return arg;
    }
    return null;
}

fn findShort(args: []const Arg, short: u8) ?Arg {
    for (args) |arg| if (arg.short == short) return arg;
    return null;
}

fn splitOnce(text: []const u8, mark: u8) struct { []const u8, ?[]const u8 } {
    const idx = std.mem.indexOfScalar(u8, text, mark) orelse return .{ text, null };
    return .{ text[0..idx], text[idx + 1 ..] };
}

fn containsString(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn hasSpace(text: []const u8) bool {
    for (text) |c| if (std.ascii.isWhitespace(c) or std.ascii.isControl(c)) return true;
    return false;
}

fn join(allocator: std.mem.Allocator, items: []const []const u8) ![]u8 {
    var len: usize = 0;
    for (items, 0..) |item, i| {
        len += item.len;
        if (i + 1 != items.len) len += 2;
    }
    const out = try allocator.alloc(u8, len);
    var n: usize = 0;
    for (items, 0..) |item, i| {
        @memcpy(out[n..][0..item.len], item);
        n += item.len;
        if (i + 1 != items.len) {
            out[n] = ',';
            out[n + 1] = ' ';
            n += 2;
        }
    }
    return out;
}

const Buf = struct {
    list: std.ArrayListUnmanaged(u8) = .empty,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Buf {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Buf) void {
        self.list.deinit(self.allocator);
    }

    fn toOwned(self: *Buf) ![]u8 {
        return self.list.toOwnedSlice(self.allocator);
    }

    fn write(self: *Buf, text: []const u8) !void {
        try self.list.appendSlice(self.allocator, text);
    }

    fn newline(self: *Buf) !void {
        try self.write("\n");
    }

    fn paint(self: *Buf, style: Style, text: []const u8) !void {
        if (style.isPlain()) {
            try self.write(text);
            return;
        }
        var tmp: [96]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&tmp);
        try style.format(&writer);
        try self.write(writer.buffered());
        try self.write(text);
        try self.write(RESET);
    }

    fn paintPadded(self: *Buf, style: Style, text: []const u8, width: usize) !void {
        if (text.len >= width) {
            try self.paint(style, text);
            return;
        }
        const padded = try self.allocator.alloc(u8, width);
        defer self.allocator.free(padded);
        @memcpy(padded[0..text.len], text);
        @memset(padded[text.len..], ' ');
        try self.paint(style, padded);
    }
};

// === Tests ===

fn takeMatches(outcome: *Outcome) !*ArgMatches {
    switch (outcome.*) {
        .matches => return &outcome.matches,
        .err => |err| {
            std.debug.print("{s}\n", .{err.message()});
            return error.UnexpectedParse;
        },
    }
}

test "set last wins and append collects" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("o").withLong("opt"));
    var set_out = try app.tryGetMatchesFrom(&.{ "t", "--opt", "a", "--opt=b" });
    defer set_out.deinit(ally);
    const set = try takeMatches(&set_out);
    try std.testing.expectEqualStrings("b", set.getOne("o").?);

    var append_app = Xarp.new(ally, "t");
    defer append_app.deinit();
    try append_app.addArg(Arg.new("h").withShort('H').withAction(.append));
    var append_out = try append_app.tryGetMatchesFrom(&.{ "t", "-H", "a", "-Hb" });
    defer append_out.deinit(ally);
    const append = try takeMatches(&append_out);
    const many = append.getMany("h").?;
    try std.testing.expectEqual(@as(usize, 2), many.len);
    try std.testing.expectEqualStrings("a", many[0]);
    try std.testing.expectEqualStrings("b", many[1]);
}

test "short attached equals and missing value" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("p").withShort('p'));
    var empty = try app.tryGetMatchesFrom(&.{ "t", "-p=" });
    defer empty.deinit(ally);
    try std.testing.expectEqualStrings("", (try takeMatches(&empty)).getOne("p").?);

    var doubled = try app.tryGetMatchesFrom(&.{ "t", "-p==x" });
    defer doubled.deinit(ally);
    try std.testing.expectEqualStrings("=x", (try takeMatches(&doubled)).getOne("p").?);

    var missing = try app.tryGetMatchesFrom(&.{ "t", "-p" });
    defer missing.deinit(ally);
    try std.testing.expect(missing.err.isParse());
    try std.testing.expect(std.mem.indexOf(u8, missing.err.message(), "-p") != null);
}

test "bundles flags and trailing values" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("v").withShort('v').withAction(.set_true));
    try app.addArg(Arg.new("p").withShort('p'));
    var out = try app.tryGetMatchesFrom(&.{ "t", "-vp8080" });
    defer out.deinit(ally);
    const matches = try takeMatches(&out);
    try std.testing.expect(matches.getFlag("v"));
    try std.testing.expectEqualStrings("8080", matches.getOne("p").?);
}

test "positionals defaults delimiter and required" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("src"));
    try app.addArg(Arg.new("dst"));
    var out = try app.tryGetMatchesFrom(&.{ "t", "a.txt", "b.txt" });
    defer out.deinit(ally);
    const matches = try takeMatches(&out);
    try std.testing.expectEqualStrings("a.txt", matches.getOne("src").?);
    try std.testing.expectEqualStrings("b.txt", matches.getOne("dst").?);

    var lone = Xarp.new(ally, "t");
    defer lone.deinit();
    try lone.addArg(Arg.new("input"));
    var dash = try lone.tryGetMatchesFrom(&.{ "t", "-" });
    defer dash.deinit(ally);
    try std.testing.expectEqualStrings("-", (try takeMatches(&dash)).getOne("input").?);

    var extra = try lone.tryGetMatchesFrom(&.{ "t", "a", "b" });
    defer extra.deinit(ally);
    try std.testing.expect(extra.err.isParse());

    var with_default = Xarp.new(ally, "t");
    defer with_default.deinit();
    try with_default.addArg(Arg.new("input").withDefault("stdin"));
    var filled = try with_default.tryGetMatchesFrom(&.{"t"});
    defer filled.deinit(ally);
    try std.testing.expectEqualStrings("stdin", (try takeMatches(&filled)).getOne("input").?);

    var files = Xarp.new(ally, "t");
    defer files.deinit();
    try files.addArg(Arg.new("files").withAction(.append));
    var after = try files.tryGetMatchesFrom(&.{ "t", "--", "-a", "--help" });
    defer after.deinit(ally);
    const got = (try takeMatches(&after)).getMany("files").?;
    try std.testing.expectEqualStrings("-a", got[0]);
    try std.testing.expectEqualStrings("--help", got[1]);
}

test "env precedence and conflicts" {
    const ally = std.testing.allocator;
    var env_map: EnvMap = .empty;
    defer env_map.deinit(ally);
    try env_map.put(ally, "K", "env");

    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("o").withLong("opt").withEnv("K").withDefault("dflt"));
    var from_env = try app.tryGetMatchesWithEnv(&.{"t"}, &env_map);
    defer from_env.deinit(ally);
    try std.testing.expectEqualStrings("env", (try takeMatches(&from_env)).getOne("o").?);

    var from_cli = try app.tryGetMatchesWithEnv(&.{ "t", "--opt", "cli" }, &env_map);
    defer from_cli.deinit(ally);
    try std.testing.expectEqualStrings("cli", (try takeMatches(&from_cli)).getOne("o").?);

    var flags = Xarp.new(ally, "t");
    defer flags.deinit();
    var left = Arg.new("a").withLong("aaa");
    try left.conflictsWith(ally, "b");
    try flags.addArg(left);
    try flags.addArg(Arg.new("b").withLong("bbb"));
    var bad = try flags.tryGetMatchesFrom(&.{ "t", "--aaa", "1", "--bbb", "2" });
    defer bad.deinit(ally);
    try std.testing.expect(bad.err.isParse());
    var ok = try flags.tryGetMatchesFrom(&.{ "t", "--bbb", "2" });
    defer ok.deinit(ally);
    try std.testing.expectEqualStrings("2", (try takeMatches(&ok)).getOne("b").?);
}

test "subcommands help and version" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "demo").withVersion("3.2.1").withAbout("d");
    defer app.deinit();
    try app.addArg(Arg.new("input").setRequired(true));
    var run = Xarp.new(ally, "run").withAbout("run it");
    try run.addArg(Arg.new("fast").withLong("fast").withAction(.set_true));
    try app.addSubcommand(run);

    var routed = try app.tryGetMatchesFrom(&.{ "demo", "run", "--fast" });
    defer routed.deinit(ally);
    const matches = try takeMatches(&routed);
    const name, const sub = matches.getSubcommand().?;
    try std.testing.expectEqualStrings("run", name);
    try std.testing.expect(sub.getFlag("fast"));

    var help = try app.tryGetMatchesFrom(&.{ "demo", "--help" });
    defer help.deinit(ally);
    try std.testing.expect(help.err.isHelp());
    const text = help.err.message();
    try std.testing.expect(std.mem.indexOf(u8, text, "demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Commands") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Arguments") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Flags & Options") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "-h, --help") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "-V, --version") != null);

    var version = try app.tryGetMatchesFrom(&.{ "demo", "--version" });
    defer version.deinit(ally);
    try std.testing.expect(version.err.isVersion());
    try std.testing.expect(std.mem.indexOf(u8, version.err.message(), "3.2.1") != null);

    var custom = Xarp.new(ally, "t");
    defer custom.deinit();
    try custom.addArg(Arg.new("myhelp").withLong("help").withAction(.set_true));
    var ordinary = try custom.tryGetMatchesFrom(&.{ "t", "--help" });
    defer ordinary.deinit(ally);
    try std.testing.expect((try takeMatches(&ordinary)).getFlag("myhelp"));
}

test "possible values and typed get" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("m").withLong("mode").withPossibleValues(&.{ "fast", "safe" }));
    var ok = try app.tryGetMatchesFrom(&.{ "t", "--mode", "safe" });
    defer ok.deinit(ally);
    try std.testing.expectEqualStrings("safe", (try takeMatches(&ok)).getOne("m").?);
    var bad = try app.tryGetMatchesFrom(&.{ "t", "--mode", "wild" });
    defer bad.deinit(ally);
    try std.testing.expect(bad.err.isParse());
    try std.testing.expect(std.mem.indexOf(u8, bad.err.message(), "wild") != null);

    var nums = Xarp.new(ally, "t");
    defer nums.deinit();
    try nums.addArg(Arg.new("p").withShort('p'));
    var parsed = try nums.tryGetMatchesFrom(&.{ "t", "-p", "8080" });
    defer parsed.deinit(ally);
    const matches = try takeMatches(&parsed);
    try std.testing.expectEqual(@as(u16, 8080), (try matches.tryGetOne(u16, "p")).?);
    try std.testing.expectEqual(@as(?u16, null), try matches.tryGetOne(u16, "missing"));
}

test "required append and non-last append are rejected" {
    const ally = std.testing.allocator;
    var missing = Xarp.new(ally, "t");
    defer missing.deinit();
    try missing.addArg(Arg.new("files").withAction(.append).setRequired(true));
    var none = try missing.tryGetMatchesFrom(&.{"t"});
    defer none.deinit(ally);
    try std.testing.expect(none.err.isParse());
    var one = try missing.tryGetMatchesFrom(&.{ "t", "only" });
    defer one.deinit(ally);
    try std.testing.expectEqualStrings("only", (try takeMatches(&one)).getMany("files").?[0]);

    var bad = Xarp.new(ally, "t");
    defer bad.deinit();
    try bad.addArg(Arg.new("files").withAction(.append));
    try bad.addArg(Arg.new("other"));
    var rejected = try bad.tryGetMatchesFrom(&.{ "t", "a" });
    defer rejected.deinit(ally);
    try std.testing.expect(rejected.err.isParse());
    try std.testing.expect(std.mem.indexOf(u8, rejected.err.message(), "last positional") != null);
}

test "flags defaults and case-insensitive env" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("v").withShort('v').withLong("verbose").withAction(.set_true));
    var absent = try app.tryGetMatchesFrom(&.{"t"});
    defer absent.deinit(ally);
    try std.testing.expect(!(try takeMatches(&absent)).getFlag("v"));
    var present = try app.tryGetMatchesFrom(&.{ "t", "-v" });
    defer present.deinit(ally);
    try std.testing.expect((try takeMatches(&present)).getFlag("v"));

    var env_map: EnvMap = .empty;
    defer env_map.deinit(ally);
    try env_map.put(ally, "K", "TRUE");
    var flagged = Xarp.new(ally, "t");
    defer flagged.deinit();
    try flagged.addArg(Arg.new("f").withLong("flag").withAction(.set_true).withEnv("K"));
    var from_env = try flagged.tryGetMatchesWithEnv(&.{"t"}, &env_map);
    defer from_env.deinit(ally);
    try std.testing.expect((try takeMatches(&from_env)).getFlag("f"));

    var falsy = Xarp.new(ally, "t");
    defer falsy.deinit();
    try falsy.addArg(Arg.new("f").withLong("flag").withAction(.set_true).withDefault("false"));
    var unset = try falsy.tryGetMatchesFrom(&.{"t"});
    defer unset.deinit(ally);
    try std.testing.expect(!(try takeMatches(&unset)).getFlag("f"));
}

test "required option env empty string and append precedence" {
    const ally = std.testing.allocator;
    var required = Xarp.new(ally, "t");
    defer required.deinit();
    try required.addArg(Arg.new("c").withLong("cfg").setRequired(true));
    var empty_env: EnvMap = .empty;
    defer empty_env.deinit(ally);
    var missing = try required.tryGetMatchesWithEnv(&.{"t"}, &empty_env);
    defer missing.deinit(ally);
    try std.testing.expect(missing.err.isParse());

    try empty_env.put(ally, "K", "");
    var optional = Xarp.new(ally, "t");
    defer optional.deinit();
    try optional.addArg(Arg.new("o").withLong("opt").withEnv("K"));
    var blank = try optional.tryGetMatchesWithEnv(&.{"t"}, &empty_env);
    defer blank.deinit(ally);
    try std.testing.expectEqualStrings("", (try takeMatches(&blank)).getOne("o").?);

    var env_map: EnvMap = .empty;
    defer env_map.deinit(ally);
    try env_map.put(ally, "K", "env");
    var append = Xarp.new(ally, "t");
    defer append.deinit();
    try append.addArg(Arg.new("h").withLong("header").withAction(.append).withEnv("K").withDefault("dflt"));
    var cli = try append.tryGetMatchesWithEnv(&.{ "t", "--header", "cli" }, &env_map);
    defer cli.deinit(ally);
    const many = (try takeMatches(&cli)).getMany("h").?;
    try std.testing.expectEqual(@as(usize, 1), many.len);
    try std.testing.expectEqualStrings("cli", many[0]);
}

test "nested subcommands and parent flags" {
    const ally = std.testing.allocator;
    var inner = Xarp.new(ally, "inner");
    try inner.addArg(Arg.new("x").withLong("x").withAction(.set_true));
    var outer = Xarp.new(ally, "outer");
    try outer.addSubcommand(inner);
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("v").withLong("verbose").withAction(.set_true));
    try app.addSubcommand(outer);

    var routed = try app.tryGetMatchesFrom(&.{ "t", "--verbose", "outer", "inner", "--x" });
    defer routed.deinit(ally);
    const matches = try takeMatches(&routed);
    try std.testing.expect(matches.getFlag("v"));
    const outer_name, const outer_matches = matches.getSubcommand().?;
    try std.testing.expectEqualStrings("outer", outer_name);
    const inner_name, const inner_matches = outer_matches.getSubcommand().?;
    try std.testing.expectEqualStrings("inner", inner_name);
    try std.testing.expect(inner_matches.getFlag("x"));

    var forced = Xarp.new(ally, "t");
    defer forced.deinit();
    try forced.addSubcommand(Xarp.new(ally, "run"));
    var behind = try forced.tryGetMatchesFrom(&.{ "t", "--", "run" });
    defer behind.deinit(ally);
    try std.testing.expect(behind.err.isParse());
}

test "help version overrides and unknown tokens" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "demo");
    defer app.deinit();
    var help = try app.tryGetMatchesFrom(&.{ "demo", "-h" });
    defer help.deinit(ally);
    try std.testing.expect(help.err.isHelp());
    var version = try app.withVersion("9.9").tryGetMatchesFrom(&.{ "demo", "-V" });
    defer version.deinit(ally);
    try std.testing.expect(version.err.isVersion());

    var custom = Xarp.new(ally, "t").withVersion("1.0");
    defer custom.deinit();
    try custom.addArg(Arg.new("mine").withShort('V').withAction(.set_true));
    var ordinary = try custom.tryGetMatchesFrom(&.{ "t", "-V" });
    defer ordinary.deinit(ally);
    try std.testing.expect((try takeMatches(&ordinary)).getFlag("mine"));

    var unknown = Xarp.new(ally, "t");
    defer unknown.deinit();
    var bad = try unknown.tryGetMatchesFrom(&.{ "t", "-z" });
    defer bad.deinit(ally);
    try std.testing.expect(bad.err.isParse());
    try std.testing.expect(std.mem.indexOf(u8, bad.err.message(), "-z") != null);

    const rendered = try Xarp.new(ally, "demo").renderVersion();
    defer ally.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "unknown") != null);
}

test "invalid default and append possible values" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("m").withLong("mode").withPossibleValues(&.{ "fast", "safe" }).withDefault("wild"));
    var bad = try app.tryGetMatchesFrom(&.{"t"});
    defer bad.deinit(ally);
    try std.testing.expect(bad.err.isParse());

    var append = Xarp.new(ally, "t");
    defer append.deinit();
    try append.addArg(Arg.new("m").withLong("mode").withAction(.append).withPossibleValues(&.{ "a", "b" }));
    var rejected = try append.tryGetMatchesFrom(&.{ "t", "--mode", "a", "--mode", "z" });
    defer rejected.deinit(ally);
    try std.testing.expect(rejected.err.isParse());
}

test "typed values invalid and missing" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("port").withLong("port"));
    var parsed = try app.tryGetMatchesFrom(&.{ "t", "--port", "abc" });
    defer parsed.deinit(ally);
    const matches = try takeMatches(&parsed);
    try std.testing.expect(matches.getOneParsed(u16, "port") == null);
    try std.testing.expectError(error.InvalidValue, matches.tryGetOne(u16, "port"));
    const err = try matches.valueError("port", "abc");
    defer err.deinit(ally);
    try std.testing.expect(std.mem.indexOf(u8, err.message(), "--help") != null);
    try std.testing.expectEqual(true, matches.getOneParsed(bool, "missing") == null);
}

test "positionals dash defaults and extras" {
    const ally = std.testing.allocator;
    var dash = Xarp.new(ally, "t");
    defer dash.deinit();
    try dash.addArg(Arg.new("file"));
    var kept = try dash.tryGetMatchesFrom(&.{ "t", "-" });
    defer kept.deinit(ally);
    try std.testing.expectEqualStrings("-", (try takeMatches(&kept)).getOne("file").?);

    var none = Xarp.new(ally, "t");
    defer none.deinit();
    var rejected = try none.tryGetMatchesFrom(&.{ "t", "-" });
    defer rejected.deinit(ally);
    try std.testing.expect(rejected.err.isParse());

    var extra = Xarp.new(ally, "t");
    defer extra.deinit();
    try extra.addArg(Arg.new("a"));
    var too_many = try extra.tryGetMatchesFrom(&.{ "t", "one", "two" });
    defer too_many.deinit(ally);
    try std.testing.expect(too_many.err.isParse());

    var optional = Xarp.new(ally, "t");
    defer optional.deinit();
    try optional.addArg(Arg.new("file").withDefault("def"));
    var filled = try optional.tryGetMatchesFrom(&.{"t"});
    defer filled.deinit(ally);
    try std.testing.expectEqualStrings("def", (try takeMatches(&filled)).getOne("file").?);
}

test "long forms empty value and dash value" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    try app.addArg(Arg.new("m").withLong("mode"));
    var empty = try app.tryGetMatchesFrom(&.{ "t", "--mode=" });
    defer empty.deinit(ally);
    try std.testing.expectEqualStrings("", (try takeMatches(&empty)).getOne("m").?);
    var dashed = try app.tryGetMatchesFrom(&.{ "t", "--mode", "-n" });
    defer dashed.deinit(ally);
    try std.testing.expectEqualStrings("-n", (try takeMatches(&dashed)).getOne("m").?);
    var missing = try app.tryGetMatchesFrom(&.{ "t", "--mode" });
    defer missing.deinit(ally);
    try std.testing.expect(missing.err.isParse());
}

test "help text names the app and stays plain without theme" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "demo").withAbout("says hello").withStyles(Styles.plain());
    defer app.deinit();
    try app.addArg(Arg.new("file").withHelp("input path").setRequired(true));
    const help = try app.renderHelp();
    defer ally.free(help);
    try std.testing.expect(std.mem.indexOf(u8, help, "DEMO") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "Flags & Options") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "\x1b[") == null);
    const version = try app.withVersion("1.2.3").renderVersion();
    defer ally.free(version);
    try std.testing.expect(std.mem.indexOf(u8, version, "demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, version, "1.2.3") != null);
}

test "custom help short is not hijacked and inline flag is rejected" {
    const ally = std.testing.allocator;
    var custom = Xarp.new(ally, "t");
    defer custom.deinit();
    try custom.addArg(Arg.new("myh").withShort('h').withAction(.set_true));
    var mine = try custom.tryGetMatchesFrom(&.{ "t", "-h" });
    defer mine.deinit(ally);
    try std.testing.expect((try takeMatches(&mine)).getFlag("myh"));

    var flagged = Xarp.new(ally, "t");
    defer flagged.deinit();
    try flagged.addArg(Arg.new("f").withLong("flag").withAction(.set_true));
    var bad = try flagged.tryGetMatchesFrom(&.{ "t", "--flag=false" });
    defer bad.deinit(ally);
    try std.testing.expect(bad.err.isParse());
}

test "single sided conflict and append after delimiter" {
    const ally = std.testing.allocator;
    var app = Xarp.new(ally, "t");
    defer app.deinit();
    var left = Arg.new("a").withLong("aaa");
    try left.conflictsWith(ally, "b");
    try app.addArg(left);
    try app.addArg(Arg.new("b").withLong("bbb"));
    var only_b = try app.tryGetMatchesFrom(&.{ "t", "--bbb", "2" });
    defer only_b.deinit(ally);
    try std.testing.expectEqualStrings("2", (try takeMatches(&only_b)).getOne("b").?);
    var both = try app.tryGetMatchesFrom(&.{ "t", "--aaa", "1", "--bbb", "2" });
    defer both.deinit(ally);
    try std.testing.expect(both.err.isParse());

    var files = Xarp.new(ally, "t");
    defer files.deinit();
    try files.addArg(Arg.new("f").withAction(.append));
    var after = try files.tryGetMatchesFrom(&.{ "t", "--", "-a", "b" });
    defer after.deinit(ally);
    const many = (try takeMatches(&after)).getMany("f").?;
    try std.testing.expectEqual(@as(usize, 2), many.len);
    try std.testing.expectEqualStrings("-a", many[0]);
}
