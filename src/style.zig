const std = @import("std");
const Color = @import("color.zig").Color;
const Effects = @import("effect.zig").Effects;
pub const Style = struct {
    /// Foreground color.
    fg: ?Color = null,
    /// Background color.
    bg: ?Color = null,
    /// Set of visual text effects.
    effects: Effects = .NONE,

    pub fn new() Style {
        return .{};
    }

    pub fn isPlain(self: Style) bool {
        return self.fg == null and self.bg == null and self.effects.isEmpty();
    }

    pub fn fgColor(self: Style, color: Color) Style {
        var next = self;
        next.fg = color;
        return next;
    }

    pub fn bgColor(self: Style, color: Color) Style {
        var next = self;
        next.bg = color;
        return next;
    }

    pub fn withEffects(self: Style, effects: Effects) Style {
        var next = self;
        next.effects = self.effects.insert(effects);
        return next;
    }
};
