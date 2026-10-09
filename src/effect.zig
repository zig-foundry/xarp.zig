//! ```zig
//! const eff = xarp.Effects.BOLD.bitOr(.UNDERLINE);
//! ```
//!
//! Bitmask for ANSI text effects. Only the ten bits in `Effects.ALL` are valid.
//!
//! - Zig has no `|` / `&` / `!` overloads, so use `bitOr`, `bitAnd`, `bitNot`.
//! - `fromBits` returns `null` on unknown bits; `fromBitsTruncate` drops them.

const std = @import("std");

/// ANSI text style modifiers and font effects.
///
/// Holds a raw bitmask. Only bits in `Effects.ALL` are defined.
pub const Effects = struct {
    /// Raw flag bits. Don't set unknown bits; `fromBits` rejects them.
    bits: u16 = 0,

    /// No text effects.
    pub const NONE: Effects = .{ .bits = 0 };

    /// Bold or increased intensity.
    pub const BOLD: Effects = .{ .bits = 1 << 0 };

    /// Dim or decreased intensity.
    pub const DIM: Effects = .{ .bits = 1 << 1 };

    /// Italic text.
    pub const ITALIC: Effects = .{ .bits = 1 << 2 };

    /// Single underline.
    pub const UNDERLINE: Effects = .{ .bits = 1 << 3 };

    /// Slow blinking text.
    pub const BLINK: Effects = .{ .bits = 1 << 4 };

    /// Rapid blinking text.
    pub const RAPID_BLINK: Effects = .{ .bits = 1 << 5 };

    /// Inverted foreground and background colors.
    pub const INVERT: Effects = .{ .bits = 1 << 6 };

    /// Hidden or concealed text.
    pub const HIDDEN: Effects = .{ .bits = 1 << 7 };

    /// Strikethrough or crossed-out text.
    pub const STRIKETHROUGH: Effects = .{ .bits = 1 << 8 };

    /// Double underline.
    ///
    /// Encoded as SGR code 21. Note that some terminals interpret code 21 as
    /// "bold off" instead of double underline, so this effect is less portable
    /// than the others.
    pub const DOUBLE_UNDERLINE: Effects = .{ .bits = 1 << 9 };

    /// Mask of all defined effect bits.
    pub const ALL: Effects = .{ .bits = BOLD.bits |
        DIM.bits |
        ITALIC.bits |
        UNDERLINE.bits |
        BLINK.bits |
        RAPID_BLINK.bits |
        INVERT.bits |
        HIDDEN.bits |
        STRIKETHROUGH.bits |
        DOUBLE_UNDERLINE.bits };

    /// Creates a set containing every defined effect.
    pub fn all() Effects {
        return ALL;
    }

    /// Converts a raw bitmask into an effect set.
    ///
    /// Returns `null` when `bits` holds undefined bits (outside `ALL`).
    /// Call `fromBitsTruncate` to drop undefined bits instead.
    pub fn fromBits(bits: u16) ?Effects {
        if (bits & ~ALL.bits == 0) {
            return .{ .bits = bits };
        }
        return null;
    }

    /// Converts a raw bitmask into an effect set, discarding undefined bits.
    pub fn fromBitsTruncate(bits: u16) Effects {
        return .{ .bits = bits & ALL.bits };
    }

    /// Creates an empty set of effects.
    pub fn empty() Effects {
        return NONE;
    }

    /// `true` when no effects are set.
    pub fn isEmpty(self: Effects) bool {
        return self.bits == 0;
    }

    /// `true` when `self` holds every effect in `other`.
    pub fn contains(self: Effects, other: Effects) bool {
        return (self.bits & other.bits) == other.bits;
    }

    /// Returns a copy with `other` added.
    pub fn insert(self: Effects, other: Effects) Effects {
        return .{ .bits = self.bits | other.bits };
    }

    /// Returns a copy with `other` removed.
    pub fn remove(self: Effects, other: Effects) Effects {
        return .{ .bits = self.bits & ~other.bits };
    }

    /// Rust `BitOr` (`self | other`). Zig has no custom `|`.
    pub fn bitOr(self: Effects, other: Effects) Effects {
        return self.insert(other);
    }

    /// Rust `BitOrAssign` (`self |= other`).
    pub fn bitOrAssign(self: *Effects, other: Effects) void {
        self.bits |= other.bits;
    }

    /// Rust `BitAnd` (`self & other`). Zig has no custom `&`.
    pub fn bitAnd(self: Effects, other: Effects) Effects {
        return .{ .bits = self.bits & other.bits };
    }

    /// Rust `BitAndAssign` (`self &= other`).
    pub fn bitAndAssign(self: *Effects, other: Effects) void {
        self.bits &= other.bits;
    }

    /// Rust `Not` (`!self`). Flips every bit, including undefined ones.
    pub fn bitNot(self: Effects) Effects {
        return .{ .bits = ~self.bits };
    }

    /// Formats set flag names, matching Rust `Debug`.
    ///
    /// An empty set formats as `Effects(NONE)`. Unknown bits (outside `ALL`)
    /// are reported as a hexadecimal mask, e.g. `Effects(BOLD | 0x8000)`.
    pub fn format(self: Effects, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isEmpty()) {
            return writer.writeAll("Effects(NONE)");
        }

        try writer.writeAll("Effects(");
        var first = true;
        const named = [_]struct { name: []const u8, flag: Effects }{
            .{ .name = "BOLD", .flag = BOLD },
            .{ .name = "DIM", .flag = DIM },
            .{ .name = "ITALIC", .flag = ITALIC },
            .{ .name = "UNDERLINE", .flag = UNDERLINE },
            .{ .name = "BLINK", .flag = BLINK },
            .{ .name = "RAPID_BLINK", .flag = RAPID_BLINK },
            .{ .name = "INVERT", .flag = INVERT },
            .{ .name = "HIDDEN", .flag = HIDDEN },
            .{ .name = "STRIKETHROUGH", .flag = STRIKETHROUGH },
            .{ .name = "DOUBLE_UNDERLINE", .flag = DOUBLE_UNDERLINE },
        };
        for (named) |entry| {
            if (self.contains(entry.flag)) {
                if (!first) try writer.writeAll(" | ");
                first = false;
                try writer.writeAll(entry.name);
            }
        }
        const unknown = self.bits & ~ALL.bits;
        if (unknown != 0) {
            if (!first) try writer.writeAll(" | ");
            try writer.print("0x{X}", .{unknown});
        }
        try writer.writeAll(")");
    }
};

