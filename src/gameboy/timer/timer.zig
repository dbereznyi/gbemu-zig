const std = @import("std");
const format = std.fmt.format;

pub const Timer = struct {
    cycles_elapsed: usize,

    pub fn init() Timer {
        return Timer{
            .cycles_elapsed = 0,
        };
    }

    pub fn printState(timer: *const Timer, writer: anytype) !void {
        try format(writer, "cycles_elapsed={}\n", .{timer.cycles_elapsed});
    }
};
