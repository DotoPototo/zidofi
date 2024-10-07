const std = @import("std");
const writers = @import("writers.zig");

const os = std.os;
const io = std.io;
const mem = std.mem;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Value;

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
    const peak_virtual = memoryTracker.peak_virtual.load(.acquire);
    const peak_resident = memoryTracker.peak_resident.load(.acquire);
    const peak_cpu = cpuTracker.getPeakCPUUsage();

    const virtual_memory: f64 = @floatFromInt(peak_virtual);
    const resident_memory: f64 = @floatFromInt(peak_resident);

    var word: []const u8 = "Peak";
    if (start) {
        word = "Starting";
    }

    try writers.writeFormattedBufferedFrame("{s} Virtual Memory Usage: {d:.2} MB\n", .{ word, virtual_memory / (1024 * 1024) });
    try writers.writeFormattedBufferedFrame("{s} Resident Memory Usage: {d:.2} MB\n", .{ word, resident_memory / (1024 * 1024) });
    try writers.writeFormattedBufferedFrame("{s} CPU Usage: {d:.2} %\n\n", .{ word, peak_cpu * 100 });
    try writers.flushWriterBuffer();
}

// MARK: Memory Tracker

const MemoryInfo = struct {
    virtual_memory: usize,
    resident_memory: usize,
};

const PeakMemoryTracker = struct {
    peak_virtual: Atomic(usize),
    peak_resident: Atomic(usize),
    stop_flag: Atomic(bool),
    mutex: Mutex,

    fn init() PeakMemoryTracker {
        return .{
            .peak_virtual = Atomic(usize).init(0),
            .peak_resident = Atomic(usize).init(0),
            .stop_flag = Atomic(bool).init(false),
            .mutex = .{},
        };
    }

    fn updatePeaks(self: *PeakMemoryTracker, current: MemoryInfo) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const peak_virtual = self.peak_virtual.load(.acquire);
        if (current.virtual_memory > peak_virtual) {
            _ = self.peak_virtual.store(current.virtual_memory, .monotonic);
        }

        const peak_resident = self.peak_resident.load(.acquire);
        if (current.resident_memory > peak_resident) {
            _ = self.peak_resident.store(current.resident_memory, .monotonic);
        }
    }

    fn stop(self: *PeakMemoryTracker) void {
        self.stop_flag.store(true, .seq_cst);
    }
};

fn getMemoryUsage() !MemoryInfo {
    const pid = os.linux.getpid();
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "/proc/{d}/statm", .{pid});
    defer std.heap.page_allocator.free(path);

    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var buffer: [256]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    var iterator = mem.tokenize(u8, content, " ");
    const vm_pages = try std.fmt.parseInt(usize, iterator.next().?, 10);
    const rss_pages = try std.fmt.parseInt(usize, iterator.next().?, 10);

    const page_size = std.mem.page_size;

    return MemoryInfo{
        .virtual_memory = vm_pages * page_size,
        .resident_memory = rss_pages * page_size,
    };
}

// MARK: CPU Tracker

const CPUInfo = struct {
    user: u64,
    nice: u64,
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
            .last_cpu_info = CPUInfo{ .user = 0, .nice = 0, .system = 0, .idle = 0 },
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
        const nice_diff = current_cpu_info.nice - self.last_cpu_info.nice;
        const system_diff = current_cpu_info.system - self.last_cpu_info.system;
        const idle_diff = current_cpu_info.idle - self.last_cpu_info.idle;

        const total_diff = user_diff + nice_diff + system_diff + idle_diff;
        const usage = if (total_diff > 0) @as(f64, @floatFromInt(user_diff + nice_diff + system_diff)) / @as(f64, @floatFromInt(total_diff)) else 0;

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
        .user = user,
        .nice = nice,
        .system = system,
        .idle = idle,
    };
}
