const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;

pub fn stepApu(gb: *Gb) void {
    gb.apu.mix();
    gb.apu.step(gb.div_apu_occurred);
    gb.div_apu_occurred = false;
}
