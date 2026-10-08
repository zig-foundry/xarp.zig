//! ANSI text style modifiers and font effects.
//!
//! The inner value is a bitmask; only the ten documented flag bits are valid.
//! Use `Effects.fromBits` to fallibly convert a raw mask.
//!
//! Rust's `Effects` is a tuple struct around `u16`, not an enum. Zig has no
//! operator overloading, so `|`, `&`, and `!` are methods: `bitOr`, `bitAnd`,
//! and `bitNot` (plus the `*Assign` variants).

const std = @import("std");

/// ANSI text style modifiers and font effects.
///
/// Raw bitflags representation. Only bits covered by `Effects.ALL` are defined.
pub const Effects = struct {
    bits: u16 = 0,
};
