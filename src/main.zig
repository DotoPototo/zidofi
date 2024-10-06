const std = @import("std");

// MARK: Globals

const APP_VERSION = "0.1";
const BUFFER_SIZE: usize = 4096;
const FULL_PIXEL_CHAR = "█";
const PIXEL_CHAR = "▀";
const FIRE_COLOURS = [_]u8{ 0, 233, 234, 52, 53, 88, 89, 94, 95, 96, 130, 131, 132, 133, 172, 214, 215, 220, 220, 221, 3, 226, 227, 230, 195, 230 };
const ALLOCATOR = std.heap.page_allocator;

const StdOutWriter = @TypeOf(std.io.getStdOut().writer());

var bufferedWriter: ?std.io.BufferedWriter(BUFFER_SIZE, StdOutWriter) = null;
var random: std.rand.Random = undefined;
var term_size: TermSize = .{ .height = 0, .width = 0 };
var stdout: std.fs.File.Writer = undefined;
var endless_mode: bool = false;
var is_monitoring_term_size: bool = false;

// MARK: Main

pub fn main() !void {
    try initialise();
    defer complete();

    try printFirePalette();
    try showDoomFire();
}

fn complete() void {
    altScreenOff();
}

// MARK: Initialisation

fn initialise() !void {
    try checkArgs();

    try initSignalHandlers();
    initWriters();
    initTermSize();
    initColors();
    try setupRandom();

    try runIntroScreen();
    try testTerminalColors();
    try testLigatures();
}

fn setupRandom() !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    random = prng.random();
}

// MARK: Terminal Escape Sequences

const esc = "\x1B";
const reset_screen = esc ++ "c";
const csi = esc ++ "[";
const screen_buf_on = csi ++ "?1049h";
const screen_buf_off = csi ++ "?1049l";
const cursor_hide = csi ++ "?25l";
const cursor_show = csi ++ "?25h";
const cursor_home = csi ++ "H";
const clear_screen = csi ++ "2J";
const reset_color = csi ++ "0m";

// MARK: Helper Functions

fn altScreenOn() void {
    print(screen_buf_on ++ clear_screen ++ cursor_hide ++ cursor_home);
}

fn altScreenOff() void {
    print(screen_buf_off ++ clear_screen ++ cursor_show ++ cursor_home);
}

fn resetScreen() void {
    print(reset_screen ++ clear_screen ++ cursor_home);
}

fn checkArgs() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--endless")) {
            endless_mode = true;
        }
    }
}

// MARK: Signal Handling

fn sigintHandler(sig: c_int) callconv(.C) void {
    std.debug.print("\nReceived SIGINT {d} (Ctrl-C). Exiting...\n", .{sig});
    resetScreen();
    altScreenOff();
    std.posix.exit(0);
}

fn sigwinchHandler(_: c_int) callconv(.C) void {
    if (is_monitoring_term_size) {
        initTermSize();
        displayIntroScreen() catch {};
        print("\x1b[38;5;226mPress Enter to continue..." ++ reset_color);
    }
}

