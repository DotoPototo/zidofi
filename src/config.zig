const std = @import("std");
const Io = std.Io;

pub const app_version = "0.0.3";
pub const output_buffer_size: usize = 4096;

pub const Config = struct {
    // Benchmark
    frames: u32 = 666,
    endless: bool = false,

    // System monitoring
    sample_interval_ms: u64 = 10,

    // Terminal
    recommended_width: u16 = 160,
    recommended_height: u16 = 48,

    // FPS validation
    fps_min: f64 = 5,
    fps_max: f64 = 1000,
};

pub var global: Config = .{};

pub fn parseArgs(io: Io, args: std.process.Args) Config {
    var config = Config{};
    var iter = args.iterate();
    _ = iter.next(); // skip program name

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printStdout(io, USAGE);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printStdout(io, "zidofi " ++ app_version ++ "\n");
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--endless")) {
            config.endless = true;
        } else if (std.mem.eql(u8, arg, "--frames")) {
            const value = iter.next() orelse exitWithError(io, "Error: --frames requires a value\n");
            config.frames = std.fmt.parseInt(u32, value, 10) catch
                exitWithError(io, "Error: --frames value must be a positive integer\n");
            if (config.frames == 0) exitWithError(io, "Error: --frames must be greater than 0\n");
        } else {
            printStderr(io, "Error: unknown option '");
            printStderr(io, arg);
            printStderr(io, "'\nTry 'zidofi --help' for usage information.\n");
            std.process.exit(1);
        }
    }

    return config;
}

const USAGE =
    "ZiDoFi - Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ app_version ++ "\n" ++
    "\n" ++
    "Usage: zidofi [options]\n" ++
    "\n" ++
    "Options:\n" ++
    "  --frames N    Set benchmark length in frames (default: 666)\n" ++
    "  --endless     Run indefinitely (overrides --frames)\n" ++
    "  --help, -h    Show this help message\n" ++
    "  --version, -v Show version\n";

fn exitWithError(io: Io, msg: []const u8) noreturn {
    printStderr(io, msg);
    std.process.exit(1);
}

fn printStdout(io: Io, msg: []const u8) void {
    var buf: [output_buffer_size]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(io, &buf);
    w.interface.writeAll(msg) catch {};
    w.flush() catch {};
}

fn printStderr(io: Io, msg: []const u8) void {
    var buf: [output_buffer_size]u8 = undefined;
    var w = Io.File.stderr().writerStreaming(io, &buf);
    w.interface.writeAll(msg) catch {};
    w.flush() catch {};
}
