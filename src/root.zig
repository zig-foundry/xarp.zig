//! # Xarp
//!
//! A zero-dependency command-line argument parser with a
//! self-contained ANSI styling engine (24 named colors, 8-bit 256-color,
//! and 24-bit TrueColor).

const std = @import("std");

/// Color definitions and ANSI escape sequence generation.
pub const color = @import("color.zig");

pub const Color = color.Color;
pub const Rgb = color.Rgb;
pub const RESET = color.RESET;

test {
    std.testing.refAllDecls(@This());
}
