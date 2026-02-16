const std = @import("std");
const config = @import("config.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");
const system = @import("system.zig");
const colours = @import("colours.zig");
const text = @import("text.zig");
const doomFire = @import("doomfire.zig");
const state = @import("state.zig");

var is_monitoring_term_size: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

// MARK: Main

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    config.global = config.parseArgs(allocator) catch std.process.exit(1);

    defer complete(allocator) catch {};
    try initialise(allocator);

    if (state.shouldQuit()) return;
    try doomFire.printFirePalette();
    if (state.shouldQuit()) return;
    try doomFire.run(allocator, random);
}

fn complete(allocator: std.mem.Allocator) !void {
    try term.altScreenOff();
    system.stopSystemTrackers();
    colours.deinitColors(allocator);
}

// MARK: Initialisation

fn initialise(allocator: std.mem.Allocator) !void {
    try initSignalHandlers();
    try system.initSystemTracker();

    term.initTermSize();
    try colours.initColors(allocator);

    try runIntroScreen();
    try colours.testTerminalColors();
    try text.testLigatures();
}

// MARK: Signal Handling

fn sigintHandler(_: c_int) callconv(.c) void {
    state.requestQuit();
}

fn sigwinchHandler(_: c_int) callconv(.c) void {
    if (is_monitoring_term_size.load(.acquire)) {
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
    is_monitoring_term_size.store(true, .release);
    defer is_monitoring_term_size.store(false, .release);

    try displayIntroScreen();
    if (state.shouldQuit()) return;
    try term.pressEnterToContinue();
}

fn displayIntroScreen() !void {
    try term.resetScreen();
    try term.altScreenOn();
    try term.writeHeader();
    try term.outputTerminalSize();
    try system.printSystemUsage(true);
}
