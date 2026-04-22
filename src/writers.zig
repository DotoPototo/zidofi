const std = @import("std");
const Io = std.Io;

const config = @import("config.zig");
const term = @import("term.zig");

var stdout_buffer: [config.output_buffer_size]u8 = undefined;
var stdout_writer: Io.File.Writer = undefined;

pub fn init(io: Io) void {
    stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
}

pub fn writer() *Io.Writer {
    return &stdout_writer.interface;
}

pub fn write(s: []const u8) !void {
    try stdout_writer.interface.writeAll(s);
}

pub fn print(comptime fmt: []const u8, args: anytype) !void {
    try stdout_writer.interface.print(fmt, args);
}

pub fn flush() !void {
    try stdout_writer.flush();
}

pub fn printCentered(string: []const u8) !void {
    const padding = if (term.term_size.width > string.len) (term.term_size.width - string.len) / 2 else 0;
    try stdout_writer.interface.splatByteAll(' ', padding);
    try stdout_writer.interface.print("{s}\n", .{string});
}
