const std = @import("std");
const app = @import("main.zig");
const system = @import("system.zig");
const colours = @import("colours.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");

const FIRE_COLOURS = [_]u8{ 0, 233, 234, 52, 53, 88, 89, 94, 95, 96, 130, 131, 132, 133, 172, 214, 215, 220, 220, 221, 3, 226, 227, 230, 195, 230 };
const PIXEL_CHAR = "▀";

fn printFirePixel(fg_color: usize, bg_color: usize) !void {
    try writers.writeFormattedBufferedFrame("\x1b[38;5;{d}m\x1b[48;5;{d}m{s}\x1b[0m", .{ fg_color, bg_color, PIXEL_CHAR });
}

// MARK: Fire Palette

pub fn printFirePalette() !void {
    term.resetScreen();
    term.altScreenOn();

    try app.writeHeader();
    try writers.printCentered("\x1b[38;5;208mThe following screen will display the DOOM fire algorithm - please wait for it to finish!\n\n");
    writers.print(term.reset_color);

    // Print fire palette
    try writers.writeBufferedFrame("Fire palette:\n");
    for (FIRE_COLOURS) |color| {
        try colours.printColorBlock(color);
    }
    try writers.flushWriterBuffer();
    try writers.writeBufferedFrame("\n\n");

    try writers.writeBufferedFrame("Half height pixel character:\n");
    try writers.writeFormattedBufferedFrame("{s}", .{PIXEL_CHAR});
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    try writers.writeBufferedFrame("Half height pixel fire on white:\n");
    for (FIRE_COLOURS) |color| {
        try printFirePixel(color, 255);
    }
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    try writers.writeBufferedFrame("Half height pixel fire on black:\n");
    for (FIRE_COLOURS) |color| {
        try printFirePixel(color, 0);
    }
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    try term.pressEnterToContinue();
}

// MARK: Fire Display Buffer

// TODO: Move these (doom fire struct?)
var display_buffer: []u8 = undefined;
var display_buffer_index: u32 = 0;
var display_buffer_length: u32 = 0;

fn initDisplayBuffer() !void {
    const pixel_character_size = PIXEL_CHAR.len;
    const pixel_color_size = colours.foreground_colors[0].len + colours.background_colors[0].len;
    const pixel_size = pixel_character_size + pixel_color_size;
    const screen_size: u64 = pixel_size * term.term_size.width * term.term_size.height;
    const overflow_size: u64 = pixel_character_size * term.term_size.width;
    const buffer_size: u64 = screen_size + overflow_size;

    display_buffer = try app.ALLOCATOR.alloc(u8, buffer_size * 2);
    resetDisplayBuffer();
}

fn resetDisplayBuffer() void {
    display_buffer_index = 0;
    display_buffer_length = 0;
}

fn addToDisplayBuffer(string: []const u8) void {
    @memcpy(display_buffer[display_buffer_index .. display_buffer_index + string.len], string);
    display_buffer_index += @intCast(string.len);
    display_buffer_length += @intCast(string.len);
}

fn freeDisplayBuffer() void {
    app.ALLOCATOR.free(display_buffer);
}

fn printDisplayBuffer() !void {
    writers.print(display_buffer[0..display_buffer_length]);
    resetDisplayBuffer();
}

// MARK: Fire Algorithm

fn doFire(FIRE_WIDTH: u16, FIRE_HEIGHT: u16, fire_buffer: *[]u8) void {
    var fire_x: u16 = 0;
    while (fire_x < FIRE_WIDTH) : (fire_x += 1) {
        var fire_y: u16 = 1;
        while (fire_y < FIRE_HEIGHT) : (fire_y += 1) {
            const source_index: u16 = fire_y * FIRE_WIDTH + fire_x;
            spreadFire(source_index, FIRE_WIDTH, fire_buffer);
        }
    }
}

fn spreadFire(source_index: u16, FIRE_WIDTH: u16, fire_buffer: *[]u8) void {
    const pixel = fire_buffer.*[source_index];
    if (pixel == 0) {
        fire_buffer.*[source_index - FIRE_WIDTH] = 0;
    } else {
        const random_index: u8 = app.random.intRangeAtMost(u8, 0, 3);
        var destination: u16 = source_index - random_index + 1;
        if (destination < FIRE_WIDTH) {
            destination = FIRE_WIDTH;
        }
        fire_buffer.*[destination - FIRE_WIDTH] = pixel - (random_index & 1);
    }
}

