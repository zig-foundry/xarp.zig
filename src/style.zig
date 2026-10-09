//! Text styling primitives and terminal theme definitions.
//!
//! Pairs foreground and background colors with bitmask text effects.
//! Provides preset styles and the `Styles` container to format help text and error output.
//!
//! - Combine styles using `merge`. Right-hand colors override left-hand colors, while effects union together.
//! - Use `withColor` to set a fallback foreground color when none is set.
//! - Formatting via `{f}` emits the opening ANSI escape code. Call `writeReset` or print `RESET` to clear it.
//! - `Styles.styled` checks `NO_COLOR` through libc `getenv` and returns unstyled text when set.

const std = @import("std");
const Color = @import("color.zig").Color;
const RESET = @import("color.zig").RESET;
const Effects = @import("effect.zig").Effects;

/// Combined terminal style containing effects, foreground color, and background color.
///
/// Unset colors remain `null`. Plain styles emit no escape codes.
pub const Style = struct {
    /// Foreground color.
    fg: ?Color = null,
    /// Background color.
    bg: ?Color = null,
    /// Active bitmask text effects.
    effects: Effects = .NONE,

    /// Creates an empty style with no colors or active effects.
    pub fn new() Style {
        return .{};
    }

    /// Checks if no color or effects are configured. Plain styles emit no ANSI sequences.
    pub fn isPlain(self: Style) bool {
        return self.fg == null and self.bg == null and self.effects.isEmpty();
    }

    /// Sets the foreground color, overriding any previous value.
    pub fn fgColor(self: Style, color: Color) Style {
        var next = self;
        next.fg = color;
        return next;
    }

    /// Sets the background color, overriding any previous value.
    pub fn bgColor(self: Style, color: Color) Style {
        var next = self;
        next.bg = color;
        return next;
    }

    /// Adds text effects into the existing effect bitmask.
    pub fn withEffects(self: Style, effects: Effects) Style {
        var next = self;
        next.effects = self.effects.insert(effects);
        return next;
    }

    /// Adds the bold text effect.
    pub fn bold(self: Style) Style {
        return self.withEffects(.BOLD);
    }

    /// Adds the dim (faint) text effect.
    pub fn dim(self: Style) Style {
        return self.withEffects(.DIM);
    }

    /// Adds the italic text effect.
    pub fn italic(self: Style) Style {
        return self.withEffects(.ITALIC);
    }

    /// Adds a single underline text effect.
    pub fn underline(self: Style) Style {
        return self.withEffects(.UNDERLINE);
    }

    /// Adds a slow blinking text effect.
    pub fn blink(self: Style) Style {
        return self.withEffects(.BLINK);
    }

    /// Inverts foreground and background colors.
    pub fn invert(self: Style) Style {
        return self.withEffects(.INVERT);
    }

    /// Hides output text.
    pub fn hidden(self: Style) Style {
        return self.withEffects(.HIDDEN);
    }

    /// Adds a strikethrough line across text.
    pub fn strikethrough(self: Style) Style {
        return self.withEffects(.STRIKETHROUGH);
    }

    /// Adds a double underline text effect.
    pub fn doubleUnderline(self: Style) Style {
        return self.withEffects(.DOUBLE_UNDERLINE);
    }

    /// Merges two styles. Colors in `rhs` take precedence when present, and effects union together.
    pub fn merge(self: Style, rhs: Style) Style {
        return .{
            .fg = rhs.fg orelse self.fg,
            .bg = rhs.bg orelse self.bg,
            .effects = self.effects.bitOr(rhs.effects),
        };
    }

    /// Sets the foreground color only when `self` lacks an existing foreground color.
    pub fn withColor(self: Style, color: Color) Style {
        return Style.new().fgColor(color).merge(self);
    }

    /// Wraps a borrowed string slice with this style and appends an ANSI reset sequence.
    pub fn paint(self: Style, text: []const u8) StyledText {
        return .{ .style = self, .text = text };
    }

    /// Formats the opening SGR sequence (`\x1b[...m`) via `{f}`. Does nothing when plain.
    pub fn format(self: Style, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.writeAnsi(writer);
    }

    /// Writes the standard ANSI reset sequence (`\x1b[0m`) to clear terminal styling.
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

/// Helper struct returned by `Style.paint`. Wraps text with styling escape codes.
pub const StyledText = struct {
    /// Style applied to the wrapped text.
    style: Style,
    /// Borrowed text slice. Must outlive the print operation.
    text: []const u8,

    /// Writes opening style codes, text content, and terminal reset sequences.
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

/// Color palette configuration used for help guides and CLI diagnostic output.
pub const Styles = struct {
    /// Style applied to section titles and framing bars.
    header: Style = .{},
    /// Style applied to command usage instructions.
    usage: Style = .{},
    /// Style applied to flags, options, and literals.
    literal: Style = .{},
    /// Style applied to argument placeholders and value labels.
    placeholder: Style = .{},
    /// Style applied to error labels and fatal error messages.
    @"error": Style = .{},
    /// Style applied to successful badges and valid choices.
    valid: Style = .{},
    /// Style applied to invalid values and highlighted warnings.
    invalid: Style = .{},
    /// Style applied to warnings and required tags.
    warning: Style = .{},
    /// Style applied to secondary descriptions and dimmed tips.
    muted: Style = .{},

    /// Returns empty styles without color or text effects.
    pub fn plain() Styles {
        return .{};
    }

    /// Returns styled defaults unless `NO_COLOR` is present in the process environment.
    pub fn styled() Styles {
        if (std.c.getenv("NO_COLOR") != null) return plain();
        return themed();
    }

    /// Returns plain styles when `no_color` is true; otherwise returns the themed defaults.
    pub fn styledUnless(no_color: bool) Styles {
        if (no_color) return plain();
        return themed();
    }

    /// Returns the standard colored theme directly, ignoring `NO_COLOR`.
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

    /// Sets the header style slot.
    pub fn setHeader(self: Styles, style: Style) Styles {
        var next = self;
        next.header = style;
        return next;
    }

    /// Sets the usage style slot.
    pub fn setUsage(self: Styles, style: Style) Styles {
        var next = self;
        next.usage = style;
        return next;
    }

    /// Sets the literal style slot.
    pub fn setLiteral(self: Styles, style: Style) Styles {
        var next = self;
        next.literal = style;
        return next;
    }

    /// Sets the placeholder style slot.
    pub fn setPlaceholder(self: Styles, style: Style) Styles {
        var next = self;
        next.placeholder = style;
        return next;
    }

    /// Sets the error style slot.
    pub fn setError(self: Styles, style: Style) Styles {
        var next = self;
        next.@"error" = style;
        return next;
    }

    /// Sets the valid choice style slot.
    pub fn setValid(self: Styles, style: Style) Styles {
        var next = self;
        next.valid = style;
        return next;
    }

    /// Sets the invalid choice style slot.
    pub fn setInvalid(self: Styles, style: Style) Styles {
        var next = self;
        next.invalid = style;
        return next;
    }

    /// Sets the warning style slot.
    pub fn setWarning(self: Styles, style: Style) Styles {
        var next = self;
        next.warning = style;
        return next;
    }

    /// Sets the muted text style slot.
    pub fn setMuted(self: Styles, style: Style) Styles {
        var next = self;
        next.muted = style;
        return next;
    }
};

// Preset style constants.

/// Preset bold effect.
pub const BOLD: Style = Style.new().bold();
/// Preset dim effect.
pub const DIM: Style = Style.new().dim();
/// Preset italic effect.
pub const ITALIC: Style = Style.new().italic();
/// Preset underline effect.
pub const UNDERLINE: Style = Style.new().underline();

/// Preset standard black foreground.
pub const BLACK: Style = Style.new().fgColor(.black);
/// Preset standard red foreground.
pub const RED: Style = Style.new().fgColor(.red);
/// Preset standard green foreground.
pub const GREEN: Style = Style.new().fgColor(.green);
/// Preset standard yellow foreground.
pub const YELLOW: Style = Style.new().fgColor(.yellow);
/// Preset standard blue foreground.
pub const BLUE: Style = Style.new().fgColor(.blue);
/// Preset standard magenta foreground.
pub const MAGENTA: Style = Style.new().fgColor(.magenta);
/// Preset standard cyan foreground.
pub const CYAN: Style = Style.new().fgColor(.cyan);
/// Preset standard white foreground.
pub const WHITE: Style = Style.new().fgColor(.white);

/// Preset bright black foreground.
pub const BRIGHT_BLACK: Style = Style.new().fgColor(.bright_black);
/// Preset bright red foreground.
pub const BRIGHT_RED: Style = Style.new().fgColor(.bright_red);
/// Preset bright green foreground.
pub const BRIGHT_GREEN: Style = Style.new().fgColor(.bright_green);
/// Preset bright yellow foreground.
pub const BRIGHT_YELLOW: Style = Style.new().fgColor(.bright_yellow);
/// Preset bright blue foreground.
pub const BRIGHT_BLUE: Style = Style.new().fgColor(.bright_blue);
/// Preset bright magenta foreground.
pub const BRIGHT_MAGENTA: Style = Style.new().fgColor(.bright_magenta);
/// Preset bright cyan foreground.
pub const BRIGHT_CYAN: Style = Style.new().fgColor(.bright_cyan);
/// Preset bright white foreground.
pub const BRIGHT_WHITE: Style = Style.new().fgColor(.bright_white);

/// Preset orange foreground.
pub const ORANGE: Style = Style.new().fgColor(.orange);
/// Preset purple foreground.
pub const PURPLE: Style = Style.new().fgColor(.purple);
/// Preset pink foreground.
pub const PINK: Style = Style.new().fgColor(.pink);
/// Preset teal foreground.
pub const TEAL: Style = Style.new().fgColor(.teal);
/// Preset gold foreground.
pub const GOLD: Style = Style.new().fgColor(.gold);
/// Preset silver foreground.
pub const SILVER: Style = Style.new().fgColor(.silver);
/// Preset lime foreground.
pub const LIME: Style = Style.new().fgColor(.lime);
/// Preset indigo foreground.
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

test "themed slots match default colors" {
    const theme = Styles.themed();
    try std.testing.expect(theme.header.effects.contains(.BOLD));
    try std.testing.expect(theme.header.effects.contains(.UNDERLINE));
    try std.testing.expectEqual(@as(?Color, .bright_cyan), theme.literal.fg);
    try std.testing.expect(theme.muted.effects.contains(.DIM));
    try std.testing.expect(theme.@"error".effects.contains(.BOLD));
}
