const std = @import("std");
const writers = @import("writers.zig");

const os = std.os;
const io = std.io;
const mem = std.mem;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Value;

const is_darwin = @import("builtin").target.os.tag == .macos;

// MARK: Trackers

var memoryTracker: PeakMemoryTracker = undefined;
var cpuTracker: PeakCPUTracker = undefined;
var trackerThread: Thread = undefined;

pub fn initSystemTracker() !void {
    memoryTracker = PeakMemoryTracker.init();
    cpuTracker = PeakCPUTracker.init();
    trackerThread = try std.Thread.spawn(.{}, systemTrackerThread, .{ &memoryTracker, &cpuTracker });
}

pub fn stopSystemTrackers() void {
    memoryTracker.stop();
    cpuTracker.stop();
    trackerThread.join();
}

fn systemTrackerThread(memory_tracker: *PeakMemoryTracker, cpu_tracker: *PeakCPUTracker) !void {
    while (!memory_tracker.stop_flag.load(.seq_cst) and !cpu_tracker.stop_flag.load(.seq_cst)) {
        const memory_info = try getMemoryUsage();
        memory_tracker.updatePeaks(memory_info);
        try cpu_tracker.updatePeakCPUUsage();
        std.time.sleep(10 * std.time.ns_per_ms); // Check every 10ms
    }
}

pub fn printSystemUsage(start: bool) !void {
    const peak_physical = memoryTracker.peak_physical.load(.acquire);
    const peak_cpu = cpuTracker.getPeakCPUUsage();

    const physical_memory: f64 = @floatFromInt(peak_physical);

    var word: []const u8 = "Peak";
    if (start) {
        word = "Starting";
    }

    try writers.writeFormattedBufferedFrame("{s} Physical Memory Usage: {d:.2} MB\n", .{ word, physical_memory / (1024 * 1024) });
    try writers.writeFormattedBufferedFrame("{s} CPU Usage: {d:.2} %\n\n", .{ word, peak_cpu * 100 });
    try writers.flushWriterBuffer();
}

// MARK: Memory Tracker

pub const MemoryInfo = struct {
    physical_memory: usize,
};

const PeakMemoryTracker = struct {
    peak_physical: Atomic(usize),
    stop_flag: Atomic(bool),
    mutex: Mutex,

    fn init() PeakMemoryTracker {
        return .{
            .peak_physical = Atomic(usize).init(0),
            .stop_flag = Atomic(bool).init(false),
            .mutex = .{},
        };
    }

    fn updatePeaks(self: *PeakMemoryTracker, current: MemoryInfo) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const peak_physical = self.peak_physical.load(.acquire);
        if (current.physical_memory > peak_physical) {
            _ = self.peak_physical.store(current.physical_memory, .monotonic);
        }
    }

    fn stop(self: *PeakMemoryTracker) void {
        self.stop_flag.store(true, .seq_cst);
    }
};

fn getMemoryUsage() !MemoryInfo {
    if (is_darwin) {
        return getDarwinMemoryUsage();
    } else {
        return getLinuxMemoryUsage();
    }
}

fn getDarwinMemoryUsage() !MemoryInfo {
    const c = @cImport({
        @cInclude("mach/mach.h");
        @cInclude("mach/task_info.h");
    });

    var task_info: c.mach_task_basic_info_data_t = undefined;
    var count: c.mach_msg_type_number_t = @sizeOf(@TypeOf(task_info)) / @sizeOf(c.natural_t);

    const kern_return = c.task_info(
        c.mach_task_self_,
        c.MACH_TASK_BASIC_INFO,
        @ptrCast(&task_info),
        &count,
    );

    if (kern_return != c.KERN_SUCCESS) {
        std.debug.print("Error: task_info failed with code {}\n", .{kern_return});
        return error.FailedToGetTaskInfo;
    }

    return MemoryInfo{
        .physical_memory = task_info.resident_size,
    };
}

fn getLinuxMemoryUsage() !MemoryInfo {
    const pid = os.linux.getpid();
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "/proc/{d}/statm", .{pid});
    defer std.heap.page_allocator.free(path);

    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var buffer: [256]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    var iterator = mem.tokenize(u8, content, " ");
    const rss_pages = try std.fmt.parseInt(usize, iterator.next().?, 10);

    const page_size = std.mem.page_size;

    return MemoryInfo{
        .physical_memory = rss_pages * page_size,
    };
}

