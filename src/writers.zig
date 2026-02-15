const std = @import("std");
const term = @import("term.zig");

const BUFFER_SIZE: usize = 4096;

var stdout_buffer: [BUFFER_SIZE]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
pub const stdout: *std.Io.Writer = &stdout_writer.interface;

// MARK: Writer
pub fn print(s: []const u8) !void {
    try stdout.writeAll(s);
}

pub fn printSpaces(count: usize) !void {
    var buf: [64]u8 = undefined;
    @memset(&buf, ' ');
    var left = count;
    while (left > 0) {
        const n = @min(left, buf.len);
        try stdout.writeAll(buf[0..n]);
        left -= n;
    }
}

pub fn printCentered(string: []const u8) !void {
    const padding = if (term.term_size.width > string.len) (term.term_size.width - string.len) / 2 else 0;
    try printSpaces(padding);
    try stdout.writeAll(string);
    try stdout.writeAll("\n");
}

// MARK: Buffered Writer
pub fn writeBufferedFrame(data: []const u8) !void {
    try stdout.writeAll(data);
}

pub fn writeFormattedBufferedFrame(comptime fmt: []const u8, args: anytype) !void {
    try stdout.print(fmt, args);
}

pub fn flushWriterBuffer() !void {
    try stdout.flush();
}
