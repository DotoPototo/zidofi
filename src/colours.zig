const std = @import("std");
const app = @import("main.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");

const FULL_PIXEL_CHAR = "█";
const MAX_COLOR = 256;

pub var foreground_colors: [MAX_COLOR][]u8 = undefined;
pub var background_colors: [MAX_COLOR][]u8 = undefined;

pub fn printColorBlock(color: usize) !void {
    // These are two characters wide
    try writers.writeFormattedBufferedFrame("\x1b[48;5;{d}m  \x1b[0m", .{color});
}

pub fn testTerminalColors() !void {
    term.resetScreen();
    term.altScreenOn();

    try app.writeHeader();
    try writers.printCentered("Terminal colours and gradients test:\n\n");

    try writers.writeBufferedFrame("System colors:\n");
    for (0..16) |i| {
        try printColorBlock(i);
    }
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    // Print 24 grayscale colors
    try writers.writeBufferedFrame("Grayscale:\n");
    for (232..256) |i| {
        try printColorBlock(i);
    }
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    // Print 216 color cubes
    try writers.writeBufferedFrame("Color cubes:\n");
    for (0..6) |r| {
        for (0..6) |g| {
            for (0..6) |b| {
                const color = 16 + 36 * r + 6 * g + b;
                try printColorBlock(color);
            }

            try writers.writeBufferedFrame("  "); // Space between g sections
        }
        try writers.writeBufferedFrame("\n"); // Newline after r section
    }
    try writers.writeBufferedFrame("\n");
    try writers.flushWriterBuffer();

    // Print 24-bit truecolor gradient
    try drawTrueColorGradient();

    // Print error-dithered truecolor gradient
    try drawSmoothGradient();

    try term.pressEnterToContinue();
}

// MARK: Colour Setup

pub fn initColors() void {
    var color_index: u16 = 0;
    while (color_index < MAX_COLOR) : (color_index += 1) {
        foreground_colors[color_index] = std.fmt.allocPrint(app.ALLOCATOR, "{s}38;5;{d}m", .{ term.csi, color_index }) catch unreachable;
        background_colors[color_index] = std.fmt.allocPrint(app.ALLOCATOR, "{s}48;5;{d}m", .{ term.csi, color_index }) catch unreachable;
    }
}

// MARK: True Color Gradient

fn printTrueColorBlock(r: u8, g: u8, b: u8) !void {
    // These are two characters wide
    try writers.writeFormattedBufferedFrame("\x1b[48;2;{d};{d};{d}m  \x1b[0m", .{ r, g, b });
}

fn drawTrueColorGradient() !void {
    try writers.writeBufferedFrame("Truecolor gradient:\n");
    const width = term.term_size.width / 2;
    for (0..width) |i| {
        const x: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width - 1));
        const r: u8 = @intFromFloat(255.0 * (1.0 - x));
        const g: u8 = @intFromFloat(255.0 * (1.0 - @abs(x - 0.5) * 2.0));
        const b: u8 = @intFromFloat(255.0 * x);
        try printTrueColorBlock(r, g, b);
    }
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();
}

// MARK: Error Diffusion Dithering Gradient

fn printSmoothTrueColorBlock(r: u8, g: u8, b: u8) !void {
    try writers.writeFormattedBufferedFrame("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ r, g, b, FULL_PIXEL_CHAR });
}

fn applyDithering(value: f32, err: *f32) u8 {
    const new_value = value + err.*;
    const rounded = @round(new_value);
    err.* = new_value - rounded;
    return @intFromFloat(std.math.clamp(rounded, 0, 255));
}

fn calculateColor(t: f32) struct { r: f32, g: f32, b: f32 } {
    if (t < 0.33) {
        // Blue to Purple
        return .{
            .r = 255 * std.math.pow(f32, t * 3, 1.5),
            .g = 0,
            .b = 255,
        };
    } else if (t < 0.66) {
        // Purple to Red
        const normalized_t = (t - 0.33) * 3;
        return .{
            .r = 255,
            .g = 0,
            .b = 255 * (1 - std.math.pow(f32, normalized_t, 2)),
        };
    } else {
        // Red to Orange to Yellow
        const normalized_t = (t - 0.66) * 3;
        return .{
            .r = 255,
            .g = 255 * std.math.pow(f32, normalized_t, 0.7),
            .b = 0,
        };
    }
}

fn drawSmoothGradient() !void {
    try writers.writeBufferedFrame("Error diffusion dithered truecolor gradient:\n");
    const width = term.term_size.width;

    var errors = [_]f32{0} ** 3;

    for (0..width) |x| {
        const x_norm: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));

        const color = calculateColor(x_norm);

        // Apply dithering
        const r = applyDithering(color.r, &errors[0]);
        const g = applyDithering(color.g, &errors[1]);
        const b = applyDithering(color.b, &errors[2]);

        try printSmoothTrueColorBlock(r, g, b);
    }

    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();
}
