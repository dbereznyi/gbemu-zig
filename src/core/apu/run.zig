const Gb = @import("../root.zig").Gb;

pub fn runApu(gb: *Gb, force: bool) void {
    gb.apu.run(force);
}
