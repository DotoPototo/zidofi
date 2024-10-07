const std = @import("std");
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

pub fn altScreenOn() void {
    writers.print(screen_buf_on ++ clear_screen ++ cursor_hide ++ cursor_home);
}

pub fn altScreenOff() void {
    writers.print(screen_buf_off ++ clear_screen ++ cursor_show ++ cursor_home);
}

pub fn resetScreen() void {
    writers.print(reset_screen ++ clear_screen ++ cursor_home);
}

pub fn pressEnterToContinue() !void {
    writers.print("\x1b[38;5;226mPress Enter to continue..." ++ reset_color);

    const stdin = std.io.getStdIn().reader();

    stdin.skipUntilDelimiterOrEof('\n') catch unreachable;

    writers.print("\n");
}

// MARK: Terminal Size

pub fn initTermSize() void {
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

pub fn outputTerminalSize() !void {
    try writers.writeFormattedBufferedFrame("Terminal size: {d}x{d}\n\n", .{ term_size.width, term_size.height });
    if (term_size.width != 160 or term_size.height != 48) {
        try writers.writeBufferedFrame("The recommended terminal size is 160x48 for the DOOM fire test\n\n");
    }
    try writers.flushWriterBuffer();
}
