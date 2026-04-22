const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const app = @import("main.zig");
const config = @import("config.zig");
const writers = @import("writers.zig");

const is_darwin = builtin.target.os.tag.isDarwin();
const mach = if (is_darwin) @import("mach_c") else void;

// MARK: Trackers

var memory_tracker: PeakMemoryTracker = .init;
var cpu_tracker: PeakCPUTracker = .init;
var tracker_future: ?Io.Future(Io.Cancelable!void) = null;

pub fn initSystemTracker() !void {
    memory_tracker = .init;
    cpu_tracker = .init;
    tracker_future = app.io.concurrent(systemTrackerLoop, .{ app.io, &memory_tracker, &cpu_tracker }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => null,
    };
}

pub fn stopSystemTrackers() void {
    if (tracker_future) |*f| {
        _ = f.cancel(app.io) catch {};
        tracker_future = null;
    }
}

fn systemTrackerLoop(io: Io, mem_t: *PeakMemoryTracker, cpu_t: *PeakCPUTracker) Io.Cancelable!void {
    while (true) {
        if (getMemoryUsage()) |mem_info| {
            mem_t.observe(mem_info);
        } else |_| {}
        cpu_t.observe() catch {};
        try io.sleep(.fromMilliseconds(@intCast(config.global.sample_interval_ms)), .awake);
    }
}

pub fn printStartingUsage() !void {
    return printUsage("Starting");
}

pub fn printPeakUsage() !void {
    return printUsage("Peak");
}

fn printUsage(label: []const u8) !void {
    const peak_physical = memory_tracker.peak_physical.load(.acquire);
    const peak_cpu = cpu_tracker.peakUsage();

    const physical_memory_mb = @as(f64, @floatFromInt(peak_physical)) / (1024 * 1024);
    try writers.print("{s} Physical Memory Usage: {d:.2} MB\n", .{ label, physical_memory_mb });
    try writers.print("{s} CPU Usage: {d:.2} %\n\n", .{ label, peak_cpu * 100 });
    try writers.flush();
}

// MARK: Memory Tracker

const MemoryInfo = struct {
    physical_memory: usize,
};

const PeakMemoryTracker = struct {
    peak_physical: std.atomic.Value(usize),

    const init: PeakMemoryTracker = .{ .peak_physical = .init(0) };

    fn observe(self: *PeakMemoryTracker, current: MemoryInfo) void {
        _ = self.peak_physical.fetchMax(current.physical_memory, .monotonic);
    }
};

fn getMemoryUsage() !MemoryInfo {
    return if (is_darwin) getDarwinMemoryUsage() else getLinuxMemoryUsage();
}

fn getDarwinMemoryUsage() !MemoryInfo {
    var task_info: mach.mach_task_basic_info_data_t = undefined;
    var count: mach.mach_msg_type_number_t = @sizeOf(@TypeOf(task_info)) / @sizeOf(mach.natural_t);

    const kern_return = mach.task_info(
        mach.mach_task_self_,
        mach.MACH_TASK_BASIC_INFO,
        @ptrCast(&task_info),
        &count,
    );

    if (kern_return != mach.KERN_SUCCESS) {
        std.log.err("task_info failed with kern_return code {}", .{kern_return});
        return error.FailedToGetTaskInfo;
    }

    return .{ .physical_memory = task_info.resident_size };
}

fn getLinuxMemoryUsage() !MemoryInfo {
    const file = try Io.Dir.openFileAbsolute(app.io, "/proc/self/statm", .{});
    defer file.close(app.io);

    var buffer: [256]u8 = undefined;
    var file_reader = file.reader(app.io, &.{});
    const n = try file_reader.interface.readSliceShort(&buffer);
    const content = buffer[0..n];

    var iterator = std.mem.tokenizeScalar(u8, content, ' ');
    _ = iterator.next() orelse {
        std.log.err("Failed to parse /proc/self/statm: missing 'size' field", .{});
        return error.InvalidMemoryInfo;
    };
    const rss_str = iterator.next() orelse {
        std.log.err("Failed to parse /proc/self/statm: missing 'rss' field", .{});
        return error.InvalidMemoryInfo;
    };
    const rss_pages = try std.fmt.parseInt(usize, rss_str, 10);

    return .{ .physical_memory = rss_pages * std.heap.pageSize() };
}

// MARK: CPU Tracker

