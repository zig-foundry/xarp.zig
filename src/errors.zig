//! Error and diagnostic representation for argument parsing.
//!
//! Represents help output, version output, and parse errors.
//! Each variant owns its message buffer on the heap.
//!
//! - Always call `deinit` on an error value to free its message buffer.
//! - `isHelp` and `isVersion` represent successful exits (status code 0).
//! - `isParse` represents bad CLI input (status code 2).

const std = @import("std");

/// Parsing outcomes that exit early: help displays, version displays, and parse failures.
pub const XarpError = union(enum) {
    /// Formatted help text displayed when requesting `-h` or `--help`.
    help: []u8,
    /// Formatted version text displayed when requesting `-V` or `--version`.
    version: []u8,
    /// Parse failure message including the `--help` suggestion.
    parse: []u8,

    /// Checks whether this error represents a help request.
    pub fn isHelp(self: XarpError) bool {
        return switch (self) {
            .help => true,
            else => false,
        };
    }

    /// Checks whether this error represents a version request.
    pub fn isVersion(self: XarpError) bool {
        return switch (self) {
            .version => true,
            else => false,
        };
    }

    /// Checks whether this error represents invalid CLI input.
    pub fn isParse(self: XarpError) bool {
        return switch (self) {
            .parse => true,
            else => false,
        };
    }

    /// Returns the suggested process exit code (0 for help/version, 2 for parse errors).
    pub fn exitCode(self: XarpError) u8 {
        return if (self.isParse()) 2 else 0;
    }

    /// Returns a borrowed slice of the owned error message.
    ///
    /// Do not free this slice directly; call `deinit` instead.
    pub fn message(self: XarpError) []const u8 {
        return switch (self) {
            .help => |msg| msg,
            .version => |msg| msg,
            .parse => |msg| msg,
        };
    }

    /// Frees the allocated message buffer.
    pub fn deinit(self: XarpError, allocator: std.mem.Allocator) void {
        allocator.free(self.message());
    }

    /// Writes the message to `writer` for `{f}` formatting.
    pub fn format(self: XarpError, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.message());
    }

    /// Allocates a new parse error variant by copying `msg`.
    pub fn fromMessage(allocator: std.mem.Allocator, msg: []const u8) !XarpError {
        return .{ .parse = try allocator.dupe(u8, msg) };
    }

    /// Allocates a new help variant by copying `text`.
    pub fn fromHelp(allocator: std.mem.Allocator, text: []const u8) !XarpError {
        return .{ .help = try allocator.dupe(u8, text) };
    }

    /// Allocates a new version variant by copying `text`.
    pub fn fromVersion(allocator: std.mem.Allocator, text: []const u8) !XarpError {
        return .{ .version = try allocator.dupe(u8, text) };
    }
};

// === Tests ===

test "error tags, exit codes, and message access" {
    const ally = std.testing.allocator;

    const parse = try XarpError.fromMessage(ally, "unknown flag");
    defer parse.deinit(ally);
    try std.testing.expect(parse.isParse());
    try std.testing.expectEqual(@as(u8, 2), parse.exitCode());
    try std.testing.expectEqualStrings("unknown flag", parse.message());

    const help = try XarpError.fromHelp(ally, "Usage: demo");
    defer help.deinit(ally);
    try std.testing.expect(help.isHelp());
    try std.testing.expectEqual(@as(u8, 0), help.exitCode());
    try std.testing.expectEqualStrings("Usage: demo", help.message());

    const version = try XarpError.fromVersion(ally, "demo 0.1.0");
    defer version.deinit(ally);
    try std.testing.expect(version.isVersion());
    try std.testing.expectEqual(@as(u8, 0), version.exitCode());
    try std.testing.expectEqualStrings("demo 0.1.0", version.message());
}

test "format hook writes error message" {
    const ally = std.testing.allocator;
    const parse = try XarpError.fromMessage(ally, "missing argument");
    defer parse.deinit(ally);

    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try parse.format(&writer);
    try std.testing.expectEqualStrings("missing argument", writer.buffered());
}
