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
    if (gb.cycles_since_last_sync < LCDC_PERIOD / 3) {
        return;
    }

    const target_ns = gb.cycles_since_last_sync * 1_000_000_000 / CLOCK_RATE;

    const now = std.time.Instant.now() catch @panic("Could not get current time");
    const sleep_time_ns = target_ns + now.since(gb.last_sync);
    if (sleep_time_ns > 0 and sleep_time_ns < LCDC_PERIOD * 1_200_000_000 / CLOCK_RATE) {
        std.time.sleep(sleep_time_ns);
        gb.last_sync = std.time.Instant.now() catch @panic("Could not get current time");
    } else {
        if (sleep_time_ns < 0 and -sleep_time_ns < LCDC_PERIOD * 1_200_000_000 / CLOCK_RATE) {
            // Skip this sync to even out time difference
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
}
