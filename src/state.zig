const std = @import("std");

var quit_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn shouldQuit() bool {
    return quit_requested.load(.acquire);
}

pub fn requestQuit() void {
    quit_requested.store(true, .release);
}