const CPUInfo = struct {
    user: u64,
    system: u64,
    idle: u64,
};

const PeakCPUTracker = struct {
    last_cpu_info: CPUInfo,
    peak_cpu_usage_bits: std.atomic.Value(u64),

    const init: PeakCPUTracker = .{
        .last_cpu_info = .{ .user = 0, .system = 0, .idle = 0 },
        .peak_cpu_usage_bits = .init(@bitCast(@as(f64, 0))),
    };

    fn observe(self: *PeakCPUTracker) !void {
        const current = try getCPUInfo();
        defer self.last_cpu_info = current;

        const user_diff = current.user -% self.last_cpu_info.user;
        const system_diff = current.system -% self.last_cpu_info.system;
        const idle_diff = current.idle -% self.last_cpu_info.idle;

        const total_diff = user_diff + system_diff + idle_diff;
        if (total_diff == 0) return;

        const usage: f64 = @as(f64, @floatFromInt(user_diff + system_diff)) / @as(f64, @floatFromInt(total_diff));

        var current_bits = self.peak_cpu_usage_bits.load(.acquire);
        while (true) {
            const current_peak: f64 = @bitCast(current_bits);
            if (usage <= current_peak) break;
            const new_bits: u64 = @bitCast(usage);
            current_bits = self.peak_cpu_usage_bits.cmpxchgWeak(current_bits, new_bits, .release, .acquire) orelse break;
        }
    }

    fn peakUsage(self: *const PeakCPUTracker) f64 {
        return @bitCast(self.peak_cpu_usage_bits.load(.acquire));
    }
};

fn getCPUInfo() !CPUInfo {
    return if (is_darwin) getDarwinCPUInfo() else getLinuxCPUInfo();
}

fn getDarwinCPUInfo() !CPUInfo {
    var host_cpu_load_info: mach.host_cpu_load_info = undefined;
    var count: mach.mach_msg_type_number_t = @sizeOf(@TypeOf(host_cpu_load_info)) / @sizeOf(mach.natural_t);

    const kern_return = mach.host_statistics(
        mach.mach_host_self(),
        mach.HOST_CPU_LOAD_INFO,
        @ptrCast(&host_cpu_load_info),
        &count,
    );

    if (kern_return != mach.KERN_SUCCESS) {
        std.log.err("host_statistics failed with kern_return code {}", .{kern_return});
        return error.FailedToGetCPUInfo;
    }

    return .{
        .user = host_cpu_load_info.cpu_ticks[mach.CPU_STATE_USER],
        .system = host_cpu_load_info.cpu_ticks[mach.CPU_STATE_SYSTEM],
        .idle = host_cpu_load_info.cpu_ticks[mach.CPU_STATE_IDLE],
    };
}

fn getLinuxCPUInfo() !CPUInfo {
    const file = try Io.Dir.openFileAbsolute(app.io, "/proc/stat", .{});
    defer file.close(app.io);

    var buffer: [256]u8 = undefined;
    var file_reader = file.reader(app.io, &.{});
    const n = try file_reader.interface.readSliceShort(&buffer);
    const content = buffer[0..n];

    var lines = std.mem.splitScalar(u8, content, '\n');
    const cpu_line = lines.next() orelse {
        std.log.err("Failed to parse /proc/stat: no lines found", .{});
        return error.NoCPUInfo;
    };

    var values = std.mem.tokenizeScalar(u8, cpu_line, ' ');
    _ = values.next();

    const user = try std.fmt.parseInt(u64, values.next() orelse {
        std.log.err("Failed to parse /proc/stat: missing 'user' field", .{});
        return error.InvalidCPUInfo;
    }, 10);
    const nice = try std.fmt.parseInt(u64, values.next() orelse {
        std.log.err("Failed to parse /proc/stat: missing 'nice' field", .{});
        return error.InvalidCPUInfo;
    }, 10);
    const system_val = try std.fmt.parseInt(u64, values.next() orelse {
        std.log.err("Failed to parse /proc/stat: missing 'system' field", .{});
        return error.InvalidCPUInfo;
    }, 10);
    const idle = try std.fmt.parseInt(u64, values.next() orelse {
        std.log.err("Failed to parse /proc/stat: missing 'idle' field", .{});
        return error.InvalidCPUInfo;
    }, 10);

    return .{ .user = user + nice, .system = system_val, .idle = idle };
}
