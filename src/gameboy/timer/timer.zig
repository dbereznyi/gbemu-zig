const std = @import("std");

pub const Timer = struct {
    const Self = @This();

    const State = enum {
        running,
        reloading_tima,
        reloaded_tima,
    };

    system_counter: u16,
    state: State,

    odd_cycles: usize,

    pub fn init() Self {
        return Self{
            .system_counter = 0,
            .state = .running,
            .odd_cycles = 0,
        };
    }

    pub fn printState(timer: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("state={s} system_counter={x:0>4}\n", .{
            switch (timer.state) {
                .running => "running",
                .reloading_tima => "reloading_tima",
                .reloaded_tima => "reloaded_tima",
            },
            timer.system_counter,
        });
    }

    pub fn reset(self: *Self) void {
        self.system_counter = 0;
        self.state = .running;
        self.odd_cycles = 0;
    }
};
