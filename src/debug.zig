const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const Ppu = @import("gameboy.zig").Ppu;
const IoReg = @import("gameboy.zig").IoReg;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;
const Interrupt = @import("gameboy.zig").Interrupt;

const DEBUGGING_ENABLED = true;

const HELP_MESSAGE =
    "available commands:\n" ++
    "  general\n" ++
    "    (q)uit\n" ++
    "    (c)ontinue execution\n" ++
    "    (h)elp\n" ++
    "  breakpoints\n" ++
    "    (b)reakpoint (l)ist\n" ++
    "    (b)reakpoint (s)et <value of PC to break on (hex)>\n" ++
    "    (b)reakpoint (u)nset <breakpoint address to unset (hex)>\n" ++
    "    (b)reakpoint (c)lear all\n" ++
    "  viewing internal state/regions of memory\n" ++
    "    (v)iew (r)registers\n" ++
    "    (v)iew (s)tack\n" ++
    "    (v)iew (p)pu\n" ++
    "    (v)iew (o)am\n" ++
    "    (v)iew (j)oypad\n" ++
    "\nexample: setting a breakpoint at $1234:" ++
    "  bs 1234";

const DebugCmdTag = enum { quit, step, continue_, help, breakpointList, breakpointSet, breakpointUnset, breakpointClearAll, viewRegisters, viewStack, viewPpu, viewOam, viewJoypad };

const DebugCmd = union(DebugCmdTag) {
    quit: void,
    step: void,
    continue_: void,
    help: void,
    breakpointList: void,
    breakpointSet: u16,
    breakpointUnset: u16,
    breakpointClearAll: void,
    viewRegisters: void,
    viewStack: void,
    viewPpu: void,
    viewOam: void,
    viewJoypad: void,

    pub fn parse(buf: []u8) ?DebugCmd {
        const bufTrimmed = std.mem.trim(u8, buf, " \t\r\n");
        var p = Parser.init(bufTrimmed);

        const command = p.pop() orelse return .step;
        return switch (command) {
            'q' => .quit,
            'c' => .continue_,
            'h' => .help,
            'b' => blk: {
                const modifier = p.pop() orelse break :blk null;

                switch (modifier) {
                    's' => {
                        _ = p.until(Parser.isHexNumeral);
                        const addrStr = p.toEnd() orelse break :blk null;
                        const addr = std.fmt.parseInt(u16, addrStr, 16) catch break :blk null;
                        break :blk DebugCmd{ .breakpointSet = addr };
                    },
                    'u' => {
                        _ = p.until(Parser.isHexNumeral);
                        const addrStr = p.toEnd() orelse break :blk null;
                        const addr = std.fmt.parseInt(u16, addrStr, 16) catch break :blk null;
                        break :blk DebugCmd{ .breakpointUnset = addr };
                    },
                    'l' => break :blk .breakpointList,
                    'c' => break :blk .breakpointClearAll,
                    else => break :blk null,
                }
            },
            'v' => blk: {
                const modifier = p.pop() orelse break :blk null;

                break :blk switch (modifier) {
                    'r' => .viewRegisters,
                    's' => .viewStack,
                    'p' => .viewPpu,
                    'o' => .viewOam,
                    'j' => .viewJoypad,
                    else => null,
                };
            },
            else => null,
        };
    }

    pub fn execute(cmd: DebugCmd, gb: *Gb) !bool {
        switch (cmd) {
            .quit => {
                gb.setIsRunning(false);
                return true;
            },
            .step => {
                return true;
            },
            .continue_ => {
                gb.debug.stepModeEnabled = false;
                return true;
            },
            .help => {
                std.debug.print("{s}", .{HELP_MESSAGE});
            },
            .breakpointList => blk: {
                if (gb.debug.breakpoints.items.len == 0) {
                    std.debug.print("No active breakpoints set.\n", .{});
                    break :blk;
                }

                std.debug.print("Active breakpoints:\n", .{});
                for (gb.debug.breakpoints.items) |breakpoint| {
                    std.debug.print("  ${x:0>4}\n", .{breakpoint});
                }
            },
            .breakpointSet => |addr| {
                try gb.debug.breakpoints.append(addr);
                std.debug.print("Set breakpoint at ${x:0>4}\n", .{addr});
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
                    std.debug.print("No breakpoint set at ${x:0>4}\n", .{addr});
                    break :blk;
                };
                _ = gb.debug.breakpoints.orderedRemove(indexToRemove);
                std.debug.print("Unset breakpoint at ${x:0>4}\n", .{addr});
            },
            .breakpointClearAll => {
                gb.debug.breakpoints.clearRetainingCapacity();
                std.debug.print("All breakpoints cleared.\n", .{});
            },
            .viewRegisters => gb.printDebugState(),
            .viewStack => {
                var addr = gb.sp;
                while (addr < gb.debug.stackBase) {
                    std.debug.print("  ${x:0>4}: ${x:0>2}\n", .{ addr, gb.read(addr) });
                    addr += 1;
                }
            },
            .viewPpu => {
                gb.ppu.printState();
            },
            .viewOam => {
                var i: u16 = 0;
                while (i < gb.oam.len) : (i += 4) {
                    std.debug.print("#{d:0>2}\n", .{i / 4});
                    std.debug.print("${x:0>4}: ${x:0>2} (y = {d:0>3})\n", .{ 0xfe00 + i + 0, gb.read(0xfe00 + i + 0), gb.read(0xfe00 + i + 0) });
                    std.debug.print("${x:0>4}: ${x:0>2} (x = {d:0>3})\n", .{ 0xfe00 + i + 1, gb.read(0xfe00 + i + 1), gb.read(0xfe00 + i + 1) });
                    std.debug.print("${x:0>4}: ${x:0>2} (tileNumber = {d:0>3})\n", .{ 0xfe00 + i + 2, gb.read(0xfe00 + i + 2), gb.read(0xfe00 + i + 2) });
                    std.debug.print("${x:0>4}: ${x:0>2} (flags = {b:0>8})\n", .{ 0xfe00 + i + 3, gb.read(0xfe00 + i + 3), gb.read(0xfe00 + i + 3) });
                }
            },
            .viewJoypad => {
                gb.joypad.printState();
            },
        }

        return false;
    }
};

