const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const format = std.fmt.format;

const HELP_MESSAGE =
    "available commands:\n" ++
    "  general\n" ++
    "    (h)elp\n" ++
    "    (q)uit\n" ++
    "  execution\n" ++
    "    (p)ause execution, allowing for debugging\n" ++
    "    (t)race execution, following jumps and function calls\n" ++
    "    (c)ontinue execution\n" ++
    "  breakpoints\n" ++
    "    (b)reakpoint (l)ist\n" ++
    "    (b)reakpoint (s)et <value of PC to break on (hex)>\n" ++
    "    (b)reakpoint (u)nset <breakpoint address to unset (hex)>\n" ++
    "    (b)reakpoint (c)lear all\n" ++
    "  viewing internal state/regions of memory\n" ++
    "    (v)iew (r)egisters\n" ++
    "    (v)iew (s)tack\n" ++
    "    (v)iew (p)pu\n" ++
    "    (v)iew (o)am\n" ++
    "    (v)iew (d)ma\n" ++
    "    (v)iew (j)oypad\n" ++
    "    (v)iew (t)imer\n" ++
    "\n" ++
    "pressing enter will repeat the last-executed command\n" ++
    "\n" ++
    "example: setting a breakpoint at $1234:\n" ++
    "    bs 1234\n";

pub fn executeCmd(cmd: DebugCmd, gb: *Gb) !void {
    var fbs = std.io.fixedBufferStream(gb.debug.pendingResultBuf);
    const writer = fbs.writer();

    switch (cmd) {
        .quit => {
            gb.setIsRunning(false);
            gb.debug.setPaused(false);
        },
        .trace => {
            if (gb.debug.isPaused()) {
                gb.debug.skipCurrentBreakpoint = true;
                gb.debug.setPaused(false);
            } else {
                try format(writer, "Must pause execution to use this command", .{});
            }
        },
        .continue_ => {
            if (gb.debug.isPaused()) {
                gb.debug.skipCurrentBreakpoint = true;
                gb.debug.stepModeEnabled = false;
                gb.debug.setPaused(false);
            } else {
                try format(writer, "Must pause execution to use this command", .{});
            }
        },
        .help => try format(writer, "{s}", .{HELP_MESSAGE}),
        .breakpointList => blk: {
            if (gb.debug.breakpoints.items.len == 0) {
                try format(writer, "No active breakpoints set.\n", .{});
                break :blk;
            }

            try format(writer, "Active breakpoints:\n", .{});
            for (gb.debug.breakpoints.items) |breakpoint| {
                try format(writer, "  ${x:0>4}\n", .{breakpoint});
            }
        },
        .breakpointSet => |addr| {
            try gb.debug.breakpoints.append(addr);
            try format(writer, "Set breakpoint at ${x:0>4}\n", .{addr});
        },
        .breakpointUnset => |addr| blk: {
            var indexToRemoveMaybe: ?usize = null;
            for (gb.debug.breakpoints.items, 0..) |breakpoint, i| {
                if (breakpoint == addr) {
                    indexToRemoveMaybe = i;
                    break;
                }
            }
            const indexToRemove = indexToRemoveMaybe orelse {
                try format(writer, "No breakpoint set at ${x:0>4}\n", .{addr});
                break :blk;
            };
            _ = gb.debug.breakpoints.orderedRemove(indexToRemove);
            try format(writer, "Unset breakpoint at ${x:0>4}\n", .{addr});
        },
        .breakpointClearAll => {
            gb.debug.breakpoints.clearRetainingCapacity();
            try format(writer, "All breakpoints cleared.\n", .{});
        },
        .viewRegisters => try gb.printDebugState(writer),
        .viewStack => {
            var addr = gb.sp;
            while (addr < gb.debug.stackBase) {
                try format(writer, "  ${x:0>4}: ${x:0>2}\n", .{ addr, gb.read(addr) });
                addr += 1;
            }
        },
        .viewPpu => try gb.ppu.printState(writer),
        .viewOam => {
            var i: u16 = 0;
            while (i < gb.oam.len) : (i += 4) {
                try format(writer, "#{d:0>2}\n", .{i / 4});
                try format(writer, "${x:0>4}: ${x:0>2} (y = {d:0>3})\n", .{ 0xfe00 + i + 0, gb.read(0xfe00 + i + 0), gb.read(0xfe00 + i + 0) });
                try format(writer, "${x:0>4}: ${x:0>2} (x = {d:0>3})\n", .{ 0xfe00 + i + 1, gb.read(0xfe00 + i + 1), gb.read(0xfe00 + i + 1) });
                try format(writer, "${x:0>4}: ${x:0>2} (tileNumber = {d:0>3})\n", .{ 0xfe00 + i + 2, gb.read(0xfe00 + i + 2), gb.read(0xfe00 + i + 2) });
                try format(writer, "${x:0>4}: ${x:0>2} (flags = {b:0>8})\n", .{ 0xfe00 + i + 3, gb.read(0xfe00 + i + 3), gb.read(0xfe00 + i + 3) });
            }
        },
        .viewDma => try gb.dma.printState(writer),
        .viewJoypad => try gb.joypad.printState(writer),
        .viewTimer => try gb.timer.printState(writer),
    }

    gb.debug.pendingResult = fbs.getWritten();
}
