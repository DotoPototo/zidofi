const std = @import("std");
const config = @import("config.zig");
const writers = @import("writers.zig");

pub const TermSize = struct {
    width: u16,
    height: u16,
};
pub var term_size: TermSize = .{ .height = 0, .width = 0 };

// MARK: Terminal Escape Sequences

const esc = "\x1B";
const reset_screen = esc ++ "c";
pub const csi = esc ++ "[";
const screen_buf_on = csi ++ "?1049h";
const screen_buf_off = csi ++ "?1049l";
const cursor_hide = csi ++ "?25l";
const cursor_show = csi ++ "?25h";
pub const cursor_home = csi ++ "H";
const clear_screen = csi ++ "2J";
pub const reset_color = csi ++ "0m";

// MARK: Screen Functions

pub fn altScreenOn() !void {
    try writers.print(clear_screen ++ screen_buf_on ++ cursor_hide ++ cursor_home);
    try writers.flushWriterBuffer();
}

pub fn altScreenOff() !void {
    try writers.print(clear_screen ++ screen_buf_off ++ cursor_show ++ cursor_home);
    try writers.flushWriterBuffer();
}

pub fn resetScreen() !void {
    try writers.print(reset_screen ++ clear_screen ++ cursor_home);
    try writers.flushWriterBuffer();
}

pub fn pressEnterToContinue() !void {
    try writers.stdout.print(
        "\x1b[38;5;226mPress Enter to continue...{s}",
        .{reset_color},
    );
    try writers.flushWriterBuffer();

    var stdin_buffer: [128]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const reader: *std.Io.Reader = &stdin_reader.interface;

    while (reader.takeDelimiterExclusive('\n')) |_| {
        break;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => {},
        error.ReadFailed => return err,
    }

    try writers.stdout.print("\n", .{});
    try writers.flushWriterBuffer();
}

// MARK: Terminal Size

pub fn initTermSize() void {
    term_size = getTermSize(std.fs.File.stdout()) catch |err| {
        std.debug.print("Fatal: Unable to get terminal size: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn getTermSize(file: std.fs.File) !TermSize {
    var buf: std.posix.winsize = undefined;

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
                .width = buf.col,
                .height = buf.row,
            },
            // If the ioctl call failed, return the error
            else => |errno| {
                std.log.err("ioctl TIOCGWINSZ failed with errno {}", .{@intFromEnum(errno)});
                return error.IoctlError;
            },
        }
    };
}

pub fn outputTerminalSize() !void {
    try writers.writeFormattedBufferedFrame("Terminal size: {d}x{d}\n\n", .{ term_size.width, term_size.height });
    if (term_size.width != config.global.recommended_width or term_size.height != config.global.recommended_height) {
        try writers.writeFormattedBufferedFrame("The recommended terminal size is {d}x{d} for the DOOM fire test\n\n", .{ config.global.recommended_width, config.global.recommended_height });
    }
    try writers.flushWriterBuffer();
}

// MARK: Header

pub fn writeHeader() !void {
    const headerWidth: u16 = 40;
    const halfTermWidth: u16 = term_size.width / 2;
    const headerOffset: u16 = halfTermWidth - headerWidth / 2;

    try writers.writeBufferedFrame("\x1b[38;5;129m"); // Purple
    try writers.writeBufferedFrame("\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame("███████╗██╗██████╗  ██████╗ ███████╗██╗\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame("╚══███╔╝██║██╔══██╗██╔═══██╗██╔════╝██║\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame("  ███╔╝ ██║██║  ██║██║   ██║█████╗  ██║\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame(" ███╔╝  ██║██║  ██║██║   ██║██╔══╝  ██║\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame("███████╗██║██████╔╝╚██████╔╝██║     ██║\n");
    try writers.printSpaces(headerOffset);
    try writers.writeBufferedFrame("╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝\n");
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    try writers.printCentered("🔥 Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ config.app_version ++ "🔥\n\n");
    if (config.global.endless) {
        try writers.print("\x1b[38;5;196m"); // Red
        try writers.printCentered("Endless mode enabled - press Ctrl+C to exit\n\n");
    }

    // reset the color
    try writers.print(reset_color);
}
