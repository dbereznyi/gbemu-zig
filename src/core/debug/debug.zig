const std = @import("std");
const format = std.fmt.format;
const Instr = @import("../cpu/root.zig").Instr;
const BoundedStack = @import("util").BoundedStack;
const DebugCmd = @import("./cmd.zig").DebugCmd;
const printAddrSpace = @import("./printAddrSpace.zig").printAddrSpace;

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
    pub const MAX_TRACE_LENGTH = 1024;

    paused: bool,
    break_next_inst: bool,
    breakpoints: std.ArrayList(Breakpoint),
    stack_base: u16,
    execution_trace: *BoundedStack(TraceLine, MAX_TRACE_LENGTH),

    last_command: ?DebugCmd,
    pending_command: ?DebugCmd,
    pending_result: std.ArrayList(u8),
    pending_result_sem: std.Thread.Semaphore,

    alloc: std.mem.Allocator,
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
            .paused = false,
            .break_next_inst = false,
            .breakpoints = breakpoints,
            .stack_base = 0xfffe,
            .execution_trace = execution_trace,

            .last_command = null,
            .pending_command = null,
            .pending_result = pending_result,
            .pending_result_sem = std.Thread.Semaphore{},

            .alloc = alloc,
            .std_out_mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(debug: *Debug) void {
        debug.breakpoints.deinit(debug.alloc);
        debug.pending_result.deinit(debug.alloc);
        debug.alloc.destroy(debug.execution_trace);
    }

    pub fn isPaused(debug: *const Debug) bool {
        return debug.paused;
    }

    pub fn setPaused(debug: *Debug, val: bool) void {
        debug.paused = val;
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

    pub fn printExecutionTrace(debug: *const Debug, writer: *std.Io.Writer, count: usize) !void {
        // Determine the starting node by traversing `count` nodes from the top of the trace
        const starting_node = blk: {
            var curr = debug.execution_trace.top();
            var curr_count: usize = 0;
            while (curr) |node| {
                if (curr_count == count) {
                    break;
                }

                curr = debug.execution_trace.down(node);
                curr_count += 1;
            }
            break :blk curr;
        };

        var curr_node = starting_node;
        while (curr_node) |node| {
            const trace_line = node.data;
            var instr_str_buf: [64]u8 = undefined;
            const instr_str = trace_line.instr.toStr(&instr_str_buf) catch "?";
            try writer.print("    ", .{});
            try printAddrSpace(writer, trace_line.pc, trace_line.bank);
            try writer.print("{x:0>4}: {s}\n", .{ trace_line.pc, instr_str });

            curr_node = debug.execution_trace.up(node);
        }
    }

    pub fn reset(debug: *Debug) void {
        debug.execution_trace.clear();
    }
};
