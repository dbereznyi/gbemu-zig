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
    pub const MAX_TRACE_LENGTH = 256;

    paused: std.atomic.Value(bool),
    break_next_inst: bool,
    breakpoints: std.ArrayList(Breakpoint),
    stack_base: u16,
    execution_trace: *BoundedStack(TraceLine, MAX_TRACE_LENGTH),

    last_command: ?DebugCmd,
    pending_command: ?DebugCmd,
    pending_result: std.ArrayList(u8),
    pending_result_sem: std.Thread.Semaphore,

    std_out_mutex: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator) !Debug {
        const breakpoints = try std.ArrayList(Breakpoint).initCapacity(alloc, 128);
        const execution_trace = try alloc.create(BoundedStack(TraceLine, MAX_TRACE_LENGTH));
        execution_trace.* = BoundedStack(TraceLine, MAX_TRACE_LENGTH).init();
        // TODO Should probably use an allocator that actually frees, just in case
        // a ton of memory gets allocated from printing a debug command's result.
        // (Also may be a good idea to set an upper bound on how much text can be
        // printed?)
        const pending_result = try std.ArrayList(u8).initCapacity(alloc, 8 * 1024);

        return Debug{
            .paused = std.atomic.Value(bool).init(false),
            .break_next_inst = false,
            .breakpoints = breakpoints,
            .stack_base = 0xfffe,
            .execution_trace = execution_trace,

            .last_command = null,
            .pending_command = null,
            .pending_result = pending_result,
            .pending_result_sem = std.Thread.Semaphore{},

            .std_out_mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(debug: *const Debug, alloc: std.mem.Allocator) void {
        debug.breakpoints.deinit();
        debug.pending_result.deinit();
        alloc.destroy(debug.execution_trace);
    }

    pub fn isPaused(debug: *Debug) bool {
        return debug.paused.load(.monotonic);
    }

    pub fn setPaused(debug: *Debug, val: bool) void {
        debug.paused.store(val, .monotonic);
    }

    pub fn sendCommand(debug: *Debug, cmd: DebugCmd) void {
        debug.pending_command = cmd;
    }

    pub fn receiveCommand(debug: *Debug) ?DebugCmd {
        return debug.pending_command;
    }

    pub fn acknowledgeCommand(debug: *Debug) void {
        debug.pending_command = null;
        debug.pending_result_sem.post();
    }

    pub fn addToExecutionTrace(debug: *Debug, bank: u8, pc: u16, instr: Instr) void {
        debug.execution_trace.push(.{ .bank = bank, .pc = pc, .instr = instr });
    }

    pub fn printExecutionTrace(debug: *const Debug, writer: anytype, count: usize) !void {
        std.debug.assert(count <= MAX_TRACE_LENGTH);

        var items_buf: [MAX_TRACE_LENGTH]TraceLine = undefined;
        const items = debug.execution_trace.getItemsReversed(&items_buf);
        const start_index = items.len -| count;
        for (start_index..items.len) |i| {
            const item = items[i];
            var instr_str_buf: [64]u8 = undefined;
            const instr_str = item.instr.toStr(&instr_str_buf) catch "?";
            try format(writer, "    rom{d:_>3}::{x:0>4}: {s}\n", .{ item.bank, item.pc, instr_str });
        }
    }

    pub fn reset(debug: *Debug) void {
        debug.execution_trace.clear();
    }
};
