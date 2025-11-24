const std = @import("std");

pub const Serial = struct {
    const Self = @This();

    pub const SerialCallback = struct {
        context: *anyopaque,
        receive: *const fn (context: *anyopaque) u1,
        send: *const fn (context: *anyopaque, bit: u1) void,
        check_send: *const fn (context: *anyopaque) bool,
    };

    bits_transferred: u4,
    callback: ?SerialCallback,

    pub fn init() Self {
        return Self{
            .bits_transferred = 0,
            .callback = null,
        };
    }

    pub fn setCallback(self: *Self, callback: SerialCallback) void {
        self.callback = callback;
    }

    pub fn printState(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("bits_transferred={}\n", .{
            self.bits_transferred,
        });
    }

    pub fn reset(self: *Self) void {
        self.bits_transferred = 0;
    }
};
