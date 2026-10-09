//! Text styles, ANSI output formatting, and CLI theme configurations.
//!
//! Combine styles with `merge`. `withColor` sets a foreground only when one
//! is not already set. `{f}` writes the opening SGR sequence; `writeReset`
//! writes the reset.

const std = @import("std");
const Color = @import("color.zig").Color;
const RESET = @import("color.zig").RESET;
const Effects = @import("effect.zig").Effects;

/// Combined text style: effects, foreground, and background.
///
/// `fg` and `bg` are optional. `null` means no color is applied.
pub const Style = struct {
    /// Foreground color.
    fg: ?Color = null,
    /// Background color.
    bg: ?Color = null,
    /// Set of visual text effects.
    effects: Effects = .NONE,

    /// Creates a blank/unstyled style.
    pub fn new() Style {
        return .{};
    }

    /// Returns `true` if no color or text effects are applied.
    pub fn isPlain(self: Style) bool {
        return self.fg == null and self.bg == null and self.effects.isEmpty();
    }

    /// Sets the foreground color. Replaces any previous foreground.
    pub fn fgColor(self: Style, color: Color) Style {
        var next = self;
        next.fg = color;
        return next;
    }

    /// Sets the background color. Replaces any previous background.
    pub fn bgColor(self: Style, color: Color) Style {
        var next = self;
        next.bg = color;
        return next;
    }

    /// Adds text effects to the current style. Existing effects are kept.
    pub fn withEffects(self: Style, effects: Effects) Style {
        var next = self;
        next.effects = self.effects.insert(effects);
        return next;
    }

    /// Applies bold styling.
    pub fn bold(self: Style) Style {
        return self.withEffects(.BOLD);
    }

    /// Applies dim (faint) styling.
    pub fn dim(self: Style) Style {
        return self.withEffects(.DIM);
    }

    /// Applies italic styling.
    pub fn italic(self: Style) Style {
        return self.withEffects(.ITALIC);
    }

    /// Applies single underline styling.
    pub fn underline(self: Style) Style {
        return self.withEffects(.UNDERLINE);
    }

    /// Applies slow blink styling.
    pub fn blink(self: Style) Style {
        return self.withEffects(.BLINK);
    }

    /// Inverts foreground and background colors.
    pub fn invert(self: Style) Style {
        return self.withEffects(.INVERT);
    }

    /// Hides the text.
    pub fn hidden(self: Style) Style {
        return self.withEffects(.HIDDEN);
    }

    /// Applies strikethrough (crossed-out) styling.
    pub fn strikethrough(self: Style) Style {
        return self.withEffects(.STRIKETHROUGH);
    }

    /// Applies double underline styling.
    pub fn doubleUnderline(self: Style) Style {
        return self.withEffects(.DOUBLE_UNDERLINE);
    }

    /// Merges two styles. Right-hand `fg` and `bg` win when set; effects are united.
    pub fn merge(self: Style, rhs: Style) Style {
        return .{
            .fg = rhs.fg orelse self.fg,
            .bg = rhs.bg orelse self.bg,
            .effects = self.effects.bitOr(rhs.effects),
        };
    }

    /// Sets the foreground when `self` does not already have one.
    pub fn withColor(self: Style, color: Color) Style {
        return Style.new().fgColor(color).merge(self);
    }

    /// Wraps text so formatting applies this style and then resets.
    ///
    /// `Style` is copied, so a temporary can be painted directly:
    /// `Style.new().bold().paint("hi")`.
    pub fn paint(self: Style, text: []const u8) StyledText {
        return .{ .style = self, .text = text };
    }

    /// Writes the opening SGR sequence (`\x1b[...m`), or nothing if plain.
    ///
    /// This is the `{f}` hook. Reset is separate: see `writeReset`.
    pub fn format(self: Style, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.writeAnsi(writer);
    }

    /// Writes the ANSI reset sequence `\x1b[0m`.
    pub fn writeReset(writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(RESET);
    }

    fn writeAnsi(self: Style, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isPlain()) return;

        try writer.writeAll("\x1b[");
        var first = true;

        const codes = [_]struct { flag: Effects, code: u8 }{
            .{ .flag = .BOLD, .code = 1 },
            .{ .flag = .DIM, .code = 2 },
            .{ .flag = .ITALIC, .code = 3 },
            .{ .flag = .UNDERLINE, .code = 4 },
            .{ .flag = .BLINK, .code = 5 },
            .{ .flag = .RAPID_BLINK, .code = 6 },
            .{ .flag = .INVERT, .code = 7 },
            .{ .flag = .HIDDEN, .code = 8 },
            .{ .flag = .STRIKETHROUGH, .code = 9 },
            .{ .flag = .DOUBLE_UNDERLINE, .code = 21 },
        };
        for (codes) |entry| {
            if (self.effects.contains(entry.flag)) {
                try writeCode(writer, &first, entry.code);
            }
        }
        if (self.fg) |fg| {
            if (!first) try writer.writeAll(";");
            first = false;
            try fg.writeAnsi(writer, false);
        }
        if (self.bg) |bg| {
            if (!first) try writer.writeAll(";");
            try bg.writeAnsi(writer, true);
        }
        try writer.writeAll("m");
    }
};