fn initSignalHandlers() !void {
    // CTRL+C handler
    const sigint = std.posix.SIG.INT;
    try std.posix.sigaction(sigint, &std.posix.Sigaction{
        .handler = .{ .handler = sigintHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    // Terminal resize handler
    _ = try stdout.write("\x1b[?2048h");
    const sigwinch = std.posix.SIG.WINCH;
    try std.posix.sigaction(sigwinch, &std.posix.Sigaction{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);
}

// MARK: Writers

fn print(s: []const u8) void {
    const sz = stdout.write(s) catch unreachable;
    if (sz == 0) {
        return;
    }
    return;
}

fn printCentered(text: []const u8) !void {
    const padding = if (term_size.width > text.len) (term_size.width - text.len) / 2 else 0;
    try stdout.writeByteNTimes(' ', padding);
    try stdout.print("{s}\n", .{text});
}

fn initWriters() void {
    const stdout_writer = std.io.getStdOut().writer();
    bufferedWriter = std.io.bufferedWriter(stdout_writer);

    stdout = std.io.getStdOut().writer();
}

fn writeBufferedFrame(data: []const u8) !void {
    if (bufferedWriter) |*bw| {
        bw.writer().print("{s}", .{data}) catch unreachable;
    } else {
        return error.BufferedWriterNotInitialised;
    }
}

fn writeFormattedBufferedFrame(comptime fmt: []const u8, args: anytype) !void {
    if (bufferedWriter) |*bw| {
        try bw.writer().print(fmt, args);
    } else {
        return error.BufferedWriterNotInitialised;
    }
}

fn flushWriterBuffer() !void {
    if (bufferedWriter) |*bw| {
        try bw.flush();
    } else {
        return error.BufferedWriterNotInitialised;
    }
}

fn writeHeader() !void {
    const headerWidth: u16 = 40;
    const halfTermWidth: u16 = term_size.width / 2;
    const headerOffset: u16 = halfTermWidth - headerWidth / 2;
    const spaceBuffer = try ALLOCATOR.alloc(u8, headerOffset);
    defer ALLOCATOR.free(spaceBuffer);
    @memset(spaceBuffer, ' ');

    try writeBufferedFrame("\x1b[38;5;129m"); // Purple
    try writeBufferedFrame("\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame("███████╗██╗██████╗  ██████╗ ███████╗██╗\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame("╚══███╔╝██║██╔══██╗██╔═══██╗██╔════╝██║\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame("  ███╔╝ ██║██║  ██║██║   ██║█████╗  ██║\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame(" ███╔╝  ██║██║  ██║██║   ██║██╔══╝  ██║\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame("███████╗██║██████╔╝╚██████╔╝██║     ██║\n");
    try writeBufferedFrame(spaceBuffer);
    try writeBufferedFrame("╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝\n");
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    try printCentered("🔥 Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ APP_VERSION ++ "🔥\n\n");
    if (endless_mode) {
        print("\x1b[38;5;196m"); // Red
        try printCentered("Endless mode enabled - press Ctrl+C to exit\n\n");
    }

    // reset the color
    print(reset_color);
}

fn pressEnterToContinue() !void {
    print("\x1b[38;5;226mPress Enter to continue..." ++ reset_color);

    const stdin = std.io.getStdIn().reader();

    stdin.skipUntilDelimiterOrEof('\n') catch unreachable;

    print("\n");
}

// MARK: Terminal Size

pub const TermSize = struct {
    width: u16,
    height: u16,
};

fn initTermSize() void {
    term_size = getTermSize(std.io.getStdOut()) catch |err| {
        std.debug.print("Fatal: Unable to get terminal size: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn getTermSize(file: std.fs.File) !TermSize {
    var buf: std.posix.system.winsize = undefined;

    return block: {
        // Switch on the result of the ioctl call
        switch (std.posix.errno(
            // Try to get the terminal size using the ioctl system call
            std.posix.system.ioctl(
                file.handle,
                std.posix.T.IOCGWINSZ,
                @intFromPtr(&buf),
            ),
        )) {
            // If the ioctl call was successful, break out of the block and return the terminal size
            .SUCCESS => break :block TermSize{
                .width = buf.ws_col,
                .height = buf.ws_row,
            },
            // If the ioctl call failed, return the error
            else => return error.IoctlError,
        }
    };
}

fn outputTerminalSize() !void {
    try writeFormattedBufferedFrame("Terminal size: {d}x{d}\n\n", .{ term_size.width, term_size.height });
    if (term_size.width < 160 or term_size.height < 48) {
        try writeBufferedFrame("The recommended terminal size is 160x48 for the DOOM fire test\n\n");
    }
    try flushWriterBuffer();
}

// MARK: Intro Screen

fn runIntroScreen() !void {
    is_monitoring_term_size = true;
    defer is_monitoring_term_size = false;

    try displayIntroScreen();
    try pressEnterToContinue();
}

fn displayIntroScreen() !void {
    resetScreen();
    altScreenOn();
    try writeHeader();
    try outputTerminalSize();
}

// MARK: Colour Setup

const MAX_COLOR = 256;
var foreground_colors: [MAX_COLOR][]u8 = undefined;
var background_colors: [MAX_COLOR][]u8 = undefined;

fn initColors() void {
    var color_index: u16 = 0;
    while (color_index < MAX_COLOR) : (color_index += 1) {
        foreground_colors[color_index] = std.fmt.allocPrint(ALLOCATOR, "{s}38;5;{d}m", .{ csi, color_index }) catch unreachable;
        background_colors[color_index] = std.fmt.allocPrint(ALLOCATOR, "{s}48;5;{d}m", .{ csi, color_index }) catch unreachable;
    }
}

// MARK: True Color Gradient

fn printTrueColorBlock(r: u8, g: u8, b: u8) !void {
    // These are two characters wide
    try writeFormattedBufferedFrame("\x1b[48;2;{d};{d};{d}m  \x1b[0m", .{ r, g, b });
}

fn drawTrueColorGradient() !void {
    try writeBufferedFrame("Truecolor gradient:\n");
    const width = term_size.width / 2;
    for (0..width) |i| {
        const x: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width - 1));
        const r: u8 = @intFromFloat(255.0 * (1.0 - x));
        const g: u8 = @intFromFloat(255.0 * (1.0 - @abs(x - 0.5) * 2.0));
        const b: u8 = @intFromFloat(255.0 * x);
        try printTrueColorBlock(r, g, b);
    }
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();
}

// MARK: Error Diffusion Dithering Gradient

fn printSmoothTrueColorBlock(r: u8, g: u8, b: u8) !void {
    try writeFormattedBufferedFrame("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ r, g, b, FULL_PIXEL_CHAR });
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
    try writeBufferedFrame("Error diffusion dithered truecolor gradient:\n");
    const width = term_size.width;

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

    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();
}

// MARK: Terminal Color Blocks

fn printColorBlock(color: usize) !void {
    // These are two characters wide
    try writeFormattedBufferedFrame("\x1b[48;5;{d}m  \x1b[0m", .{color});
}

fn testTerminalColors() !void {
    resetScreen();
    altScreenOn();

    try writeBufferedFrame("System colors:\n");
    for (0..16) |i| {
        try printColorBlock(i);
    }
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    // Print 24 grayscale colors
    try writeBufferedFrame("Grayscale:\n");
    for (232..256) |i| {
        try printColorBlock(i);
    }
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    // Print 216 color cubes
    try writeBufferedFrame("Color cubes:\n");
    for (0..6) |r| {
        for (0..6) |g| {
            for (0..6) |b| {
                const color = 16 + 36 * r + 6 * g + b;
                try printColorBlock(color);
            }

            try writeBufferedFrame("  "); // Space between g sections
        }
        try writeBufferedFrame("\n"); // Newline after r section
    }
    try writeBufferedFrame("\n");
    try flushWriterBuffer();

    // Print 24-bit truecolor gradient
    try drawTrueColorGradient();

    // Print error-dithered truecolor gradient
    try drawSmoothGradient();

    try pressEnterToContinue();
}

fn printFirePixel(fg_color: usize, bg_color: usize) !void {
    try writeFormattedBufferedFrame("\x1b[38;5;{d}m\x1b[48;5;{d}m{s}\x1b[0m", .{ fg_color, bg_color, PIXEL_CHAR });
}

fn printFullscreen(buf: []u8) !void {
    for (buf) |pixel| {
        try printFirePixel(pixel, pixel);
    }
    try flushWriterBuffer();
}

// MARK: Terminal Rendering

fn testLigatures() !void {
    altScreenOn();

    const ligature_tests = [_][]const u8{
        "Terminal ligatures and special characters:\n",
        "┌──────────────────────────────┐\n",
        "│ Box Drawing                  │\n",
        "├──────────────────────────────┤\n",
        "│ ┌─┬┐  ┏━┳┓  ╔═╦╗  ╓─╥╖  ╒═╤╕ │\n",
        "│ │ ││  ┃ ┃┃  ║ ║║  ║ ║║  │ ││ │\n",
        "│ ├─┼┤  ┣━╋┫  ╠═╬╣  ╟─╫╢  ╞═╪╡ │\n",
        "│ │ ││  ┃ ┃┃  ║ ║║  ║ ║║  │ ││ │\n",
        "│ └─┴┘  ┗━┻┛  ╚═╩╝  ╙─╨╜  ╘═╧╛ │\n",
        "└──────────────────────────────┘\n\n",
        "Arrows and Symbols:\n",
        "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇐ ⇑ ⇒ ⇓ ⇔ ⇕ ⇖ ⇗ ⇘ ⇙ ⇚ ⇛ ⇜ ⇝ ⇞ ⇟\n\n",
        "Programming Ligatures:\n",
        "== != === !== -> => >= <= << >> /* */ // ++ -- && || ?? ?. ??\n\n",
        "Math Symbols:\n",
        "∀ ∂ ∃ ∅ ∇ ∈ ∉ ∋ ∏ ∑ − ∕ ∗ ∙ √ ∝ ∞ ∠ ∧ ∨ ∩ ∪ ∫ ∴ ∼ ≅ ≈ ≠ ≡ ≤ ≥ ⊂ ⊃ ⊄ ⊆ ⊇ ⊕ ⊗ ⊥\n\n",
        "Miscellaneous Symbols:\n",
        "☀ ☁ ☂ ☃ ★ ☆ ☉ ☎ ☐ ☑ ☒ ☕ ☘ ☠ ☢ ☣ ☮ ☯ ☸ ☹ ☺ ☻ ☼ ☽ ☾ ♠ ♡ ♢ ♣ ♤ ♥ ♦ ♧ ♨ ♩ ♪ ♫ ♬ ♭ ♮ ♯\n\n",
        "Emoji:\n",
        "😀 😁 😂 😃 😄 😅 😆 😇 😈 😉 😊 😋 😌 😍 😎 😏 😐 😑 😒 😓 😔 😕 😖 😗 😘 😙 😚 😛 😜 😝 😞 😟 😠 😡 😢 😣 😤 😥 😦 😧 😨 😩 😪 😫 😬 😭 😮 😯 😰 😱 😲 😳 😴 😵 😶 😷 😸 😹 😺 😻 😼 😽 😾 😿 🙀 🙁 🙂 🙃 🙄 🙅 🙆 🙇 🙈 🙉 🙊 🙋 🙌 🙍 🙎 🙏\n\n",
        "Bold Text:\n",
        "𝗔𝗕𝗖𝗗𝗘𝗙𝗚𝗛𝗜𝗝𝗞𝗟𝗠𝗡𝗢𝗣𝗤𝗥𝗦𝗧𝗨𝗩𝗪𝗫𝗬𝗭\n\n",
        "Italic Text:\n",
        "𝘈𝘉𝘊𝘋𝘌𝘍𝘎𝘏𝘐𝘑𝘒𝘓𝘔𝘕𝘖𝘗𝘘𝘙𝘚𝘛𝘜𝘝𝘞𝘟𝘠𝘡\n\n",
    };

    for (ligature_tests) |ligtest| {
        try writeBufferedFrame(ligtest);
    }
    try flushWriterBuffer();

    try pressEnterToContinue();
}

// MARK: DOOM Fire Palette

fn printFirePalette() !void {
    resetScreen();
    altScreenOn();

    // Print fire palette
    try writeBufferedFrame("Fire palette:\n");
    for (FIRE_COLOURS) |color| {
        try printColorBlock(color);
    }
    try flushWriterBuffer();
    try writeBufferedFrame("\n\n");

    try writeBufferedFrame("Half height pixel character:\n");
    try writeFormattedBufferedFrame("{s}", .{PIXEL_CHAR});
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    try writeBufferedFrame("Half height pixel fire on white:\n");
    for (FIRE_COLOURS) |color| {
        try printFirePixel(color, 255);
    }
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    try writeBufferedFrame("Half height pixel fire on black:\n");
    for (FIRE_COLOURS) |color| {
        try printFirePixel(color, 0);
    }
    try writeBufferedFrame("\n\n");
    try flushWriterBuffer();

    try printCentered("\x1b[38;5;208mThe following screen will display the DOOM fire algorithm - please wait for it to finish\n\n");
    print(reset_color);

    try pressEnterToContinue();
}

// MARK: DOOM Display Buffer

// TODO: Move these (doom fire struct?)
var display_buffer: []u8 = undefined;
var display_buffer_index: u32 = 0;
var display_buffer_length: u32 = 0;

fn initDisplayBuffer() !void {
    const pixel_character_size = PIXEL_CHAR.len;
    const pixel_color_size = foreground_colors[0].len + background_colors[0].len;
    const pixel_size = pixel_character_size + pixel_color_size;
    const screen_size: u64 = pixel_size * term_size.width * term_size.height;
    const overflow_size: u64 = pixel_character_size * term_size.width;
    const buffer_size: u64 = screen_size + overflow_size;

    display_buffer = try ALLOCATOR.alloc(u8, buffer_size * 2);
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
    ALLOCATOR.free(display_buffer);
}

fn printDisplayBuffer() !void {
    print(display_buffer[0..display_buffer_length]);
    resetDisplayBuffer();
}

// MARK: DOOM Fire Algorithm

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
        const random_index: u8 = random.intRangeAtMost(u8, 0, 3);
        var destination: u16 = source_index - random_index + 1;
        if (destination < FIRE_WIDTH) {
            destination = FIRE_WIDTH;
        }
        fire_buffer.*[destination - FIRE_WIDTH] = pixel - (random_index & 1);
    }
}

fn showDoomFire() !void {
    try initDisplayBuffer();
    defer freeDisplayBuffer();

    // Doom fire sizes
    const FIRE_WIDTH: u16 = term_size.width;
    const FIRE_HEIGHT: u16 = term_size.height * 2; // Double height due to half block characters
    const FIRE_SIZE: u16 = FIRE_WIDTH * FIRE_HEIGHT;
    const FIRE_LAST_ROW: u16 = (FIRE_HEIGHT - 1) * FIRE_WIDTH;

    // Doom fire colours
    const FIRE_BLACK: u8 = 0;
    const FIRE_WHITE: u8 = FIRE_COLOURS.len - 1; // Index of last colour aka white

    // Doom fire buffers
    var fire_buffer: []u8 = try ALLOCATOR.alloc(u8, FIRE_SIZE);
    defer ALLOCATOR.free(fire_buffer);

    // Initialize fire buffer (defaults to black)
    @memset(fire_buffer, FIRE_BLACK);

    // Last row of fire is white aka fire source
    var buf_index: u16 = 0;
    while (buf_index < FIRE_WIDTH) : (buf_index += 1) {
        fire_buffer[FIRE_LAST_ROW + buf_index] = FIRE_WHITE;
    }

    // Ensure terminal is in correct mode
    altScreenOn();

    // Setup initial frame
    const init_frame = std.fmt.allocPrint(ALLOCATOR, "{s}{s}{s}", .{ cursor_home, background_colors[0], foreground_colors[0] }) catch unreachable;
    defer ALLOCATOR.free(init_frame);

    var prev_pixel_foreground: u8 = 0;
    var prev_pixel_background: u8 = 0;

    var timer = try std.time.Timer.start();

    var loop_count: u16 = 0;
    var loop_limit: u16 = 666;
    if (endless_mode) {
        loop_limit = 65535;
    }
    while (loop_count < loop_limit) : (loop_count += 1) {
        doFire(FIRE_WIDTH, FIRE_HEIGHT, &fire_buffer);

        resetDisplayBuffer();
        addToDisplayBuffer(init_frame);

        // Display fire
        var frame_y: u16 = 0;
        while (frame_y < FIRE_HEIGHT) : (frame_y += 2) {
            var frame_x: u16 = 0;
            while (frame_x < FIRE_WIDTH) : (frame_x += 1) {
                const pixel_foreground: u8 = fire_buffer[frame_y * FIRE_WIDTH + frame_x];
                const pixel_background: u8 = fire_buffer[(frame_y + 1) * FIRE_WIDTH + frame_x];

                // No need to re-add the same colour if it's already set
                if (pixel_background != prev_pixel_background) {
                    addToDisplayBuffer(background_colors[FIRE_COLOURS[pixel_background]]);
                }
                if (pixel_foreground != prev_pixel_foreground) {
                    addToDisplayBuffer(foreground_colors[FIRE_COLOURS[pixel_foreground]]);
                }
                addToDisplayBuffer(PIXEL_CHAR);

                prev_pixel_foreground = pixel_foreground;
                prev_pixel_background = pixel_background;
            }
        }

        try printDisplayBuffer();
    }

    resetScreen();
    altScreenOn();
    const elapsed = timer.lap();
    const fps = @as(f64, @floatFromInt(loop_count)) / (@as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s);
    if (fps < 5 or fps > 1000) {
        try stdout.print("Results do not seem accurate - test may not have ran correctly\n", .{});
    }
    try stdout.print("\x1b[38;5;70mAverage FPS: {d:.2}{s}\n", .{ fps, reset_color });
    try stdout.print("Visual results may vary depending on terminal refresh capabilities\n\n", .{});
    try pressEnterToContinue();
}
