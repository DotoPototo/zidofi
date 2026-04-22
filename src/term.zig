const std = @import("std");
const Io = std.Io;

const app = @import("main.zig");
const config = @import("config.zig");
const writers = @import("writers.zig");

pub const TermSize = struct {
    width: u16,
    height: u16,
};
pub var term_size: TermSize = .{ .height = 0, .width = 0 };

// MARK: Terminal Escape Sequences

const esc = "\x1B";
pub const reset_screen = esc ++ "c";
pub const csi = esc ++ "[";
pub const screen_buf_on = csi ++ "?1049h";
pub const screen_buf_off = csi ++ "?1049l";
pub const cursor_hide = csi ++ "?25l";
pub const cursor_show = csi ++ "?25h";
pub const cursor_home = csi ++ "H";
const clear_screen = csi ++ "2J";
pub const reset_color = csi ++ "0m";

// MARK: Screen Functions

pub fn altScreenOn() !void {
    try writers.write(clear_screen ++ screen_buf_on ++ cursor_hide ++ cursor_home);
    try writers.flush();
}

pub fn altScreenOff() !void {
    try writers.write(clear_screen ++ screen_buf_off ++ cursor_show ++ cursor_home);
    try writers.flush();
}

pub fn resetScreen() !void {
    try writers.write(reset_screen ++ clear_screen ++ cursor_home);
    try writers.flush();
}

pub fn pressEnterToContinue() !void {
    try writers.print("\x1b[38;5;226mPress Enter to continue...{s}", .{reset_color});
    try writers.flush();

    var stdin_buffer: [128]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(app.io, &stdin_buffer);

    _ = stdin_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream, error.StreamTooLong => {},
        error.ReadFailed => return err,
    };

    try writers.write("\n");
    try writers.flush();
}

// MARK: Terminal Size

pub fn initTermSize() void {
    term_size = getTermSize() catch |err| {
        std.debug.print("Fatal: Unable to get terminal size: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn getTermSize() !TermSize {
    var buf: std.posix.winsize = undefined;
    const fd = std.posix.STDOUT_FILENO;
    return switch (std.posix.errno(std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&buf)))) {
        .SUCCESS => .{ .width = buf.col, .height = buf.row },
        else => |errno| {
            std.log.err("ioctl TIOCGWINSZ failed with errno {}", .{@intFromEnum(errno)});
            return error.IoctlError;
        },
    };
}

pub fn outputTerminalSize() !void {
    try writers.print("Terminal size: {d}x{d}\n\n", .{ term_size.width, term_size.height });
    if (term_size.width != config.global.recommended_width or term_size.height != config.global.recommended_height) {
        try writers.print(
            "The recommended terminal size is {d}x{d} for the DOOM fire test\n\n",
            .{ config.global.recommended_width, config.global.recommended_height },
        );
    }
    try writers.flush();
}

// MARK: Header

const HEADER_LINES = [_][]const u8{
    "███████╗██╗██████╗  ██████╗ ███████╗██╗",
    "╚══███╔╝██║██╔══██╗██╔═══██╗██╔════╝██║",
    "  ███╔╝ ██║██║  ██║██║   ██║█████╗  ██║",
    " ███╔╝  ██║██║  ██║██║   ██║██╔══╝  ██║",
    "███████╗██║██████╔╝╚██████╔╝██║     ██║",
    "╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝",
};
const HEADER_WIDTH: u16 = 39;

pub fn writeHeader() !void {
    const half = term_size.width / 2;
    const offset: u16 = if (half > HEADER_WIDTH / 2) half - HEADER_WIDTH / 2 else 0;
    const w = writers.writer();

    try w.writeAll("\x1b[38;5;129m\n"); // Purple
    for (HEADER_LINES) |line| {
        try w.splatByteAll(' ', offset);
        try w.writeAll(line);
        try w.writeByte('\n');
    }
    try w.writeAll("\n\n");

    try writers.printCentered("🔥 Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ config.app_version ++ "🔥\n\n");
    if (config.global.endless) {
        try w.writeAll("\x1b[38;5;196m"); // Red
        try writers.printCentered("Endless mode enabled - press Ctrl+C to exit\n\n");
    }

    // reset the color
    try w.writeAll(reset_color);
    try writers.flush();
}