fn writeCode(writer: *std.Io.Writer, first: *bool, code: u8) std.Io.Writer.Error!void {
    if (!first.*) try writer.writeAll(";");
    first.* = false;
    try writer.print("{d}", .{code});
}

/// Helper returned by `Style.paint`. Owns a copy of the style.
pub const StyledText = struct {
    style: Style,
    text: []const u8,

    pub fn format(self: StyledText, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.style.isPlain()) {
            try writer.writeAll(self.text);
            return;
        }
        try self.style.writeAnsi(writer);
        try writer.writeAll(self.text);
        try Style.writeReset(writer);
    }
};

/// Styling configuration for help, usage, and error output.
pub const Styles = struct {
    /// Style applied to section headers.
    header: Style = .{},
    /// Style applied to usage instructions.
    usage: Style = .{},
    /// Style applied to command literals and flags.
    literal: Style = .{},
    /// Style applied to argument value placeholders.
    placeholder: Style = .{},
    /// Style applied to error messages.
    ///
    /// Named `@"error"` because `error` is a keyword.
    @"error": Style = .{},
    /// Style applied to valid values or states.
    valid: Style = .{},
    /// Style applied to invalid values or warnings.
    invalid: Style = .{},
    /// Style applied to warning messages.
    warning: Style = .{},
    /// Style applied to secondary or dimmed text.
    muted: Style = .{},

    /// Returns uncolored / plain styles.
    pub fn plain() Styles {
        return .{};
    }

    /// Default styled CLI theme (Cargo / Clap v4 styled look).
    ///
    /// This does not read the process environment. Zig 0.16 has no libc-free
    /// global getenv. Pass the result of `init.environ.getPosix("NO_COLOR") != null`
    /// to `styledUnless` when color should follow `NO_COLOR`.
    pub fn styled() Styles {
        return themed();
    }

    /// Returns plain styles when `no_color` is true, otherwise the default theme.
    /// Any presence of `NO_COLOR`, including an empty value, should set `no_color`.
    pub fn styledUnless(no_color: bool) Styles {
        if (no_color) return plain();
        return themed();
    }

    /// The color theme, ignoring `NO_COLOR`.
    pub fn themed() Styles {
        return .{
            .header = Style.new().bold().underline(),
            .usage = Style.new().bold().underline(),
            .literal = Style.new().bold().fgColor(.bright_cyan),
            .placeholder = Style.new().fgColor(.cyan),
            .@"error" = Style.new().bold().fgColor(.bright_red),
            .valid = Style.new().bold().fgColor(.bright_green),
            .invalid = Style.new().bold().fgColor(.bright_yellow),
            .warning = Style.new().bold().fgColor(.yellow),
            .muted = Style.new().dim(),
        };
    }

    pub fn setHeader(self: Styles, style: Style) Styles {
        var next = self;
        next.header = style;
        return next;
    }

    pub fn setUsage(self: Styles, style: Style) Styles {
        var next = self;
        next.usage = style;
        return next;
    }

    pub fn setLiteral(self: Styles, style: Style) Styles {
        var next = self;
        next.literal = style;
        return next;
    }

    pub fn setPlaceholder(self: Styles, style: Style) Styles {
        var next = self;
        next.placeholder = style;
        return next;
    }

    pub fn setError(self: Styles, style: Style) Styles {
        var next = self;
        next.@"error" = style;
        return next;
    }

    pub fn setValid(self: Styles, style: Style) Styles {
        var next = self;
        next.valid = style;
        return next;
    }

    pub fn setInvalid(self: Styles, style: Style) Styles {
        var next = self;
        next.invalid = style;
        return next;
    }

    pub fn setWarning(self: Styles, style: Style) Styles {
        var next = self;
        next.warning = style;
        return next;
    }

    pub fn setMuted(self: Styles, style: Style) Styles {
        var next = self;
        next.muted = style;
        return next;
    }
};