pub fn run() !void {
    try initDisplayBuffer();
    defer freeDisplayBuffer();

    // Doom fire sizes
    const FIRE_WIDTH: u16 = term.term_size.width;
    const FIRE_HEIGHT: u16 = term.term_size.height * 2; // Double height due to half block characters
    const FIRE_SIZE: u16 = FIRE_WIDTH * FIRE_HEIGHT;
    const FIRE_LAST_ROW: u16 = (FIRE_HEIGHT - 1) * FIRE_WIDTH;

    // Doom fire colours
    const FIRE_BLACK: u8 = 0;
    const FIRE_WHITE: u8 = FIRE_COLOURS.len - 1; // Index of last colour aka white

    // Doom fire buffers
    var fire_buffer: []u8 = try app.ALLOCATOR.alloc(u8, FIRE_SIZE);
    defer app.ALLOCATOR.free(fire_buffer);

    // Initialize fire buffer (defaults to black)
    @memset(fire_buffer, FIRE_BLACK);

    // Last row of fire is white aka fire source
    var buf_index: u16 = 0;
    while (buf_index < FIRE_WIDTH) : (buf_index += 1) {
        fire_buffer[FIRE_LAST_ROW + buf_index] = FIRE_WHITE;
    }

    // Ensure terminal is in correct mode
    term.altScreenOn();

    // Setup initial frame
    const init_frame = std.fmt.allocPrint(app.ALLOCATOR, "{s}{s}{s}", .{ term.cursor_home, colours.background_colors[0], colours.foreground_colors[0] }) catch unreachable;
    defer app.ALLOCATOR.free(init_frame);

    var prev_pixel_foreground: u8 = 0;
    var prev_pixel_background: u8 = 0;

    var timer = try std.time.Timer.start();

    var loop_count: u16 = 0;
    var loop_limit: u16 = 666;
    if (app.endless_mode) {
        loop_limit = 65535;
    }
    while (loop_count < loop_limit) : (loop_count += 1) {
        doFire(FIRE_WIDTH, FIRE_HEIGHT, &fire_buffer);

        resetDisplayBuffer();
        addToDisplayBuffer(init_frame);

        // Display the fire
        var frame_y: u16 = 0;
        while (frame_y < FIRE_HEIGHT) : (frame_y += 2) {
            var frame_x: u16 = 0;
            while (frame_x < FIRE_WIDTH) : (frame_x += 1) {
                const pixel_foreground: u8 = fire_buffer[frame_y * FIRE_WIDTH + frame_x];
                const pixel_background: u8 = fire_buffer[(frame_y + 1) * FIRE_WIDTH + frame_x];

                // No need to re-add the same colour if it's already set
                if (pixel_background != prev_pixel_background) {
                    addToDisplayBuffer(colours.background_colors[FIRE_COLOURS[pixel_background]]);
                }
                if (pixel_foreground != prev_pixel_foreground) {
                    addToDisplayBuffer(colours.foreground_colors[FIRE_COLOURS[pixel_foreground]]);
                }
                addToDisplayBuffer(PIXEL_CHAR);

                prev_pixel_foreground = pixel_foreground;
                prev_pixel_background = pixel_background;
            }
        }

        try printDisplayBuffer();
    }

    // Reset terminal and display results
    term.resetScreen();
    term.altScreenOn();
    const elapsed = timer.lap();
    const fps = @as(f64, @floatFromInt(loop_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
    if (fps < 5 or fps > 1000) {
        try writers.stdout.print("Results do not seem accurate - test may not have ran correctly\n", .{});
    }
    try writers.stdout.print("\x1b[38;5;70mAverage FPS: {d:.2}{s}\n", .{ fps, term.reset_color });
    try writers.stdout.print("Visual results may vary depending on terminal refresh capabilities\n\n", .{});
    try system.printSystemUsage(false);
    try term.pressEnterToContinue();
}
