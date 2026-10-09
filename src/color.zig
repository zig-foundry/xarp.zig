//! ANSI color formatting for terminal output.
//!
//! Handles 4-bit standard/bright colors, 8-bit ANSI 256 palettes, and 24-bit RGB TrueColor.
//! Emits raw SGR parameter numbers without outer escape wrappers (`\x1b[` or `m`).
//!
//! - `writeAnsi(writer, is_bg)` writes foreground (`38;...`) or background (`48;...`) codes.
//! - Print `RESET` after styled text to clear styling.

const std = @import("std");

/// ANSI escape sequence that clears all terminal styling and colors.
pub const RESET = "\x1b[0m";

/// 24-bit TrueColor RGB color channels.
pub const Rgb = struct {
    /// Red color intensity (0–255).
    r: u8,
    /// Green color intensity (0–255).
    g: u8,
    /// Blue color intensity (0–255).
    b: u8,
};

/// 24 named colors, 8-bit ANSI codes, and 24-bit RGB TrueColor.
pub const Color = union(enum) {
    // Standard ANSI (30-37 / 40-47)
    /// Standard ANSI black.
    black,
    /// Standard ANSI red.
    red,
    /// Standard ANSI green.
    green,
    /// Standard ANSI yellow.
    yellow,
    /// Standard ANSI blue.
    blue,
    /// Standard ANSI magenta.
    magenta,
    /// Standard ANSI cyan.
    cyan,
    /// Standard ANSI white.
    white,

    // High-intensity ANSI (90-97 / 100-107)
    /// High-intensity black (charcoal / dark gray).
    bright_black,
    /// High-intensity red.
    bright_red,
    /// High-intensity green.
    bright_green,
    /// High-intensity yellow.
    bright_yellow,
    /// High-intensity blue.
    bright_blue,
    /// High-intensity magenta.
    bright_magenta,
    /// High-intensity cyan.
    bright_cyan,
    /// High-intensity white.
    bright_white,

    // Extended named palette
    /// Extended palette orange (ANSI 208).
    orange,
    /// Extended palette purple (ANSI 129).
    purple,
    /// Extended palette pink (ANSI 205).
    pink,
    /// Extended palette teal (ANSI 30).
    teal,
    /// Extended palette gold (ANSI 220).
    gold,
    /// Extended palette silver (ANSI 248).
    silver,
    /// Extended palette lime (ANSI 118).
    lime,
    /// Extended palette indigo (ANSI 54).
    indigo,

    // Parameterized formats
    /// 8-bit ANSI 256-color palette index (0–255).
    ansi256: u8,
    /// 24-bit TrueColor RGB values.
    rgb: Rgb,

    /// Constructs an RGB TrueColor variant.
    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    /// Constructs an 8-bit ANSI 256-color variant.
    pub fn fromAnsi256(code: u8) Color {
        return .{ .ansi256 = code };
    }

    /// Writes raw ANSI parameters to `writer`.
    ///
    /// Outputs background codes (`40–47`, `100–107`, `48;...`) when `is_bg` is true,
    /// or foreground codes (`30–37`, `90–97`, `38;...`) when false.
    pub fn writeAnsi(self: Color, writer: *std.Io.Writer, is_bg: bool) std.Io.Writer.Error!void {
        const base_ext = if (is_bg) "48" else "38";

        switch (self) {
            // Standard ANSI
            .black => try writer.writeAll(if (is_bg) "40" else "30"),
            .red => try writer.writeAll(if (is_bg) "41" else "31"),
            .green => try writer.writeAll(if (is_bg) "42" else "32"),
            .yellow => try writer.writeAll(if (is_bg) "43" else "33"),
            .blue => try writer.writeAll(if (is_bg) "44" else "34"),
            .magenta => try writer.writeAll(if (is_bg) "45" else "35"),
            .cyan => try writer.writeAll(if (is_bg) "46" else "36"),
            .white => try writer.writeAll(if (is_bg) "47" else "37"),

            // High-intensity
            .bright_black => try writer.writeAll(if (is_bg) "100" else "90"),
            .bright_red => try writer.writeAll(if (is_bg) "101" else "91"),
            .bright_green => try writer.writeAll(if (is_bg) "102" else "92"),
            .bright_yellow => try writer.writeAll(if (is_bg) "103" else "93"),
            .bright_blue => try writer.writeAll(if (is_bg) "104" else "94"),
            .bright_magenta => try writer.writeAll(if (is_bg) "105" else "95"),
            .bright_cyan => try writer.writeAll(if (is_bg) "106" else "96"),
            .bright_white => try writer.writeAll(if (is_bg) "107" else "97"),

            // Extended palette
            .orange => try writer.writeAll(if (is_bg) "48;5;208" else "38;5;208"),
            .purple => try writer.writeAll(if (is_bg) "48;5;129" else "38;5;129"),
            .pink => try writer.writeAll(if (is_bg) "48;5;205" else "38;5;205"),
            .teal => try writer.writeAll(if (is_bg) "48;5;30" else "38;5;30"),
            .gold => try writer.writeAll(if (is_bg) "48;5;220" else "38;5;220"),
            .silver => try writer.writeAll(if (is_bg) "48;5;248" else "38;5;248"),
            .lime => try writer.writeAll(if (is_bg) "48;5;118" else "38;5;118"),
            .indigo => try writer.writeAll(if (is_bg) "48;5;54" else "38;5;54"),

            // Parameterized formats
            .ansi256 => |code| try writer.print("{s};5;{d}", .{ base_ext, code }),
            .rgb => |c| try writer.print("{s};2;{d};{d};{d}", .{ base_ext, c.r, c.g, c.b }),
        }
    }

    /// Formats the color as a foreground parameter string via `{f}`.
    pub fn format(self: Color, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return self.writeAnsi(writer, false);
    }
};

