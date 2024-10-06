const std = @import("std");
const app = @import("main.zig");
const term = @import("term.zig");

pub var stdout: std.fs.File.Writer = undefined;

const BUFFER_SIZE: usize = 4096;
const StdOutWriter = @TypeOf(std.io.getStdOut().writer());
var buffered_writer: ?std.io.BufferedWriter(BUFFER_SIZE, StdOutWriter) = null;

pub fn initWriters() void {
    const stdout_writer = std.io.getStdOut().writer();
    buffered_writer = std.io.bufferedWriter(stdout_writer);

    stdout = std.io.getStdOut().writer();
}

// MARK: Writer

pub fn print(s: []const u8) void {
    const sz = stdout.write(s) catch unreachable;
    if (sz == 0) {
        return;
    }
    return;
}

pub fn printCentered(string: []const u8) !void {
    const padding = if (term.term_size.width > string.len) (term.term_size.width - string.len) / 2 else 0;
    try stdout.writeByteNTimes(' ', padding);
    try stdout.print("{s}\n", .{string});
}

// MARK: Buffered Writer

pub fn writeBufferedFrame(data: []const u8) !void {
    if (buffered_writer) |*bw| {
        bw.writer().print("{s}", .{data}) catch unreachable;
    } else {
        return error.BufferedWriterNotInitialised;
    }
}

pub fn writeFormattedBufferedFrame(comptime fmt: []const u8, args: anytype) !void {
    if (buffered_writer) |*bw| {
        try bw.writer().print(fmt, args);
    } else {
        return error.BufferedWriterNotInitialised;
    }
}

pub fn flushWriterBuffer() !void {
    if (buffered_writer) |*bw| {
        try bw.flush();
    } else {
        return error.BufferedWriterNotInitialised;
    }
}