// MARK: CPU Tracker

const CPUInfo = struct {
    user: u64,
    system: u64,
    idle: u64,
};

const PeakCPUTracker = struct {
    last_cpu_info: CPUInfo,
    peak_cpu_usage: Atomic(f64),
    stop_flag: Atomic(bool),
    mutex: Mutex,

    fn init() PeakCPUTracker {
        return .{
            .last_cpu_info = CPUInfo{ .user = 0, .system = 0, .idle = 0 },
            .peak_cpu_usage = Atomic(f64).init(0),
            .stop_flag = Atomic(bool).init(false),
            .mutex = .{},
        };
    }

    fn updatePeakCPUUsage(self: *PeakCPUTracker) !void {
        const current_cpu_info = try getCPUInfo();

        self.mutex.lock();
        defer self.mutex.unlock();

        const user_diff = current_cpu_info.user - self.last_cpu_info.user;
        const system_diff = current_cpu_info.system - self.last_cpu_info.system;
        const idle_diff = current_cpu_info.idle - self.last_cpu_info.idle;

        const total_diff = user_diff + system_diff + idle_diff;
        const usage = if (total_diff > 0) @as(f64, @floatFromInt(user_diff + system_diff)) / @as(f64, @floatFromInt(total_diff)) else 0;

        const current_peak = self.peak_cpu_usage.load(.acquire);
        if (usage > current_peak) {
            _ = self.peak_cpu_usage.store(usage, .monotonic);
        }

        self.last_cpu_info = current_cpu_info;
    }

    fn getPeakCPUUsage(self: *PeakCPUTracker) f64 {
        return self.peak_cpu_usage.load(.acquire);
    }

    fn stop(self: *PeakCPUTracker) void {
        self.stop_flag.store(true, .seq_cst);
    }
};

fn getCPUInfo() !CPUInfo {
    if (is_darwin) {
        return getDarwinCPUInfo();
    } else {
        return getLinuxCPUInfo();
    }
}

fn getDarwinCPUInfo() !CPUInfo {
    const c = @cImport({
        @cInclude("mach/mach.h");
    });

    var host_cpu_load_info: c.host_cpu_load_info = undefined;
    var count: c.mach_msg_type_number_t = @sizeOf(@TypeOf(host_cpu_load_info)) / @sizeOf(c.natural_t);

    const kern_return = c.host_statistics(
        c.mach_host_self(),
        c.HOST_CPU_LOAD_INFO,
        @ptrCast(&host_cpu_load_info),
        &count,
    );

    if (kern_return != c.KERN_SUCCESS) {
        return error.FailedToGetCPUInfo;
    }

    return CPUInfo{
        .user = host_cpu_load_info.cpu_ticks[c.CPU_STATE_USER],
        .system = host_cpu_load_info.cpu_ticks[c.CPU_STATE_SYSTEM],
        .idle = host_cpu_load_info.cpu_ticks[c.CPU_STATE_IDLE],
    };
}

fn getLinuxCPUInfo() !CPUInfo {
    const file = try std.fs.openFileAbsolute("/proc/stat", .{});
    defer file.close();

    var buffer: [256]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    var lines = mem.split(u8, content, "\n");
    const cpu_line = lines.next() orelse return error.NoCPUInfo;

    var values = mem.tokenize(u8, cpu_line, " ");
    _ = values.next(); // Skip "cpu" prefix

    const user = try std.fmt.parseInt(u64, values.next() orelse return error.InvalidCPUInfo, 10);
    const nice = try std.fmt.parseInt(u64, values.next() orelse return error.InvalidCPUInfo, 10);
    const system = try std.fmt.parseInt(u64, values.next() orelse return error.InvalidCPUInfo, 10);
    const idle = try std.fmt.parseInt(u64, values.next() orelse return error.InvalidCPUInfo, 10);

    return CPUInfo{
        .user = user + nice,
        .system = system,
        .idle = idle,
    };
}
