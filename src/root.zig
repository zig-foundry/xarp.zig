//! ```zig
//! var app = xarp.Xarp.new(allocator, "demo");
//! defer app.deinit();
//! try app.addArg(xarp.Arg.new("verbose").withShort('v').withLong("verbose").withAction(.set_true));
//! ```
//!
//! Zig port of the Rust `xarp` crate. Parses CLI args and styles terminal output.
//!
//! - Call `deinit` on `Xarp` and `Outcome` or you leak memory.
//! - `Outcome` holds `.matches` or `.err`; only allocation failures return `try` errors.
//! - Pass argv from `init.minimal.args.toSlice(allocator)`.
//! - `Styles.styled` checks `NO_COLOR` with libc `getenv`; presence alone disables color.

const std = @import("std");

/// Color types and ANSI code writers (`Color`, `Rgb`, `RESET`).
pub const color = @import("color.zig");

/// Bitmask text effects (`Effects`: bold, italic, underline, ...).
pub const effect = @import("effect.zig");

/// `Style`, `StyledText`, `Styles`, and preset constants (`RED`, `BOLD`, ...).
pub const style = @import("style.zig");

/// `XarpError`: help, version, and parse failures. Call `deinit` on each value.
pub const errors = @import("errors.zig");

/// `Xarp`, `Arg`, `ArgMatches`, and `Outcome` plus parsing entry points.
pub const xarp = @import("xarp.zig");

pub const Color = color.Color;
/// RGB triple for `Color.rgb`.
pub const Rgb = color.Rgb;
/// `\x1b[0m`. Print it after styled text or color bleeds onward.
pub const RESET = color.RESET;

/// Bitmask text effects. Combine with `bitOr`.
pub const Effects = effect.Effects;

/// Foreground + background + effects. Build with `Style.new().bold().fgColor(...)`.
pub const Style = style.Style;
/// `Style` + text pair returned by `Style.paint`. Prints with `{f}`.
pub const StyledText = style.StyledText;
/// Theme for help and error output. `Styles.styled()` checks `NO_COLOR`.
pub const Styles = style.Styles;

/// Help, version, or parse failure. Call `deinit` or you leak the message.
pub const XarpError = errors.XarpError;
/// Parser and app config. Add args, then call `tryGetMatchesFrom`.
pub const Xarp = xarp.Xarp;
/// Single argument definition. Build with `Arg.new("id").withLong(...)`.
pub const Arg = xarp.Arg;
/// What to do when an arg appears: `.set_true`, `.set`, or `.append`.
pub const ArgAction = xarp.ArgAction;
/// Parsed flags and values. Read with `getFlag`, `getOne`, `getMany`.
pub const ArgMatches = xarp.ArgMatches;
/// `.matches` on success, `.err` for help, version, or bad input.
pub const Outcome = xarp.Outcome;

/// Bold preset.
pub const BOLD = style.BOLD;
/// Dim preset.
pub const DIM = style.DIM;
/// Italic preset.
pub const ITALIC = style.ITALIC;
/// Underline preset.
pub const UNDERLINE = style.UNDERLINE;

/// Black fg preset.
pub const BLACK = style.BLACK;
/// Red fg preset.
pub const RED = style.RED;
/// Green fg preset.
pub const GREEN = style.GREEN;
/// Yellow fg preset.
pub const YELLOW = style.YELLOW;
/// Blue fg preset.
pub const BLUE = style.BLUE;
/// Magenta fg preset.
pub const MAGENTA = style.MAGENTA;
/// Cyan fg preset.
pub const CYAN = style.CYAN;
/// White fg preset.
pub const WHITE = style.WHITE;

/// Bright-black (gray) fg preset.
pub const BRIGHT_BLACK = style.BRIGHT_BLACK;
/// Bright-red fg preset.
pub const BRIGHT_RED = style.BRIGHT_RED;
/// Bright-green fg preset.
pub const BRIGHT_GREEN = style.BRIGHT_GREEN;
/// Bright-yellow fg preset.
pub const BRIGHT_YELLOW = style.BRIGHT_YELLOW;
/// Bright-blue fg preset.
pub const BRIGHT_BLUE = style.BRIGHT_BLUE;
/// Bright-magenta fg preset.
pub const BRIGHT_MAGENTA = style.BRIGHT_MAGENTA;
/// Bright-cyan fg preset.
pub const BRIGHT_CYAN = style.BRIGHT_CYAN;
/// Bright-white fg preset.
pub const BRIGHT_WHITE = style.BRIGHT_WHITE;

/// Orange (ANSI 208) fg preset.
pub const ORANGE = style.ORANGE;
/// Purple (ANSI 129) fg preset.
pub const PURPLE = style.PURPLE;
/// Pink (ANSI 205) fg preset.
pub const PINK = style.PINK;
/// Teal (ANSI 30) fg preset.
pub const TEAL = style.TEAL;
/// Gold (ANSI 220) fg preset.
pub const GOLD = style.GOLD;
/// Silver (ANSI 248) fg preset.
pub const SILVER = style.SILVER;
/// Lime (ANSI 118) fg preset.
pub const LIME = style.LIME;
/// Indigo (ANSI 54) fg preset.
pub const INDIGO = style.INDIGO;

test {
    // Pulls each module's `test` blocks into `zig build test`.
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("color.zig"));
    std.testing.refAllDecls(@import("effect.zig"));
    std.testing.refAllDecls(@import("style.zig"));
    std.testing.refAllDecls(@import("errors.zig"));
    std.testing.refAllDecls(@import("xarp.zig"));
}
