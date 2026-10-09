//! ```zig
//! switch (outcome) {
//!     .matches => |*m| try run(m),
//!     .err => |err| {
//!         defer err.deinit(allocator);
//!         std.debug.print("{s}\n", .{err.message()});
//!     },
//! }
//! ```
//!
//! Help, version, and parse failures. Each variant owns its message buffer.
//!
//! - Call `deinit` or you leak the message.
//! - `isHelp` / `isVersion` mean normal output; `isParse` means exit code 2.

const std = @import("std");

/// Help, version, and parse failures. Each variant owns its message buffer.
pub const XarpError = union(enum) {
    /// Rendered help text. Returned for `-h` / `--help`.
    help: []u8,
    /// Rendered version text. Returned for `-V` / `--version`.
    version: []u8,
    /// Bad CLI input with a `--help` hint appended.
    parse: []u8,

    /// `true` for help output.
    pub fn isHelp(self: XarpError) bool {
        return switch (self) {
            .help => true,
            else => false,
        };
    }

    /// `true` for version output.
    pub fn isVersion(self: XarpError) bool {
        return switch (self) {
            .version => true,
            else => false,
        };
    }

    /// `true` for bad CLI input.
    pub fn isParse(self: XarpError) bool {
        return switch (self) {
            .parse => true,
            else => false,
        };
    }

    /// Borrowed view of the message. Don't free it directly; call `deinit`.
    pub fn message(self: XarpError) []const u8 {
        return switch (self) {
            .help => |msg| msg,
            .version => |msg| msg,
            .parse => |msg| msg,
        };
    }

    /// Frees the message buffer.
    pub fn deinit(self: XarpError, allocator: std.mem.Allocator) void {
        allocator.free(self.message());
    }

    /// Writes the message. Lets you print errors with `{f}`.
    pub fn format(self: XarpError, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.message());
    }

    /// Copies `msg` into a new parse error.
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
