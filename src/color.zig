const std = @import("std");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// 24 distinct named colors, 8-bit ANSI palette, and 24-bit TrueColor (RGB).
pub const Color = union(enum) {
    // Standard ANSI
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,

    // High-intensity
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    // Extended palette
    orange,
    purple,
    pink,
    teal,
    gold,
    silver,
    lime,
    indigo,

    // Parameterized variants
    ansi256: u8,
    rgb: Rgb,

    /// Renders color code to a modern Zig 0.16 `*std.Io.Writer`.
    pub fn writeAnsi(self: Color, writer: *std.Io.Writer, is_bg: bool) std.Io.Writer.Error!void {
        const base_ext = if (is_bg) "48" else "38";

        switch (self) {
            .black => try writer.writeAll(if (is_bg) "40" else "30"),
            .red => try writer.writeAll(if (is_bg) "41" else "31"),
            .green => try writer.writeAll(if (is_bg) "42" else "32"),
            .yellow => try writer.writeAll(if (is_bg) "43" else "33"),
            .blue => try writer.writeAll(if (is_bg) "44" else "34"),
            .magenta => try writer.writeAll(if (is_bg) "45" else "35"),
            .cyan => try writer.writeAll(if (is_bg) "46" else "36"),
            .white => try writer.writeAll(if (is_bg) "47" else "37"),

            .bright_black => try writer.writeAll(if (is_bg) "100" else "90"),
            .bright_red => try writer.writeAll(if (is_bg) "101" else "91"),
            .bright_green => try writer.writeAll(if (is_bg) "102" else "92"),
            .bright_yellow => try writer.writeAll(if (is_bg) "103" else "93"),
            .bright_blue => try writer.writeAll(if (is_bg) "104" else "94"),
            .bright_magenta => try writer.writeAll(if (is_bg) "105" else "95"),
            .bright_cyan => try writer.writeAll(if (is_bg) "106" else "96"),
            .bright_white => try writer.writeAll(if (is_bg) "107" else "97"),

            .orange => try writer.writeAll(if (is_bg) "48;5;208" else "38;5;208"),
            .purple => try writer.writeAll(if (is_bg) "48;5;129" else "38;5;129"),
            .pink => try writer.writeAll(if (is_bg) "48;5;205" else "38;5;205"),
            .teal => try writer.writeAll(if (is_bg) "48;5;30" else "38;5;30"),
            .gold => try writer.writeAll(if (is_bg) "48;5;220" else "38;5;220"),
            .silver => try writer.writeAll(if (is_bg) "48;5;248" else "38;5;248"),
            .lime => try writer.writeAll(if (is_bg) "48;5;118" else "38;5;118"),
            .indigo => try writer.writeAll(if (is_bg) "48;5;54" else "38;5;54"),

            .ansi256 => |code| try writer.print("{s};5;{d}", .{ base_ext, code }),
            .rgb => |c| try writer.print("{s};2;{d};{d};{d}", .{ base_ext, c.r, c.g, c.b }),
        }
    }
};

test "writeAnsi renders correctly in Zig 0.16" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    const c: Color = .{ .rgb = .{ .r = 255, .g = 128, .b = 0 } };
    try c.writeAnsi(&writer, false);

    try std.testing.expectEqualStrings("38;2;255;128;0", writer.buffered());
}
