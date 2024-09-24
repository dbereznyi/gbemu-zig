const std = @import("std");
const format = std.fmt.format;
const Instr = @import("../cpu/instruction.zig").Instr;
const BoundedStack = @import("../../util.zig").BoundedStack;
const DebugCmd = @import("cmd.zig").DebugCmd;

pub const Debug = struct {
    const TraceLine = struct {
        bank: u8,
        pc: u16,
        instr: Instr,
    };
    pub const Breakpoint = struct {
        bank: u8,
        addr: u16,
    };
    pub const MAX_TRACE_LENGTH = 16;

    paused: std.atomic.Value(bool),
    skipCurrentInstruction: bool,
    stepModeEnabled: bool,
    breakpoints: std.ArrayList(Breakpoint),
    stackBase: u16,
    executionTrace: BoundedStack(TraceLine, MAX_TRACE_LENGTH),

    frameTimeNs: u64,

    lastCommand: ?DebugCmd,
    pendingCommand: ?DebugCmd,
    pendingResult: std.ArrayList(u8),
    pendingResultSem: std.Thread.Semaphore,

    stdOutMutex: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator) !Debug {
        const breakpoints = try std.ArrayList(Breakpoint).initCapacity(alloc, 128);
        const executionTrace = BoundedStack(TraceLine, MAX_TRACE_LENGTH).init();
        // TODO Should probably use an allocator that actually frees, just in case
        // a ton of memory gets allocated from printing a debug command's result.
        // (Also may be a good idea to set an upper bound on how much text can be
        // printed?)
        const pendingResult = try std.ArrayList(u8).initCapacity(alloc, 8 * 1024);

        return Debug{
            .paused = std.atomic.Value(bool).init(false),
            .skipCurrentInstruction = false,
            .stepModeEnabled = false,
            .breakpoints = breakpoints,
            .stackBase = 0xfffe,
            .executionTrace = executionTrace,

            .frameTimeNs = 0,

            .lastCommand = null,
            .pendingCommand = null,
            .pendingResult = pendingResult,
            .pendingResultSem = std.Thread.Semaphore{},

            .stdOutMutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(debug: *const Debug) void {
        debug.breakpoints.deinit();
        debug.pendingResult.deinit();
    }

    pub fn isPaused(debug: *Debug) bool {
        return debug.paused.load(.monotonic);
    }

    pub fn setPaused(debug: *Debug, val: bool) void {
        debug.paused.store(val, .monotonic);
    }

    pub fn sendCommand(debug: *Debug, cmd: DebugCmd) void {
        debug.pendingCommand = cmd;
    }

    pub fn receiveCommand(debug: *Debug) ?DebugCmd {
        return debug.pendingCommand;
    }

    pub fn acknowledgeCommand(debug: *Debug) void {
        debug.pendingCommand = null;
        debug.pendingResultSem.post();
    }

    pub fn addToExecutionTrace(debug: *Debug, bank: u8, pc: u16, instr: Instr) void {
        debug.executionTrace.push(.{ .bank = bank, .pc = pc, .instr = instr });
    }

    pub fn printExecutionTrace(debug: *const Debug, writer: anytype, count: usize) !void {
        std.debug.assert(count <= MAX_TRACE_LENGTH);

        var items_buf: [MAX_TRACE_LENGTH]TraceLine = undefined;
        const items = debug.executionTrace.getItemsReversed(&items_buf);
        const start_index = items.len -| count;
        for (start_index..items.len) |i| {
            const item = items[i];
            var instr_str_buf: [64]u8 = undefined;
            const instr_str = item.instr.toStr(&instr_str_buf) catch "?";
            try format(writer, "    rom{d:_>3}::{x:0>4}: {s}\n", .{ item.bank, item.pc, instr_str });
        }
    }
};
