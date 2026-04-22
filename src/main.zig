const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const config = @import("config.zig");
const state = @import("state.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");
const system = @import("system.zig");
const colours = @import("colours.zig");
const text = @import("text.zig");
const doomFire = @import("doomfire.zig");

pub var io: Io = undefined;
pub var gpa: Allocator = undefined;
pub var arena: Allocator = undefined;
pub var random: std.Random = undefined;

var prng: std.Random.DefaultPrng = undefined;
var is_monitoring_term_size: std.atomic.Value(bool) = .init(false);

// MARK: Main

pub fn main(init: std.process.Init) !void {
    io = init.io;
    gpa = init.gpa;
    arena = init.arena.allocator();
    writers.init(io);

    config.global = config.parseArgs(io, init.minimal.args);

    defer complete();
    try initialise();

    if (state.shouldQuit()) return;
    try doomFire.printFirePalette();
    if (state.shouldQuit()) return;
    try doomFire.run();
}

fn complete() void {
    term.altScreenOff() catch {};
    system.stopSystemTrackers();
    colours.deinitColors();
}

// MARK: Initialisation

fn initialise() !void {
    try initSignalHandlers();
    try system.initSystemTracker();

    term.initTermSize();
    seedRandom();
    try colours.initColors();

    try runIntroScreen();
    try colours.testTerminalColors();
    try text.testLigatures();
}

fn seedRandom() void {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);
    random = prng.random();
}

// MARK: Signal Handling

fn sigintHandler(_: std.posix.SIG) callconv(.c) void {
    state.requestQuit();
}

fn sigwinchHandler(_: std.posix.SIG) callconv(.c) void {
    if (!is_monitoring_term_size.load(.monotonic)) return;
    term.initTermSize();
    displayIntroScreen() catch return;
    writers.print("\x1b[38;5;226mPress Enter to continue...{s}", .{term.reset_color}) catch return;
    writers.flush() catch return;
}

fn initSignalHandlers() !void {
    // CTRL+C handler
    const sigint_action: std.posix.Sigaction = .{
        .handler = .{ .handler = sigintHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.INT, &sigint_action, null);

    // Terminal resize handler
    try writers.write("\x1b[?2048h");
    try writers.flush();
    const sigwinch_action: std.posix.Sigaction = .{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.WINCH, &sigwinch_action, null);
}

// MARK: Intro Screen

fn runIntroScreen() !void {
    is_monitoring_term_size.store(true, .monotonic);
    defer is_monitoring_term_size.store(false, .monotonic);

    try displayIntroScreen();
    if (state.shouldQuit()) return;
    try term.pressEnterToContinue();
}

fn displayIntroScreen() !void {
    try term.resetScreen();
    try term.altScreenOn();
    try term.writeHeader();
    try term.outputTerminalSize();
    try system.printStartingUsage();
}
