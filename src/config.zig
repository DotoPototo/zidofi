const std = @import("std");

pub const app_version = "0.1";
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

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    var config = Config{};
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--endless")) {
            config.endless = true;
        } else if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse {
                exitWithError("Error: --frames requires a value\n");
            };
            config.frames = std.fmt.parseInt(u32, value, 10) catch {
                exitWithError("Error: --frames value must be a positive integer\n");
            };
            if (config.frames == 0) {
                exitWithError("Error: --frames must be greater than 0\n");
            }
        } else {
            printStderr("Error: unknown option '");
            printStderr(arg);
            printStderr("'\nTry 'zidofi --help' for usage information.\n");
            std.process.exit(1);
        }
    }

    return config;
}

fn printUsage() void {
    printStdout(
        "ZiDoFi - Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ app_version ++ "\n" ++
            "\n" ++
            "Usage: zidofi [options]\n" ++
            "\n" ++
            "Options:\n" ++
            "  --frames N    Set benchmark length in frames (default: 666)\n" ++
            "  --endless     Run indefinitely (overrides --frames)\n" ++
            "  --help, -h    Show this help message\n" ++
            "  --version, -v Show version\n",
    );
}

fn printVersion() void {
    printStdout("zidofi " ++ app_version ++ "\n");
}

fn exitWithError(msg: []const u8) noreturn {
    printStderr(msg);
    std.process.exit(1);
}

fn printStdout(msg: []const u8) void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    const w: *std.Io.Writer = &writer.interface;
    w.writeAll(msg) catch {};
    w.flush() catch {};
}

fn printStderr(msg: []const u8) void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);
    const w: *std.Io.Writer = &writer.interface;
    w.writeAll(msg) catch {};
    w.flush() catch {};
}