// === Tests ===

fn formatEffects(effects: Effects, buf: []u8) ![]const u8 {
    var writer: std.Io.Writer = .fixed(buf);
    try effects.format(&writer);
    return writer.buffered();
}

test "format lists set flag names" {
    var buf: [64]u8 = undefined;

    try std.testing.expectEqualStrings("Effects(NONE)", try formatEffects(.NONE, &buf));
    try std.testing.expectEqualStrings("Effects(BOLD)", try formatEffects(.BOLD, &buf));
    try std.testing.expectEqualStrings(
        "Effects(BOLD | UNDERLINE)",
        try formatEffects(Effects.BOLD.bitOr(.UNDERLINE), &buf),
    );
}

test "all and fromBits round trip" {
    const every = Effects.all();
    try std.testing.expect(every.contains(.BOLD));
    try std.testing.expect(every.contains(.DOUBLE_UNDERLINE));
    try std.testing.expectEqual(every, Effects.fromBits(every.bits));
    try std.testing.expectEqual(null, Effects.fromBits(std.math.maxInt(u16)));
    try std.testing.expectEqual(
        Effects.fromBitsTruncate(std.math.maxInt(u16)),
        Effects.fromBitsTruncate(Effects.ALL.bits),
    );
}

test "every flag has a distinct bit" {
    const flags = [_]Effects{
        .BOLD,
        .DIM,
        .ITALIC,
        .UNDERLINE,
        .BLINK,
        .RAPID_BLINK,
        .INVERT,
        .HIDDEN,
        .STRIKETHROUGH,
        .DOUBLE_UNDERLINE,
    };
    try std.testing.expectEqual(@as(usize, 10), flags.len);
    for (flags, 0..) |first, i| {
        try std.testing.expect(first.bits != 0);
        for (flags[i + 1 ..]) |second| {
            try std.testing.expectEqual(@as(u16, 0), first.bits & second.bits);
        }
        try std.testing.expect(Effects.ALL.contains(first));
    }
}

