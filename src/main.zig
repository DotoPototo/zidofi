const std = @import("std");
const writers = @import("writers.zig");
const term = @import("term.zig");
const system = @import("system.zig");
const colours = @import("colours.zig");
const text = @import("text.zig");
const doomFire = @import("doomfire.zig");

pub const ALLOCATOR = std.heap.page_allocator;
pub var endless_mode: bool = false;
pub var random: std.Random = undefined;
var quit_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn shouldQuit() bool {
    return quit_requested.load(.acquire);
}

const APP_VERSION = "0.1";
var is_monitoring_term_size: bool = false;

// MARK: Main

pub fn main() !void {
    defer complete() catch {};
    try initialise();

    if (shouldQuit()) return;
    try doomFire.printFirePalette();
    if (shouldQuit()) return;
    try doomFire.run();
}

fn complete() !void {
    try term.altScreenOff();
    system.stopSystemTrackers();
    colours.deinitColors();
}

// MARK: Initialisation

fn initialise() !void {
    try checkArgs();

    try initSignalHandlers();
    try system.initSystemTracker();

    term.initTermSize();
    try setupRandom();
    try colours.initColors();

    try runIntroScreen();
    try colours.testTerminalColors();
    try text.testLigatures();
}

fn setupRandom() !void {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    random = prng.random();
}

fn checkArgs() !void {
    var args = try std.process.argsWithAllocator(ALLOCATOR);
    defer args.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--endless")) {
            endless_mode = true;
        }
    }
}

// MARK: Signal Handling

fn sigintHandler(_: c_int) callconv(.c) void {
    quit_requested.store(true, .release);
}

fn sigwinchHandler(_: c_int) callconv(.c) void {
    if (is_monitoring_term_size) {
        term.initTermSize();
        displayIntroScreen() catch {};
        _ = writers.stdout.print("\x1b[38;5;226mPress Enter to continue...{s}", .{term.reset_color}) catch {};
        _ = writers.flushWriterBuffer() catch {};
    }
}

fn initSignalHandlers() !void {
    // CTRL+C handler
    const sigint_action = std.posix.Sigaction{
        .handler = .{ .handler = sigintHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sigint_action, null);

    // Terminal resize handler
    try writers.stdout.writeAll("\x1b[?2048h");
    const sigwinch_action = std.posix.Sigaction{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sigwinch_action, null);
}

// MARK: Intro Screen

fn runIntroScreen() !void {
    is_monitoring_term_size = true;
    defer is_monitoring_term_size = false;

    try displayIntroScreen();
    if (shouldQuit()) return;
    try term.pressEnterToContinue();
}

fn displayIntroScreen() !void {
    try term.resetScreen();
    try term.altScreenOn();
    try writeHeader();
    try term.outputTerminalSize();
    try system.printSystemUsage(true);
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
        try writers.print("\x1b[38;5;196m"); // Red
        try writers.printCentered("Endless mode enabled - press Ctrl+C to exit\n\n");
    }

    // reset the color
    try writers.print(term.reset_color);
}