// Preset styles. Kept here so `color.zig` does not import this file.

/// Preset style with bold text effect.
pub const BOLD: Style = Style.new().bold();
/// Preset style with dim (faint) text effect.
pub const DIM: Style = Style.new().dim();
/// Preset style with italic text effect.
pub const ITALIC: Style = Style.new().italic();
/// Preset style with underline text effect.
pub const UNDERLINE: Style = Style.new().underline();

/// Preset style with foreground standard black.
pub const BLACK: Style = Style.new().fgColor(.black);
/// Preset style with foreground standard red.
pub const RED: Style = Style.new().fgColor(.red);
/// Preset style with foreground standard green.
pub const GREEN: Style = Style.new().fgColor(.green);
/// Preset style with foreground standard yellow.
pub const YELLOW: Style = Style.new().fgColor(.yellow);
/// Preset style with foreground standard blue.
pub const BLUE: Style = Style.new().fgColor(.blue);
/// Preset style with foreground standard magenta.
pub const MAGENTA: Style = Style.new().fgColor(.magenta);
/// Preset style with foreground standard cyan.
pub const CYAN: Style = Style.new().fgColor(.cyan);
/// Preset style with foreground standard white.
pub const WHITE: Style = Style.new().fgColor(.white);

/// Preset style with foreground bright black (gray / charcoal).
pub const BRIGHT_BLACK: Style = Style.new().fgColor(.bright_black);
/// Preset style with foreground bright red.
pub const BRIGHT_RED: Style = Style.new().fgColor(.bright_red);
/// Preset style with foreground bright green.
pub const BRIGHT_GREEN: Style = Style.new().fgColor(.bright_green);
/// Preset style with foreground bright yellow.
pub const BRIGHT_YELLOW: Style = Style.new().fgColor(.bright_yellow);
/// Preset style with foreground bright blue.
pub const BRIGHT_BLUE: Style = Style.new().fgColor(.bright_blue);
/// Preset style with foreground bright magenta.
pub const BRIGHT_MAGENTA: Style = Style.new().fgColor(.bright_magenta);
/// Preset style with foreground bright cyan.
pub const BRIGHT_CYAN: Style = Style.new().fgColor(.bright_cyan);
/// Preset style with foreground bright white.
pub const BRIGHT_WHITE: Style = Style.new().fgColor(.bright_white);

/// Preset style with foreground orange.
pub const ORANGE: Style = Style.new().fgColor(.orange);
/// Preset style with foreground purple.
pub const PURPLE: Style = Style.new().fgColor(.purple);
/// Preset style with foreground pink.
pub const PINK: Style = Style.new().fgColor(.pink);
/// Preset style with foreground teal.
pub const TEAL: Style = Style.new().fgColor(.teal);
/// Preset style with foreground gold.
pub const GOLD: Style = Style.new().fgColor(.gold);
/// Preset style with foreground silver.
pub const SILVER: Style = Style.new().fgColor(.silver);
/// Preset style with foreground lime.
pub const LIME: Style = Style.new().fgColor(.lime);
/// Preset style with foreground indigo.
pub const INDIGO: Style = Style.new().fgColor(.indigo);

// === Tests ===

fn render(value: anytype, buf: []u8) ![]const u8 {
    var writer: std.Io.Writer = .fixed(buf);
    try value.format(&writer);
    return writer.buffered();
}

test "paint temporary can be bound" {
    const painted = Style.new().bold().paint("hi");
    var buf: [32]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, try render(painted, &buf), "hi") != null);
}

