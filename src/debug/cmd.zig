const std = @import("std");

const DebugCmdTag = enum { quit, trace, continue_, help, breakpointList, breakpointSet, breakpointUnset, breakpointClearAll, viewRegisters, viewStack, viewPpu, viewOam, viewDma, viewJoypad, viewTimer };

pub const DebugCmd = union(DebugCmdTag) {
    quit: void,
    trace: void,
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
    viewDma: void,
    viewJoypad: void,
    viewTimer: void,

    pub fn parse(buf: []u8) ?DebugCmd {
        const bufTrimmed = std.mem.trim(u8, buf, " \t\r\n");
        var p = Parser.init(bufTrimmed);

        const command = p.pop() orelse return .trace;
        return switch (command) {
            'q' => .quit,
            't' => .trace,
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
                    'd' => .viewDma,
                    'j' => .viewJoypad,
                    't' => .viewTimer,
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

    pub fn isHexNumeral(val: u8) bool {
        return switch (val) {
            '0'...'9' => true,
            'a'...'f' => true,
            'A'...'F' => true,
            else => false,
        };
    }
};
