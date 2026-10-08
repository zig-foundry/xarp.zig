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
};
