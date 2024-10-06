const std = @import("std");
const writers = @import("writers.zig");
const term = @import("term.zig");
const colours = @import("colours.zig");
const text = @import("text.zig");
const doomFire = @import("doomfire.zig");

pub const ALLOCATOR = std.heap.page_allocator;
pub var endless_mode: bool = false;
pub var random: std.rand.Random = undefined;

const APP_VERSION = "0.1";
var is_monitoring_term_size: bool = false;

// MARK: Main

pub fn main() !void {
    try initialise();
    defer complete();

    try doomFire.printFirePalette();
    try doomFire.run();
}

fn complete() void {
    term.altScreenOff();
}

// MARK: Initialisation

fn initialise() !void {
    try checkArgs();

    try initSignalHandlers();
    writers.initWriters();
    term.initTermSize();
    try setupRandom();
    colours.initColors();

    try runIntroScreen();
    try colours.testTerminalColors();
    try text.testLigatures();
}

fn setupRandom() !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    random = prng.random();
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
    term.resetScreen();
    term.altScreenOff();
    std.posix.exit(0);
}

fn sigwinchHandler(_: c_int) callconv(.C) void {
    if (is_monitoring_term_size) {
        term.initTermSize();
        displayIntroScreen() catch {};
        writers.print("\x1b[38;5;226mPress Enter to continue..." ++ term.reset_color);
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
    _ = try writers.stdout.write("\x1b[?2048h");
    const sigwinch = std.posix.SIG.WINCH;
    try std.posix.sigaction(sigwinch, &std.posix.Sigaction{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);
}

// MARK: Intro Screen

fn runIntroScreen() !void {
    is_monitoring_term_size = true;
    defer is_monitoring_term_size = false;

    try displayIntroScreen();
    try term.pressEnterToContinue();
}

fn displayIntroScreen() !void {
    term.resetScreen();
    term.altScreenOn();
    try writeHeader();
    try term.outputTerminalSize();
}

pub fn writeHeader() !void {
    const headerWidth: u16 = 40;
    const halfTermWidth: u16 = term.term_size.width / 2;
    const headerOffset: u16 = halfTermWidth - headerWidth / 2;
    const spaceBuffer = try ALLOCATOR.alloc(u8, headerOffset);
    defer ALLOCATOR.free(spaceBuffer);
    @memset(spaceBuffer, ' ');

    try writers.writeBufferedFrame("\x1b[38;5;129m"); // Purple
    try writers.writeBufferedFrame("\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame("███████╗██╗██████╗  ██████╗ ███████╗██╗\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame("╚══███╔╝██║██╔══██╗██╔═══██╗██╔════╝██║\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame("  ███╔╝ ██║██║  ██║██║   ██║█████╗  ██║\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame(" ███╔╝  ██║██║  ██║██║   ██║██╔══╝  ██║\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame("███████╗██║██████╔╝╚██████╔╝██║     ██║\n");
    try writers.writeBufferedFrame(spaceBuffer);
    try writers.writeBufferedFrame("╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝\n");
    try writers.writeBufferedFrame("\n\n");
    try writers.flushWriterBuffer();

    try writers.printCentered("🔥 Zig Doom Fire - Terminal Tester & Benchmark Tool v" ++ APP_VERSION ++ "🔥\n\n");
    if (endless_mode) {
        writers.print("\x1b[38;5;196m"); // Red
        try writers.printCentered("Endless mode enabled - press Ctrl+C to exit\n\n");
    }

    // reset the color
    writers.print(term.reset_color);
}