pub fn debugBreak(gb: *Gb) !void {
    var breakpointHit = false;
    for (gb.debug.breakpoints.items) |addr| {
        if (gb.pc == addr) {
            breakpointHit = true;
            break;
        }
    }
    if (!gb.isRunning() or !DEBUGGING_ENABLED or !(gb.debug.stepModeEnabled or breakpointHit)) {
        return;
    }

    gb.setDebugPaused(true);
    gb.debug.stepModeEnabled = true;

    gb.printDebugState();

    var instrStrBuf: [64]u8 = undefined;

    const instr = decodeInstrAt(gb.pc, gb);
    const instrStr = try instr.toStr(&instrStrBuf);
    std.debug.print("\n", .{});
    std.debug.print("==> ${x:0>4}: {s} (${x:0>2} ${x:0>2} ${x:0>2}) \n", .{
        gb.pc,
        instrStr,
        gb.read(gb.pc),
        gb.read(gb.pc + 1),
        gb.read(gb.pc + 2),
    });

    const instrNext = decodeInstrAt(gb.pc + instr.size(), gb);
    const instrNextStr = try instrNext.toStr(&instrStrBuf);
    std.debug.print("    ${x:0>4}: {s} (${x:0>2} ${x:0>2} ${x:0>2}) \n", .{
        gb.pc + instr.size(),
        instrNextStr,
        gb.read(gb.pc + instr.size()),
        gb.read(gb.pc + instr.size() + 1),
        gb.read(gb.pc + instr.size() + 2),
    });

    var resumeExecution = false;
    while (!resumeExecution) {
        std.debug.print("> ", .{});
        var inputBuf: [128]u8 = undefined;
        const inputLen = try std.io.getStdIn().read(&inputBuf);

        if (inputLen > 0) {
            const cmd = DebugCmd.parse(inputBuf[0..inputLen]) orelse {
                std.debug.print("Invalid command\n", .{});
                continue;
            };
            resumeExecution = try cmd.execute(gb);
            std.debug.print("\n", .{});
        }
    }

    gb.setDebugPaused(false);
}

const Parser = struct {
    buf: []const u8,
    i: usize,

    pub fn init(buf: []const u8) Parser {
        return Parser{
            .buf = buf,
            .i = 0,
        };
    }

    pub fn pop(self: *Parser) ?u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        const ret = self.buf[self.i];
        self.i += 1;
        return ret;
    }

    pub fn byte(self: *Parser, b: u8) ?u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        var ret: ?u8 = null;
        if (self.buf[self.i] == b) {
            ret = b;
            self.i += 1;
        }
        return ret;
    }

    pub fn peekByte(self: *Parser, b: u8) ?u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        var ret: ?u8 = null;
        if (self.buf[self.i] == b) {
            ret = b;
        }
        return ret;
    }

    pub fn untilByte(self: *Parser, b: u8) ?[]const u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        const start = self.i;
        var found = false;
        while (self.i < self.buf.len) {
            if (self.buf[self.i] == b) {
                found = true;
                break;
            }
            self.i += 1;
        }
        if (!found) {
            self.i = start;
            return null;
        }
        return self.buf[start..self.i];
    }

    pub fn until(self: *Parser, matcherFunc: *const fn (val: u8) bool) ?[]const u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        const start = self.i;
        var found = false;
        while (self.i < self.buf.len) {
            if (matcherFunc(self.buf[self.i])) {
                found = true;
                break;
            }
            self.i += 1;
        }
        if (!found) {
            self.i = start;
            return null;
        }
        return self.buf[start..self.i];
    }

    pub fn surroundedBy(self: *Parser, b: u8) ?[]const u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        if (self.buf[self.i] != b) {
            return null;
        }
        self.i += 1;
        const start = self.i;
        while (self.i < self.buf.len and self.buf[self.i] != b) {
            self.i += 1;
        }
        if (self.i == self.buf.len) {
            return self.buf[start..];
        }
        const s = self.buf[start..self.i];
        self.i += 2;
        return s;
    }

    pub fn separatedBy(self: *Parser, alloc: std.mem.Allocator, b: u8, end_byte: u8) [][]const u8 {
        var entries = std.ArrayList([]const u8).init(alloc);
        while (true) {
            const entry = self.untilByte(b) orelse break;
            entries.append(entry) catch return entries.toOwnedSlice();
        }
        const last = self.untilByte(end_byte);
        if (last != null) {
            entries.append(last.?) catch return entries.toOwnedSlice();
        }
        return entries.toOwnedSlice();
    }

    pub fn toEnd(self: *Parser) ?[]const u8 {
        if (self.i >= self.buf.len) {
            return null;
        }
        const start = self.i;
        self.i = self.buf.len;
        return self.buf[start..];
    }

    pub fn isHexNumeral(val: u8) bool {
        return switch (val) {
            '0'...'9' => true,
            'a'...'f' => true,
            'A'...'F' => true,
            else => false,
        };
    }
};
