//! The root module for `xarp.zig`.
//!
//! Exposes argument parsing primitives, outcome containers, and ANSI styling tools.
//!
//! - Always call `deinit` on `Xarp` and `Outcome` instances to free allocated buffers.
//! - `Outcome` holds either `.matches` or `.err`; memory allocation errors propagate via `try`.
//! - Pass command-line arguments using `init.minimal.args.toSlice(allocator)`.
//! - `Styles.styled` checks `NO_COLOR` through libc `getenv`.

const std = @import("std");

/// ANSI colors and SGR parameter formatting (`Color`, `Rgb`, `RESET`).
pub const color = @import("color.zig");

/// Bitmask operations for text effects (`Effects`).
pub const effect = @import("effect.zig");

/// Text styling primitives and themes (`Style`, `StyledText`, `Styles`).
pub const style = @import("style.zig");

/// Error and exit representations (`XarpError`).
pub const errors = @import("errors.zig");

/// Core parser, argument specifications, and outcome types.
pub const xarp = @import("xarp.zig");

pub const Color = color.Color;
/// RGB triple for 24-bit TrueColor.
pub const Rgb = color.Rgb;
/// ANSI reset escape code sequence.
pub const RESET = color.RESET;

/// Text attribute bitmask.
pub const Effects = effect.Effects;

/// Combined text style with colors and effects.
pub const Style = style.Style;
/// Text wrapped with opening and closing style escape sequences.
pub const StyledText = style.StyledText;
/// Help and diagnostic display theme.
pub const Styles = style.Styles;

/// Error or early-exit result containing an owned message.
pub const XarpError = errors.XarpError;
/// Command-line parser definition.
pub const Xarp = xarp.Xarp;
/// Single command-line argument or option definition.
pub const Arg = xarp.Arg;
/// Action executed when matching an argument.
pub const ArgAction = xarp.ArgAction;
/// Parsed flags, options, and positionals.
pub const ArgMatches = xarp.ArgMatches;
/// Parser outcome: holds `.matches` on success or `.err` on failure.
pub const Outcome = xarp.Outcome;

/// Preset bold style.
pub const BOLD = style.BOLD;
/// Preset dim style.
pub const DIM = style.DIM;
/// Preset italic style.
pub const ITALIC = style.ITALIC;
/// Preset underline style.
pub const UNDERLINE = style.UNDERLINE;

/// Preset black foreground.
pub const BLACK = style.BLACK;
/// Preset red foreground.
pub const RED = style.RED;
/// Preset green foreground.
pub const GREEN = style.GREEN;
/// Preset yellow foreground.
pub const YELLOW = style.YELLOW;
/// Preset blue foreground.
pub const BLUE = style.BLUE;
/// Preset magenta foreground.
pub const MAGENTA = style.MAGENTA;
/// Preset cyan foreground.
pub const CYAN = style.CYAN;
/// Preset white foreground.
pub const WHITE = style.WHITE;

/// Preset bright black (charcoal) foreground.
pub const BRIGHT_BLACK = style.BRIGHT_BLACK;
/// Preset bright red foreground.
pub const BRIGHT_RED = style.BRIGHT_RED;
/// Preset bright green foreground.
pub const BRIGHT_GREEN = style.BRIGHT_GREEN;
/// Preset bright yellow foreground.
pub const BRIGHT_YELLOW = style.BRIGHT_YELLOW;
/// Preset bright blue foreground.
pub const BRIGHT_BLUE = style.BRIGHT_BLUE;
/// Preset bright magenta foreground.
pub const BRIGHT_MAGENTA = style.BRIGHT_MAGENTA;
/// Preset bright cyan foreground.
pub const BRIGHT_CYAN = style.BRIGHT_CYAN;
/// Preset bright white foreground.
pub const BRIGHT_WHITE = style.BRIGHT_WHITE;

/// Preset orange foreground.
pub const ORANGE = style.ORANGE;
/// Preset purple foreground.
pub const PURPLE = style.PURPLE;
/// Preset pink foreground.
pub const PINK = style.PINK;
/// Preset teal foreground.
pub const TEAL = style.TEAL;
/// Preset gold foreground.
pub const GOLD = style.GOLD;
/// Preset silver foreground.
pub const SILVER = style.SILVER;
/// Preset lime foreground.
pub const LIME = style.LIME;
/// Preset indigo foreground.
pub const INDIGO = style.INDIGO;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("color.zig"));
    std.testing.refAllDecls(@import("effect.zig"));
    std.testing.refAllDecls(@import("style.zig"));
    std.testing.refAllDecls(@import("errors.zig"));
    std.testing.refAllDecls(@import("xarp.zig"));
}
