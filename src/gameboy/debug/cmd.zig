const std = @import("std");
const Breakpoint = @import("debug.zig").Debug.Breakpoint;
const Ppu = @import("../ppu/ppu.zig").Ppu;
const Button = @import("../joypad/joypad.zig").Joypad.Button;

const DebugCmdTag = enum {
    quit,
    pause,
    trace,
    resume_,
    help,
    breakpointList,
    breakpointSet,
    breakpointUnset,
    breakpointClearAll,
    viewRegisters,
    viewMemory,
    viewStack,
    viewPpu,
    viewOam,
    viewDma,
    viewJoypad,
    viewTimer,
    viewCart,
    viewExecutionTrace,
    joypadPress,
    joypadRelease,
    ticks,
    palette,
};

pub const DebugCmd = union(DebugCmdTag) {
    pub const AddrRange = struct {
        start: u16,
        end: u16,
    };

    quit: void,
    pause: void,
    trace: void,
    resume_: void,
    help: void,
    breakpointList: void,
    breakpointSet: Breakpoint,
    breakpointUnset: u16,
    breakpointClearAll: void,
    viewRegisters: void,
    viewMemory: AddrRange,
    viewStack: void,
    viewPpu: void,
    viewOam: void,
    viewDma: void,
    viewJoypad: void,
    viewTimer: void,
    viewCart: void,
    viewExecutionTrace: void,
    joypadPress: Button,
    joypadRelease: Button,
    ticks: struct { keep: bool },
    palette: struct { new_palette: ?Ppu.Palette },

    pub fn parse(buf: []u8) ?DebugCmd {
        const bufTrimmed = std.mem.trim(u8, buf, " \t\r\n");
        var p = Parser.init(bufTrimmed);

        const command = p.pop() orelse return .trace;
        return switch (command) {
            'q' => .quit,
            'p' => blk: {
                const next = p.pop() orelse break :blk .pause;

                break :blk switch (next) {
                    'a' => {
                        _ = p.until(Parser.isWhitespace);
                        _ = p.until(Parser.isNonWhitespace);

                        const palette_name = p.toEnd() orelse break :blk .{ .palette = .{ .new_palette = null } };

                        const palette: Ppu.Palette = parse_palette: {
                            if (std.ascii.eqlIgnoreCase(palette_name, "grey")) {
                                break :parse_palette .grey;
                            } else if (std.ascii.eqlIgnoreCase(palette_name, "green")) {
                                break :parse_palette .green;
                            } else {
                                break :blk null;
                            }
                        };

                        break :blk .{ .palette = .{ .new_palette = palette } };
                    },
                    else => null,
                };
            },
            't' => blk: {
                const next = p.pop() orelse break :blk .trace;

                break :blk switch (next) {
                    'i' => {
                        _ = p.until(Parser.isNonWhitespace);

                        const arg = p.toEnd() orelse break :blk .{ .ticks = .{ .keep = false } };

                        if (arg[0] == 'k') {
                            break :blk .{ .ticks = .{ .keep = true } };
                        } else {
                            break :blk null;
                        }
                    },
                    else => null,
                };
            },
            'r' => .resume_,
            'h' => .help,
            'b' => blk: {
                const modifier = p.pop() orelse break :blk null;

                switch (modifier) {
                    's' => {
                        _ = p.until(Parser.isHexNumeral);
                        const addr_str = p.untilByte(' ') orelse (p.toEnd() orelse break :blk null);
                        const addr = std.fmt.parseInt(u16, addr_str, 16) catch break :blk null;

                        _ = p.until(Parser.isNumeral) orelse break :blk DebugCmd{ .breakpointSet = .{ .addr = addr, .bank = if (addr < 0x4000) 0 else 1 } };
                        const bank_number_str = p.toEnd() orelse break :blk null;
                        const bank_number = std.fmt.parseInt(u8, bank_number_str, 10) catch break :blk null;

                        break :blk DebugCmd{ .breakpointSet = .{ .addr = addr, .bank = bank_number } };
                    },
                    'u' => {
                        _ = p.until(Parser.isNumeral);
                        const addrStr = p.toEnd() orelse break :blk null;
                        const number = std.fmt.parseInt(u16, addrStr, 10) catch break :blk null;
                        break :blk DebugCmd{ .breakpointUnset = number };
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
                    'm' => m: {
                        _ = p.until(Parser.isHexNumeral);
                        const addr_str = p.untilByte(' ') orelse (p.toEnd() orelse break :m null);
                        const addr = std.fmt.parseInt(u16, addr_str, 16) catch break :m null;

                        _ = p.until(Parser.isNumeral) orelse break :m DebugCmd{ .viewMemory = .{ .start = addr, .end = addr +% 1 } };
                        const num_bytes_str = p.toEnd() orelse break :m null;
                        const num_bytes = std.fmt.parseInt(u8, num_bytes_str, 10) catch break :blk null;

                        break :m DebugCmd{ .viewMemory = .{ .start = addr, .end = addr +% num_bytes } };
                    },
                    's' => .viewStack,
                    'p' => .viewPpu,
                    'o' => .viewOam,
                    'd' => .viewDma,
                    'j' => .viewJoypad,
                    't' => .viewTimer,
                    'c' => .viewCart,
                    'e' => .viewExecutionTrace,
                    else => null,
                };
            },
            'j' => blk: {
                const modifier = p.pop() orelse break :blk null;

                _ = p.until(Parser.isNonWhitespace);

                const button_char = p.pop() orelse break :blk null;
                const button: Button = switch (button_char) {
                    'a' => Button.a,
                    'b' => Button.b,
                    's' => s: {
                        const c = p.pop() orelse break :blk null;
                        break :s switch (c) {
                            't' => Button.start,
                            'e' => Button.select,
                            else => break :blk null,
                        };
                    },
                    'u' => Button.up,
                    'l' => Button.left,
                    'r' => Button.right,
                    'd' => Button.down,
                    else => break :blk null,
                };

                break :blk switch (modifier) {
                    'p' => DebugCmd{ .joypadPress = button },
                    'r' => DebugCmd{ .joypadRelease = button },
                    else => null,
                };
            },
            else => null,
        };
    }
};

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

    pub fn isNumeral(val: u8) bool {
        return switch (val) {
            '0'...'9' => true,
            else => false,
        };
    }

    pub fn isHexNumeral(val: u8) bool {
        return switch (val) {
            '0'...'9' => true,
            'a'...'f' => true,
            'A'...'F' => true,
            else => false,
        };
    }

    pub fn isWhitespace(val: u8) bool {
        return std.ascii.isWhitespace(val);
    }

    pub fn isNonWhitespace(val: u8) bool {
        return !std.ascii.isWhitespace(val);
    }
};
