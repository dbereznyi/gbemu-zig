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
    breakpoint_list,
    breakpoint_set,
    breakpoint_unset,
    breakpoint_clear_all,
    view_registers,
    view_memory,
    view_stack,
    view_ppu,
    view_oam,
    view_dma,
    view_joypad,
    view_timer,
    view_cart,
    view_apu,
    view_execution_trace,
    joypad_press,
    joypad_release,
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
    breakpoint_list: void,
    breakpoint_set: Breakpoint,
    breakpoint_unset: u16,
    breakpoint_clear_all: void,
    view_registers: void,
    view_memory: AddrRange,
    view_stack: void,
    view_ppu: void,
    view_oam: void,
    view_dma: void,
    view_joypad: void,
    view_timer: void,
    view_cart: void,
    view_apu: void,
    view_execution_trace: void,
    joypad_press: Button,
    joypad_release: Button,
    ticks: struct { keep: bool },
    palette: struct { new_palette: ?Ppu.Palette },

    pub fn parse(buf: []u8) ?DebugCmd {
        const buf_trimmed = std.mem.trim(u8, buf, " \t\r\n");
        var p = Parser.init(buf_trimmed);

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

                        _ = p.until(Parser.isNumeral) orelse break :blk DebugCmd{ .breakpoint_set = .{ .addr = addr, .bank = if (addr < 0x4000) 0 else 1 } };
                        const bank_number_str = p.toEnd() orelse break :blk null;
                        const bank_number = std.fmt.parseInt(u8, bank_number_str, 10) catch break :blk null;

                        break :blk DebugCmd{ .breakpoint_set = .{ .addr = addr, .bank = bank_number } };
                    },
                    'u' => {
                        _ = p.until(Parser.isNumeral);
                        const addrStr = p.toEnd() orelse break :blk null;
                        const number = std.fmt.parseInt(u16, addrStr, 10) catch break :blk null;
                        break :blk DebugCmd{ .breakpoint_unset = number };
                    },
                    'l' => break :blk .breakpoint_list,
                    'c' => break :blk .breakpoint_clear_all,
                    else => break :blk null,
                }
            },
            'v' => blk: {
                const modifier = p.pop() orelse break :blk null;

                break :blk switch (modifier) {
                    'r' => .view_registers,
                    'm' => m: {
                        _ = p.until(Parser.isHexNumeral);
                        const addr_str = p.untilByte(' ') orelse (p.toEnd() orelse break :m null);
                        const addr = std.fmt.parseInt(u16, addr_str, 16) catch break :m null;

                        _ = p.until(Parser.isNumeral) orelse break :m DebugCmd{ .view_memory = .{ .start = addr, .end = addr +% 1 } };
                        const num_bytes_str = p.toEnd() orelse break :m null;
                        const num_bytes = std.fmt.parseInt(u16, num_bytes_str, 10) catch break :blk null;

                        break :m DebugCmd{ .view_memory = .{ .start = addr, .end = addr +% num_bytes } };
                    },
                    's' => .view_stack,
                    'p' => .view_ppu,
                    'o' => .view_oam,
                    'd' => .view_dma,
                    'j' => .view_joypad,
                    't' => .view_timer,
                    'c' => .view_cart,
                    'a' => .view_apu,
                    'e' => .view_execution_trace,
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
                    'p' => DebugCmd{ .joypad_press = button },
                    'r' => DebugCmd{ .joypad_release = button },
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
