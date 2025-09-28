const Gb = @import("../gameboy.zig").Gb;

pub fn runApu(gb: *Gb, force: bool) void {
    gb.apu.run(force);
}
