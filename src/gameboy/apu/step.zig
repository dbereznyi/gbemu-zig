const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;

pub fn stepApu(gb: *Gb) void {
    gb.apu.step(&gb.div_apu_occurred);
    gb.apu.render();
}
