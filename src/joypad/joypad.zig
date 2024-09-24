const std = @import("std");
const format = std.fmt.format;

pub const Joypad = struct {
    pub const Button = enum(u8) {
        a = 0b0000_0001,
        b = 0b0000_0010,
        select = 0b0000_0100,
        start = 0b0000_1000,
        right = 0b0001_0000,
        left = 0b0010_0000,
        up = 0b0100_0000,
        down = 0b1000_0000,
    };

    pub const JoypFlag = .{
        .SELECT_BUTTONS = 0b0010_0000,
        .SELECT_DPAD = 0b0001_0000,
    };

    const Mode = enum {
        waitingForLowEdge,
        lowEdge,
    };

    mode: Joypad.Mode,
    data: std.atomic.Value(u8),
    cyclesSinceLowEdgeTransition: u8,

    pub fn init() Joypad {
        return Joypad{
            .mode = .waitingForLowEdge,
            .data = std.atomic.Value(u8).init(0),
            .cyclesSinceLowEdgeTransition = 0,
        };
    }

    pub fn readButtons(joypad: *Joypad) u4 {
        return @truncate(joypad.data.load(.monotonic));
    }

    pub fn readDpad(joypad: *Joypad) u4 {
        return @truncate((joypad.data.load(.monotonic) & 0b1111_0000) >> 4);
    }

    pub fn pressButton(joypad: *Joypad, button: Button) void {
        _ = joypad.data.fetchOr(@intFromEnum(button), .monotonic);
    }

    pub fn releaseButton(joypad: *Joypad, button: Button) void {
        _ = joypad.data.fetchAnd(~@intFromEnum(button), .monotonic);
    }

    pub fn printState(joypad: *Joypad, writer: anytype) !void {
        const data = joypad.data.load(.monotonic);
        const down: u1 = if (data & @intFromEnum(Button.down) > 0) 1 else 0;
        const up: u1 = if (data & @intFromEnum(Button.up) > 0) 1 else 0;
        const left: u1 = if (data & @intFromEnum(Button.left) > 0) 1 else 0;
        const right: u1 = if (data & @intFromEnum(Button.right) > 0) 1 else 0;
        const start: u1 = if (data & @intFromEnum(Button.start) > 0) 1 else 0;
        const select: u1 = if (data & @intFromEnum(Button.select) > 0) 1 else 0;
        const b: u1 = if (data & @intFromEnum(Button.b) > 0) 1 else 0;
        const a: u1 = if (data & @intFromEnum(Button.a) > 0) 1 else 0;
        try format(writer, "U={} D={} L={} R={} ST={} SE={} B={} A={}\n", .{ down, up, left, right, start, select, b, a });
    }
};
