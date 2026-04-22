const std = @import("std");

const app = @import("main.zig");
const state = @import("state.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");

const FULL_PIXEL_CHAR = "█";
const MAX_COLOR = 256;

pub var foreground_colors: [MAX_COLOR][]const u8 = .{""} ** MAX_COLOR;
pub var background_colors: [MAX_COLOR][]const u8 = .{""} ** MAX_COLOR;
var colors_initialized: u16 = 0;

// MARK: Colour Setup

pub fn initColors() !void {
    errdefer deinitColors();
    while (colors_initialized < MAX_COLOR) {
        foreground_colors[colors_initialized] = try std.fmt.allocPrint(app.gpa, "{s}38;5;{d}m", .{ term.csi, colors_initialized });
        errdefer app.gpa.free(foreground_colors[colors_initialized]);
        background_colors[colors_initialized] = try std.fmt.allocPrint(app.gpa, "{s}48;5;{d}m", .{ term.csi, colors_initialized });
        colors_initialized += 1;
    }
}

pub fn deinitColors() void {
    var i: u16 = 0;
    while (i < colors_initialized) : (i += 1) {
        app.gpa.free(foreground_colors[i]);
        app.gpa.free(background_colors[i]);
    }
    colors_initialized = 0;
}

// MARK: Test Functions

pub fn testTerminalColors() !void {
    try term.resetScreen();
    try term.altScreenOn();

    try term.writeHeader();
    try writers.printCentered("Terminal colours and gradients test:\n\n");

    try writers.write("System colors:\n");
    for (0..16) |i| try printColorBlock(i);
    try writers.write("\n\n");
    try writers.flush();

    // Print 24 grayscale colors
    try writers.write("Grayscale:\n");
    for (232..256) |i| try printColorBlock(i);
    try writers.write("\n\n");
    try writers.flush();

    // Print 216 color cubes
    try writers.write("Color cubes:\n");
    for (0..6) |r| {
        for (0..6) |g| {
            for (0..6) |b| {
                const color = 16 + 36 * r + 6 * g + b;
                try printColorBlock(color);
            }
            try writers.write("  "); // Space between g sections
        }
        try writers.write("\n"); // Newline after r section
    }
    try writers.write("\n");
    try writers.flush();

    // Print 24-bit truecolor gradient
    try drawTrueColorGradient();

    // Print error-dithered truecolor gradient
    try drawDitheredGradient();

    if (state.shouldQuit()) return;
    try term.pressEnterToContinue();
}

// MARK: Color Printing Blocks

pub fn printColorBlock(color: usize) !void {
    try writers.print("\x1b[48;5;{d}m  \x1b[0m", .{color}); // Two characters wide
}

fn printSmoothColorBlock(r: u8, g: u8, b: u8) !void {
    try writers.print("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ r, g, b, FULL_PIXEL_CHAR }); // One character wide
}

// MARK: True Color Gradient

fn drawTrueColorGradient() !void {
    try writers.write("Truecolor gradient:\n");
    const width = term.term_size.width;
    if (width <= 1) return;
    for (0..width) |i| {
        const x: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width - 1));
        const r: u8 = @trunc(255.0 * (1.0 - x));
        const g: u8 = @trunc(255.0 * (1.0 - @abs(x - 0.5) * 2.0));
        const b: u8 = @trunc(255.0 * x);
        try printSmoothColorBlock(r, g, b);
    }
    try writers.write("\n\n");
    try writers.flush();
}

// MARK: Error Diffusion Dithering Gradient

fn applyDithering(value: f32, err: *f32) u8 {
    const new_value = value + err.*;
    const rounded: f32 = @round(new_value);
    err.* = new_value - rounded;
    return @trunc(std.math.clamp(rounded, 0, 255));
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

fn drawDitheredGradient() !void {
    try writers.write("Error diffusion dithered truecolor gradient:\n");
    const width = term.term_size.width;
    if (width <= 1) return;

    var errors = [_]f32{0} ** 3;

    for (0..width) |x| {
        const x_norm: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));

        const color = calculateColor(x_norm);

        // Apply dithering
        const r = applyDithering(color.r, &errors[0]);
        const g = applyDithering(color.g, &errors[1]);
        const b = applyDithering(color.b, &errors[2]);

        try printSmoothColorBlock(r, g, b);
    }

    try writers.write("\n\n");
    try writers.flush();
}
