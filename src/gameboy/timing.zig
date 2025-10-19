const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const runTimer = @import("./timer/run.zig").runTimer;
const runJoypad = @import("./joypad/run.zig").runJoypad;
const runApu = @import("./apu/run.zig").runApu;
const runPpu = @import("./ppu/run.zig").runPpu;
const runDma = @import("./dma/run.zig").runDma;
const constants = @import("../constants.zig");

const LCDC_PERIOD: u64 = 70224;

pub fn syncTime(gb: *Gb) void {
    if (gb.cycles_since_last_sync < LCDC_PERIOD / 3) {
        return;
    }

    const target_ns: i64 = @intCast(gb.cycles_since_last_sync * (1_000_000_000 - 3_500_000) / constants.GB.CLOCK_RATE);

    const now = std.time.Instant.now() catch @panic("Could not get current time");
    const sleep_time_ns: i64 = target_ns - @as(i64, @intCast(now.since(gb.last_sync)));

    if (sleep_time_ns > 0 and sleep_time_ns < LCDC_PERIOD * 1_200_000_000 / constants.GB.CLOCK_RATE) {
        std.posix.nanosleep(0, @intCast(sleep_time_ns));

        // std.debug.print("slept {} ns ({} us), cycles_since_last_sync = {}, target_us = {}, elasped_us = {}\n", .{
        //     sleep_time_ns,
        //     @divTrunc(sleep_time_ns, 1000),
        //     gb.cycles_since_last_sync,
        //     @divTrunc(target_ns, 1000),
        //     @divTrunc(@as(i64, @intCast(now.since(gb.last_sync))), 1000),
        // });
        gb.last_sync = std.time.Instant.now() catch @panic("Could not get current time");
    } else {
        if (sleep_time_ns < 0 and -sleep_time_ns < LCDC_PERIOD * 1_200_000_000 / constants.GB.CLOCK_RATE) {
            // Skip this sync to even out time difference

            //std.debug.print("slightly slow! off by {} ns ({} us)\n", .{ -sleep_time_ns, @divTrunc(-sleep_time_ns, 1000) });
            return;
        }

        gb.last_sync = now;
    }

    gb.cycles_since_last_sync = 0;
}

pub fn advanceGameboy(gb: *Gb, cycles: usize) void {
    gb.dma.cycles = cycles;

    runTimer(gb, cycles);

    gb.cycles_since_last_sync +%= cycles;

    runJoypad(gb, cycles);
    runApu(gb, false);
    runPpu(gb, cycles);
    runDma(gb);

    gb.cycles +%= cycles;
}
