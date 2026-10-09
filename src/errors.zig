//! Errors encountered while evaluating command-line arguments.
//!
//! The message is an allocated slice. Call `deinit` when you are done with it.
//! Help and version are requests, not syntax failures, so they are separate
//! variants from `parse`.

const std = @import("std");

/// Errors encountered while evaluating command-line arguments.
pub const XarpError = union(enum) {
    /// Help documentation requested by the user. Payload is the rendered help text.
    help: []u8,
    /// Version details requested by the user.
    version: []u8,
    /// Argument syntax or validation failure.
    parse: []u8,

    /// Returns `true` when the user requested help output.
    pub fn isHelp(self: XarpError) bool {
        return switch (self) {
            .help => true,
            else => false,
        };
    }

    /// Returns `true` when the user requested version output.
    pub fn isVersion(self: XarpError) bool {
        return switch (self) {
            .version => true,
            else => false,
        };
    }

    /// Returns `true` for argument syntax or validation failures.
    pub fn isParse(self: XarpError) bool {
        return switch (self) {
            .parse => true,
            else => false,
        };
    }

    /// The rendered message.
    pub fn message(self: XarpError) []const u8 {
        return switch (self) {
            .help => |msg| msg,
            .version => |msg| msg,
            .parse => |msg| msg,
        };
    }

    pub fn deinit(self: XarpError, allocator: std.mem.Allocator) void {
        allocator.free(self.message());
    }

    /// `{f}` writes the message.
    pub fn format(self: XarpError, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.message());
    }

    /// Copies `msg` into a parse error.
    pub fn fromMessage(allocator: std.mem.Allocator, msg: []const u8) !XarpError {
        return .{ .parse = try allocator.dupe(u8, msg) };
    }
};

test "error tags and display" {
    const ally = std.testing.allocator;
    const parse = try XarpError.fromMessage(ally, "boom");
    defer parse.deinit(ally);
    try std.testing.expect(parse.isParse());
    try std.testing.expectEqualStrings("boom", parse.message());

    const help: XarpError = .{ .help = try ally.dupe(u8, "h") };
    defer help.deinit(ally);
    try std.testing.expect(help.isHelp());
    try std.testing.expectEqualStrings("h", help.message());

    const version: XarpError = .{ .version = try ally.dupe(u8, "v") };
    defer version.deinit(ally);
    try std.testing.expect(version.isVersion());
    try std.testing.expectEqualStrings("v", version.message());
}