test "merge prefers right colors and unions effects" {
    const merged = Style.new().fgColor(.red).merge(Style.new().bold());
    try std.testing.expectEqual(@as(?Color, .red), merged.fg);
    try std.testing.expect(merged.effects.contains(.BOLD));

    const overridden = Style.new().fgColor(.red).merge(Style.new().fgColor(.blue));
    try std.testing.expectEqual(@as(?Color, .blue), overridden.fg);
}

test "effects and colors merge with styles" {
    const from_effects = Style.new().withEffects(.BOLD).merge(Style.new().fgColor(.red));
    try std.testing.expectEqual(@as(?Color, .red), from_effects.fg);
    try std.testing.expect(from_effects.effects.contains(.BOLD));

    const from_color = Style.new().bold().withColor(.red);
    try std.testing.expectEqual(@as(?Color, .red), from_color.fg);
    try std.testing.expect(from_color.effects.contains(.BOLD));
}

test "builders set each effect" {
    try std.testing.expect(Style.new().bold().effects.contains(.BOLD));
    try std.testing.expect(Style.new().dim().effects.contains(.DIM));
    try std.testing.expect(Style.new().italic().effects.contains(.ITALIC));
    try std.testing.expect(Style.new().underline().effects.contains(.UNDERLINE));
    try std.testing.expect(Style.new().blink().effects.contains(.BLINK));
    try std.testing.expect(Style.new().invert().effects.contains(.INVERT));
    try std.testing.expect(Style.new().hidden().effects.contains(.HIDDEN));
    try std.testing.expect(Style.new().strikethrough().effects.contains(.STRIKETHROUGH));
    try std.testing.expect(Style.new().doubleUnderline().effects.contains(.DOUBLE_UNDERLINE));
}

test "fg bg and effects union" {
    const style = Style.new().fgColor(.red).bgColor(.blue).withEffects(Effects.BOLD.bitOr(.ITALIC));
    try std.testing.expectEqual(@as(?Color, .red), style.fg);
    try std.testing.expectEqual(@as(?Color, .blue), style.bg);
    try std.testing.expect(style.effects.contains(.BOLD));
    try std.testing.expect(style.effects.contains(.ITALIC));
    try std.testing.expect(!style.isPlain());
    try std.testing.expect(Style.new().isPlain());
}

test "display effect codes" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("\x1b[1m", try render(Style.new().bold(), &buf));
    try std.testing.expectEqualStrings("\x1b[2m", try render(Style.new().dim(), &buf));
    try std.testing.expectEqualStrings("\x1b[3m", try render(Style.new().italic(), &buf));
    try std.testing.expectEqualStrings("\x1b[4m", try render(Style.new().underline(), &buf));
    try std.testing.expectEqualStrings("\x1b[5m", try render(Style.new().blink(), &buf));
    try std.testing.expectEqualStrings("\x1b[6m", try render(Style.new().withEffects(.RAPID_BLINK), &buf));
    try std.testing.expectEqualStrings("\x1b[7m", try render(Style.new().invert(), &buf));
    try std.testing.expectEqualStrings("\x1b[8m", try render(Style.new().hidden(), &buf));
    try std.testing.expectEqualStrings("\x1b[9m", try render(Style.new().strikethrough(), &buf));
    try std.testing.expectEqualStrings("\x1b[21m", try render(Style.new().doubleUnderline(), &buf));
}

test "display standard and bright foreground codes" {
    const standard = [_]struct { color: Color, code: []const u8 }{
        .{ .color = .black, .code = "30" },
        .{ .color = .red, .code = "31" },
        .{ .color = .green, .code = "32" },
        .{ .color = .yellow, .code = "33" },
        .{ .color = .blue, .code = "34" },
        .{ .color = .magenta, .code = "35" },
        .{ .color = .cyan, .code = "36" },
        .{ .color = .white, .code = "37" },
        .{ .color = .bright_black, .code = "90" },
        .{ .color = .bright_red, .code = "91" },
        .{ .color = .bright_green, .code = "92" },
        .{ .color = .bright_yellow, .code = "93" },
        .{ .color = .bright_blue, .code = "94" },
        .{ .color = .bright_magenta, .code = "95" },
        .{ .color = .bright_cyan, .code = "96" },
        .{ .color = .bright_white, .code = "97" },
    };
    var buf: [32]u8 = undefined;
    var expected: [16]u8 = undefined;
    for (standard) |case| {
        const want = try std.fmt.bufPrint(&expected, "\x1b[{s}m", .{case.code});
        try std.testing.expectEqualStrings(want, try render(Style.new().fgColor(case.color), &buf));
    }
}

