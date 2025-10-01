const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const runTimer = @import("./timer/run.zig").runTimer;
const runJoypad = @import("./joypad/run.zig").runJoypad;
const runApu = @import("./apu/run.zig").runApu;
const runPpu = @import("./ppu/run.zig").runPpu;
const runDma = @import("./dma/run.zig").runDma;

const LCDC_PERIOD: u64 = 70224;
const CLOCK_RATE: u64 = 4194304;

pub fn syncTime(gb: *Gb) void {
    if (gb.debug.justUnpaused()) {
        gb.last_sync = std.time.Instant.now() catch @panic("Could not get current time");
        gb.debug.clearJustUnpaused();
    }
    if (gb.debug.isPaused()) {
        std.debug.print("debug paused!\n", .{});
        std.time.sleep(16666666);
        return;
    }
    if (gb.cycles_since_last_sync < LCDC_PERIOD / 3) {
        return;
    }

    const target_ns = gb.cycles_since_last_sync * 1_000_000_000 / CLOCK_RATE;
    std.time.sleep(target_ns);

    // const now = std.time.Instant.now() catch @panic("Could not get current time");
    // const sleep_time_ns: i64 = target_ns - @as(i64, @intCast(now.since(gb.last_sync)));

    // if (sleep_time_ns > 0 and sleep_time_ns < LCDC_PERIOD * 1_100_000_000 / CLOCK_RATE) {
    //     std.debug.print(
    //         "sleeping {} ns ({} us) to sync for {} cycles. time since last sync: {} ns ({} us)\n",
    //         .{
    //             sleep_time_ns,
    //             @divTrunc(sleep_time_ns, 1000),
    //             gb.cycles_since_last_sync,
    //             now.since(gb.last_sync),
    //             now.since(gb.last_sync) / 1000,
    //         },
    //     );
    //     std.time.sleep(@intCast(sleep_time_ns));
    //     gb.last_sync = std.time.Instant.now() catch @panic("Could not get current time");
    // } else {
    //     if (sleep_time_ns < 0 and -sleep_time_ns < LCDC_PERIOD * 1_100_000_000 / CLOCK_RATE) {
    //         // Skip this sync to even out time difference
    //         return;
    //     }

    //     std.debug.print(
    //         "sleep_time_ns {} ns ({} us), skipping sleep. cycles passed = {}\n",
    //         .{
    //             sleep_time_ns,
    //             @divTrunc(sleep_time_ns, 1000),
    //             gb.cycles_since_last_sync,
    //         },
    //     );

    //     gb.last_sync = now;
    // }

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
