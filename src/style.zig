const std = @import("std");
const Color = @import("color.zig").Color;
const Effects = @import("effect.zig").Effects;
pub const Style = struct {
    /// Foreground color.
    fg: Color,
    /// Background color.
    bg: Color,
    /// Set of visual text effects.
    effects: Effects,

    pub fn new() @This() {
        return Style{
            .fg = null,
            .bg = null,
            .effects = Effects.NONE,
        };
    }
};
