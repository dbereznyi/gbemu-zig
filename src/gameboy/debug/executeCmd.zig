const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const format = std.fmt.format;
const MAX_TRACE_LENGTH = @import("debug.zig").Debug.MAX_TRACE_LENGTH;

const HELP_MESSAGE =
    "available commands:\n" ++
    "  general\n" ++
    "    (h)elp\n" ++
    "    (q)uit\n" ++
    "    (ti)cks <optional: \"(k)eep\" to prevent counter from being reset>\n" ++
    "    (pa)lette <optional: name of palette to change to>\n" ++
    "  execution\n" ++
    "    (p)ause execution, allowing for debugging\n" ++
    "    (t)race execution, following jumps and function calls\n" ++
    "    (r)esume execution\n" ++
    "  breakpoints\n" ++
    "    (b)reakpoint (l)ist\n" ++
    "    (b)reakpoint (s)et <value of PC to break on (hex)> <optional: ROM bank>\n" ++
    "    (b)reakpoint (u)nset <breakpoint number>\n" ++
    "    (b)reakpoint (c)lear all\n" ++
    "  viewing internal state/regions of memory\n" ++
    "    (v)iew (r)egisters\n" ++
    "    (v)iew (m)emory <address (hex)> <optional: number of bytes (default 1)>\n" ++
    "    (v)iew (s)tack\n" ++
    "    (v)iew (p)pu\n" ++
    "    (v)iew (o)am\n" ++
    "    (v)iew (d)ma\n" ++
    "    (v)iew (j)oypad\n" ++
    "    (v)iew (t)imer\n" ++
    "    (v)iew (c)artridge\n" ++
    "    (v)iew (e)xecution trace\n" ++
    "  simulating joypad button presses/releases\n" ++
    "    (j)oypad (p)ress <button to press: a,b,st,se,u,l,r,d>\n" ++
    "    (j)oypad (r)elease <button to release: a,b,st,se,u,l,r,d>\n" ++
    "\n" ++
    "pressing enter will repeat the last-executed command\n" ++
    "\n" ++
    "example: setting a breakpoint at $1234:\n" ++
    "    bs 1234\n";

pub fn executeCmd(cmd: DebugCmd, gb: *Gb) !void {
    const writer = gb.debug.pendingResult.writer();

    switch (cmd) {
        .quit => {
            gb.setIsRunning(false);
            gb.debug.setPaused(false);
        },
        .pause => {
            if (!gb.debug.isPaused()) {
                try gb.printDebugTrace();
                gb.debug.setPaused(true);
            }
        },
        .trace => {
            if (gb.debug.isPaused()) {
                gb.debug.skipCurrentInstruction = true;
                gb.debug.stepModeEnabled = true;
                gb.debug.setPaused(false);
            }
        },
        .resume_ => {
            if (gb.debug.isPaused()) {
                gb.debug.skipCurrentInstruction = true;
                gb.debug.stepModeEnabled = false;
                gb.debug.setPaused(false);
            }
        },
        .help => try format(writer, "{s}", .{HELP_MESSAGE}),
        .breakpointList => blk: {
            if (gb.debug.breakpoints.items.len == 0) {
                try format(writer, "No active breakpoints set.\n", .{});
                break :blk;
            }

            try format(writer, "Active breakpoints:\n", .{});
            for (gb.debug.breakpoints.items, 0..) |breakpoint, i| {
                try format(writer, "  #{} ${x:0>4} (bank {})\n", .{ i, breakpoint.addr, breakpoint.bank });
            }
        },
        .breakpointSet => |breakpoint| {
            try gb.debug.breakpoints.append(breakpoint);
            try format(writer, "Set breakpoint at ${x:0>4} (bank {}).\n", .{ breakpoint.addr, breakpoint.bank });
        },
        .breakpointUnset => |index| blk: {
            if (index >= gb.debug.breakpoints.items.len) {
                try format(writer, "Breakpoint #{} does not exist.\n", .{index});
                break :blk;
            }
            _ = gb.debug.breakpoints.orderedRemove(index);
            try format(writer, "Unset breakpoint #{}.\n", .{index});
        },
        .breakpointClearAll => {
            gb.debug.breakpoints.clearRetainingCapacity();
            try format(writer, "All breakpoints cleared.\n", .{});
        },
        .viewRegisters => try gb.printDebugState(writer),
        .viewMemory => |args| {
            for (args.start..args.end, 0..) |addr, i| {
                if (i > 0 and i % 16 == 0) {
                    try format(writer, "\n", .{});
                }
                if (i % 16 == 0) {
                    try format(writer, "{x:0>4}: ", .{addr});
                }
                try format(writer, "{x:0>2} ", .{gb.read(@truncate(addr))});
            }
        },
        .viewStack => blk: {
            if (gb.sp >= gb.debug.stackBase) {
                break :blk;
            }
            for (gb.sp..gb.debug.stackBase, 0..) |addr, i| {
                if (i > 0 and i % 16 == 0) {
                    try format(writer, "\n", .{});
                }
                if (i % 16 == 0) {
                    try format(writer, "{x:0>4}: ", .{addr});
                }
                try format(writer, "{x:0>2} ", .{gb.read(@truncate(addr))});
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
        .viewCart => try gb.cart.printState(writer),
        .viewExecutionTrace => try gb.debug.printExecutionTrace(writer, MAX_TRACE_LENGTH),
        .joypadPress => |button| gb.joypad.pressButton(button),
        .joypadRelease => |button| gb.joypad.releaseButton(button),
        .ticks => |args| {
            try format(writer, "M-cycles: {}\n", .{gb.cycles});
            if (!args.keep) {
                gb.cycles = 0;
                try format(writer, "Cycle counter reset to 0.\n", .{});
            }
        },
        .palette => |args| {
            if (args.new_palette) |new_palette| {
                gb.ppu.palette = new_palette;
                try format(writer, "Palette set to: {s}\n", .{new_palette.toStr()});
            } else {
                try format(writer, "Current palette: {s}\n", .{gb.ppu.palette.toStr()});
            }
        },
    }
}
