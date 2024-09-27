const std = @import("std");
const format = std.fmt.format;

pub const Timer = struct {
    const State = enum {
        running,
        reloading_tima,
        reloaded_tima,
    };

    cycles_elapsed: usize,
    state: State,

    pub fn init() Timer {
        return Timer{
            .cycles_elapsed = 0,
            .state = .running,
        };
    }

    pub fn printState(timer: *const Timer, writer: anytype) !void {
        try format(writer, "state={s} cycles_elapsed={}\n", .{
            switch (timer.state) {
                .running => "running",
                .reloading_tima => "reloading_tima",
                .reloaded_tima => "reloaded_tima",
            },
            timer.cycles_elapsed,
        });
    }
};