// === Tests ===

test "writeAnsi foreground standard and bright" {
    var buf: [64]u8 = undefined;

    // Standard foreground red (31)
    var writer: std.Io.Writer = .fixed(&buf);
    const red: Color = .red;
    try red.writeAnsi(&writer, false);
    try std.testing.expectEqualStrings("31", writer.buffered());

    // Bright foreground cyan (96)
    writer = .fixed(&buf);
    const bright_cyan: Color = .bright_cyan;
    try bright_cyan.writeAnsi(&writer, false);
    try std.testing.expectEqualStrings("96", writer.buffered());
}

test "writeAnsi background standard and bright" {
    var buf: [64]u8 = undefined;

    // Standard background black (40)
    var writer: std.Io.Writer = .fixed(&buf);
    const black: Color = .black;
    try black.writeAnsi(&writer, true);
    try std.testing.expectEqualStrings("40", writer.buffered());

    // Bright background green (102)
    writer = .fixed(&buf);
    const bright_green: Color = .bright_green;
    try bright_green.writeAnsi(&writer, true);
    try std.testing.expectEqualStrings("102", writer.buffered());
}

test "writeAnsi extended palette" {
    var buf: [64]u8 = undefined;

    // Foreground orange (38;5;208)
    var writer: std.Io.Writer = .fixed(&buf);
    const orange: Color = .orange;
    try orange.writeAnsi(&writer, false);
    try std.testing.expectEqualStrings("38;5;208", writer.buffered());

    // Background teal (48;5;30)
    writer = .fixed(&buf);
    const teal: Color = .teal;
    try teal.writeAnsi(&writer, true);
    try std.testing.expectEqualStrings("48;5;30", writer.buffered());
}

test "writeAnsi 256 and rgb truecolor" {
    var buf: [64]u8 = undefined;

    // ANSI 256-color
    var writer: std.Io.Writer = .fixed(&buf);
    const c256: Color = Color.fromAnsi256(141);
    try c256.writeAnsi(&writer, false);
    try std.testing.expectEqualStrings("38;5;141", writer.buffered());

    // TrueColor RGB background
    writer = .fixed(&buf);
    const crgb: Color = Color.fromRgb(255, 110, 64);
    try crgb.writeAnsi(&writer, true);
    try std.testing.expectEqualStrings("48;2;255;110;64", writer.buffered());
}

test "format hook integration with {f}" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    const red: Color = .red;
    try writer.print("\x1b[{f}mHello\x1b[0m", .{red});
    try std.testing.expectEqualStrings("\x1b[31mHello\x1b[0m", writer.buffered());
}