test "display extended palette and parameterized colors" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("\x1b[38;5;208m", try render(Style.new().fgColor(.orange), &buf));
    try std.testing.expectEqualStrings("\x1b[38;5;141m", try render(Style.new().fgColor(.{ .ansi256 = 141 }), &buf));
    try std.testing.expectEqualStrings(
        "\x1b[38;2;255;110;64m",
        try render(Style.new().fgColor(.{ .rgb = .{ .r = 255, .g = 110, .b = 64 } }), &buf),
    );
}

test "display background and combined codes" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("\x1b[41m", try render(Style.new().bgColor(.red), &buf));
    try std.testing.expectEqualStrings("\x1b[106m", try render(Style.new().bgColor(.bright_cyan), &buf));
    try std.testing.expectEqualStrings("\x1b[48;5;7m", try render(Style.new().bgColor(.{ .ansi256 = 7 }), &buf));
    try std.testing.expectEqualStrings(
        "\x1b[48;2;1;2;3m",
        try render(Style.new().bgColor(.{ .rgb = .{ .r = 1, .g = 2, .b = 3 } }), &buf),
    );
    try std.testing.expectEqualStrings("\x1b[1;31m", try render(Style.new().bold().fgColor(.red), &buf));
    try std.testing.expectEqualStrings(
        "\x1b[32;40m",
        try render(Style.new().fgColor(.green).bgColor(.black), &buf),
    );
}

test "reset plain and painted output" {
    var buf: [32]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try Style.writeReset(&writer);
    try std.testing.expectEqualStrings("\x1b[0m", writer.buffered());

    try std.testing.expectEqualStrings("", try render(Style.new(), &buf));
    try std.testing.expectEqualStrings("text", try render(Style.new().paint("text"), &buf));

    const out = try render(Style.new().bold().paint("hi"), &buf);
    try std.testing.expect(std.mem.startsWith(u8, out, "\x1b[1m"));
    try std.testing.expect(std.mem.endsWith(u8, out, "\x1b[0m"));
    try std.testing.expect(std.mem.indexOf(u8, out, "hi") != null);
}

test "preset constants carry codes" {
    var buf: [32]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, try render(RED, &buf), "\x1b[31m") != null);
    try std.testing.expect(std.mem.indexOf(u8, try render(GREEN.paint("ok"), &buf), "ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, try render(BOLD, &buf), "\x1b[1m") != null);
}

test "plain theme has no styled slots" {
    const theme = Styles.plain();
    for ([_]Style{
        theme.header,
        theme.usage,
        theme.literal,
        theme.placeholder,
        theme.@"error",
        theme.valid,
        theme.invalid,
        theme.warning,
        theme.muted,
    }) |slot| {
        try std.testing.expect(slot.isPlain());
    }
}

test "theme setters replace slots" {
    const custom = Styles.plain()
        .setHeader(Style.new().bold())
        .setLiteral(Style.new().fgColor(.red))
        .setMuted(Style.new().dim());
    try std.testing.expect(custom.header.effects.contains(.BOLD));
    try std.testing.expectEqual(@as(?Color, .red), custom.literal.fg);
    try std.testing.expect(custom.muted.effects.contains(.DIM));
    try std.testing.expect(custom.usage.isPlain());
}

test "themed slots match the clap-like theme" {
    const theme = Styles.themed();
    try std.testing.expect(theme.header.effects.contains(.BOLD));
    try std.testing.expect(theme.header.effects.contains(.UNDERLINE));
    try std.testing.expectEqual(@as(?Color, .bright_cyan), theme.literal.fg);
    try std.testing.expect(theme.muted.effects.contains(.DIM));
    try std.testing.expect(theme.@"error".effects.contains(.BOLD));
}