test "empty and contains" {
    try std.testing.expect(Effects.NONE.isEmpty());
    try std.testing.expect(Effects.empty().isEmpty());
    try std.testing.expect(!Effects.BOLD.isEmpty());
    try std.testing.expect(Effects.BOLD.bitOr(.DIM).contains(.BOLD));
    try std.testing.expect(!Effects.BOLD.contains(.DIM));
}

test "insert and remove" {
    const added = Effects.NONE.insert(.BOLD).insert(.DIM);
    try std.testing.expect(added.contains(.BOLD));
    const removed = added.remove(.BOLD);
    try std.testing.expect(!removed.contains(.BOLD));
    try std.testing.expect(removed.contains(.DIM));
}

test "bitwise methods" {
    try std.testing.expectEqual(@as(u16, 0b11), Effects.BOLD.bitOr(.DIM).bits);
    try std.testing.expectEqual(@as(u16, 0), Effects.BOLD.bitAnd(.DIM).bits);
    try std.testing.expectEqual(
        @as(u16, 1),
        Effects.BOLD.bitAnd(Effects.BOLD.bitOr(.DIM)).bits,
    );

    var assigned = Effects.BOLD;
    assigned.bitOrAssign(.DIM);
    try std.testing.expect(assigned.contains(.DIM));
    assigned.bitAndAssign(.BOLD);
    try std.testing.expect(!assigned.contains(.DIM));
    try std.testing.expect(!Effects.NONE.bitNot().isEmpty());
}

test "format names every flag" {
    const cases = [_]struct { flag: Effects, name: []const u8 }{
        .{ .flag = .DIM, .name = "DIM" },
        .{ .flag = .ITALIC, .name = "ITALIC" },
        .{ .flag = .UNDERLINE, .name = "UNDERLINE" },
        .{ .flag = .BLINK, .name = "BLINK" },
        .{ .flag = .RAPID_BLINK, .name = "RAPID_BLINK" },
        .{ .flag = .INVERT, .name = "INVERT" },
        .{ .flag = .HIDDEN, .name = "HIDDEN" },
        .{ .flag = .STRIKETHROUGH, .name = "STRIKETHROUGH" },
        .{ .flag = .DOUBLE_UNDERLINE, .name = "DOUBLE_UNDERLINE" },
    };
    var buf: [64]u8 = undefined;
    var expected_buf: [64]u8 = undefined;
    for (cases) |case| {
        const expected = try std.fmt.bufPrint(&expected_buf, "Effects({s})", .{case.name});
        try std.testing.expectEqualStrings(expected, try formatEffects(case.flag, &buf));
    }
}

test "format reports unknown bits as hex" {
    const unknown = Effects.fromBitsTruncate(0).bitOr(.BOLD);
    const raw: Effects = .{ .bits = unknown.bits | 0x8000 };
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Effects(BOLD | 0x8000)", try formatEffects(raw, &buf));
}

test "fromBits boundary" {
    try std.testing.expectEqual(Effects.ALL, Effects.fromBits(Effects.ALL.bits));
    try std.testing.expectEqual(null, Effects.fromBits(Effects.ALL.bits + 1));
    try std.testing.expectEqual(Effects.NONE, Effects.fromBits(0));
    try std.testing.expectEqual(Effects.ALL.bits, Effects.fromBitsTruncate(0xFFFF).bits);
}
