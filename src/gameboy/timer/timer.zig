const std = @import("std");

pub const Timer = struct {
    const Self = @This();

    const State = enum {
        running,
        reloading_tima,
        reloaded_tima,
    };

    system_counter: u16,
    cycles_elapsed: usize,
    state: State,

    odd_cycles: usize,

    pub fn init() Self {
        return Self{
            .system_counter = 0,
            .cycles_elapsed = 0,
            .state = .running,
            .odd_cycles = 0,
        };
    }

    pub fn printState(timer: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("state={s} cycles_elapsed={} system_counter={x:0>4}\n", .{
            switch (timer.state) {
                .running => "running",
                .reloading_tima => "reloading_tima",
                .reloaded_tima => "reloaded_tima",
            },
            timer.cycles_elapsed,
            timer.system_counter,
        });
    }

    pub fn reset(self: *Self) void {
        self.system_counter = 0;
        self.cycles_elapsed = 0;
        self.state = .running;
        self.odd_cycles = 0;
    }
};
