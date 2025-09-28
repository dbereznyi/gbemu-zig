const Gb = @import("gameboy.zig").Gb;
const runCpu = @import("cpu/run.zig").runCpu;

pub fn runGameboy(gb: *Gb) void {
    gb.vblank_just_occurred = false;

    runCpu(gb);
}
