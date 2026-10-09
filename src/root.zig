//! # Xarp
//!
//! Official Zig port of the Rust `xarp` crate: a command-line argument
//! parser with a self-contained ANSI styling engine (24 named colors,
//! 8-bit 256-color, and 24-bit TrueColor).
//!
//! Operators and trait returns from the Rust crate are methods here.
//! `merge` and `bitOr` replace `|`. `Outcome` carries help, version, and
//! parse text. Call `deinit` on owned results. `Styles.styled` reads
//! `NO_COLOR` through libc `getenv`. Pass argv from `init.minimal.args`.

const std = @import("std");

/// Color definitions and ANSI escape sequence generation.
pub const color = @import("color.zig");

/// ANSI text style modifiers and font effects bitflags.
pub const effect = @import("effect.zig");

/// Text styles, ANSI output formatting, and CLI theme configurations.
pub const style = @import("style.zig");

/// Parse and help/version errors. Messages are allocated; call `deinit`.
pub const errors = @import("errors.zig");

/// Argument definitions, parsing, and matches.
pub const xarp = @import("xarp.zig");

pub const Color = color.Color;
pub const Rgb = color.Rgb;
pub const RESET = color.RESET;

pub const Effects = effect.Effects;

pub const Style = style.Style;
pub const StyledText = style.StyledText;
pub const Styles = style.Styles;

pub const XarpError = errors.XarpError;
pub const Xarp = xarp.Xarp;
pub const Arg = xarp.Arg;
pub const ArgAction = xarp.ArgAction;
pub const ArgMatches = xarp.ArgMatches;
pub const Outcome = xarp.Outcome;

pub const BOLD = style.BOLD;
pub const DIM = style.DIM;
pub const ITALIC = style.ITALIC;
pub const UNDERLINE = style.UNDERLINE;

pub const BLACK = style.BLACK;
pub const RED = style.RED;
pub const GREEN = style.GREEN;
pub const YELLOW = style.YELLOW;
pub const BLUE = style.BLUE;
pub const MAGENTA = style.MAGENTA;
pub const CYAN = style.CYAN;
pub const WHITE = style.WHITE;

pub const BRIGHT_BLACK = style.BRIGHT_BLACK;
pub const BRIGHT_RED = style.BRIGHT_RED;
pub const BRIGHT_GREEN = style.BRIGHT_GREEN;
pub const BRIGHT_YELLOW = style.BRIGHT_YELLOW;
pub const BRIGHT_BLUE = style.BRIGHT_BLUE;
pub const BRIGHT_MAGENTA = style.BRIGHT_MAGENTA;
pub const BRIGHT_CYAN = style.BRIGHT_CYAN;
pub const BRIGHT_WHITE = style.BRIGHT_WHITE;

pub const ORANGE = style.ORANGE;
pub const PURPLE = style.PURPLE;
pub const PINK = style.PINK;
pub const TEAL = style.TEAL;
pub const GOLD = style.GOLD;
pub const SILVER = style.SILVER;
pub const LIME = style.LIME;
pub const INDIGO = style.INDIGO;

test {
    // Referencing each file pulls its `test` blocks into `zig build test`.
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("color.zig"));
    std.testing.refAllDecls(@import("effect.zig"));
    std.testing.refAllDecls(@import("style.zig"));
    std.testing.refAllDecls(@import("errors.zig"));
    std.testing.refAllDecls(@import("xarp.zig"));
}
