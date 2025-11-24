const Bess = @import("./bess.zig").Bess;
const Gb = @import("../root.zig").Gb;
const IoReg = @import("../root.zig").IoReg;
const ApuReg = @import("../apu/root.zig").ApuReg;
const mem = @import("../memory/root.zig");

pub fn loadBess(gb: *Gb, bess: Bess) void {
    gb.reset();

    const core = bess.core;

    gb.pc = core.pc;
    gb.sp = core.sp;
    gb.a = @truncate(core.af >> 8);
    gb.zero = core.af & 0b1000_0000 != 0;
    gb.negative = core.af & 0b0100_0000 != 0;
    gb.halfCarry = core.af & 0b0010_0000 != 0;
    gb.carry = core.af & 0b0001_0000 != 0;
    gb.b = @truncate(core.bc >> 8);
    gb.c = @truncate(core.bc);
    gb.d = @truncate(core.de >> 8);
    gb.e = @truncate(core.de);
    gb.h = @truncate(core.hl >> 8);
    gb.l = @truncate(core.hl);
    gb.ime = core.ime == 1;
    gb.ie = core.ie;
    gb.halted = core.state == .halted;
    gb.stopped = core.state == .stopped;

    gb.io_regs[IoReg.JOYP] = core.mm_regs[IoReg.JOYP];
    gb.timer.system_counter = @as(u16, @intCast(core.mm_regs[IoReg.DIV])) << 8;
    gb.io_regs[IoReg.TIMA] = core.mm_regs[IoReg.TIMA];
    gb.io_regs[IoReg.TMA] = core.mm_regs[IoReg.TMA];
    gb.io_regs[IoReg.TAC] = core.mm_regs[IoReg.TAC];
    gb.io_regs[IoReg.IF] = core.mm_regs[IoReg.IF];
    gb.apu.writeReg(ApuReg.NR52, core.mm_regs[IoReg.NR52]);
    gb.apu.writeReg(ApuReg.NR51, core.mm_regs[IoReg.NR51]);
    gb.apu.writeReg(ApuReg.NR50, core.mm_regs[IoReg.NR50]);

    gb.apu.writeReg(ApuReg.NR10, core.mm_regs[IoReg.NR10]);
    gb.apu.writeReg(ApuReg.NR11, core.mm_regs[IoReg.NR11]);
    gb.apu.writeReg(ApuReg.NR12, core.mm_regs[IoReg.NR12]);
    gb.apu.writeReg(ApuReg.NR13, core.mm_regs[IoReg.NR13]);
    gb.apu.writeReg(ApuReg.NR14, core.mm_regs[IoReg.NR14]);

    gb.apu.writeReg(ApuReg.NR21, core.mm_regs[IoReg.NR21]);
    gb.apu.writeReg(ApuReg.NR22, core.mm_regs[IoReg.NR22]);
    gb.apu.writeReg(ApuReg.NR23, core.mm_regs[IoReg.NR23]);
    gb.apu.writeReg(ApuReg.NR24, core.mm_regs[IoReg.NR24]);

    gb.apu.writeReg(ApuReg.NR30, core.mm_regs[IoReg.NR30]);
    gb.apu.writeReg(ApuReg.NR31, core.mm_regs[IoReg.NR31]);
    gb.apu.writeReg(ApuReg.NR32, core.mm_regs[IoReg.NR32]);
    gb.apu.writeReg(ApuReg.NR33, core.mm_regs[IoReg.NR33]);
    gb.apu.writeReg(ApuReg.NR34, core.mm_regs[IoReg.NR34]);

    gb.apu.writeReg(ApuReg.NR41, core.mm_regs[IoReg.NR41]);
    gb.apu.writeReg(ApuReg.NR42, core.mm_regs[IoReg.NR42]);
    gb.apu.writeReg(ApuReg.NR43, core.mm_regs[IoReg.NR43]);
    gb.apu.writeReg(ApuReg.NR44, core.mm_regs[IoReg.NR44]);

    for (0x30..0x40) |i| {
        gb.apu.writeWavRam(i - 0x30, core.mm_regs[i]);
    }

    gb.io_regs[IoReg.LCDC] = core.mm_regs[IoReg.LCDC];
    gb.io_regs[IoReg.STAT] = core.mm_regs[IoReg.STAT];
    gb.io_regs[IoReg.SCY] = core.mm_regs[IoReg.SCY];
    gb.io_regs[IoReg.SCX] = core.mm_regs[IoReg.SCX];
    // Since we just start drawing a new frame anyway, we don't reload these.
    // gb.io_regs[IoReg.LY] = core.mm_regs[IoReg.LY];
    // gb.io_regs[IoReg.LYC] = core.mm_regs[IoReg.LYC];
    gb.io_regs[IoReg.DMA] = core.mm_regs[IoReg.DMA];
    gb.io_regs[IoReg.BGP] = core.mm_regs[IoReg.BGP];
    gb.io_regs[IoReg.OBP0] = core.mm_regs[IoReg.OBP0];
    gb.io_regs[IoReg.OBP1] = core.mm_regs[IoReg.OBP1];
    gb.io_regs[IoReg.WY] = core.mm_regs[IoReg.WY];
    gb.io_regs[IoReg.WX] = core.mm_regs[IoReg.WX];

    copyMemoryRegion(gb.wram, core.ram);
    copyMemoryRegion(gb.vram, core.vram);
    copyMemoryRegion(gb.cart.ram, core.mbc_ram);
    copyMemoryRegion(gb.oam, core.oam);
    copyMemoryRegion(gb.hram, core.hram);

    if (bess.mbc) |mbc| {
        for (mbc.regs) |reg| {
            mem.write(gb, reg.addr, reg.val);
        }
    }
}

// Handles copying memory regions of possibly differing sizes.
// When the destination is larger than the source, the remaining space is set to 0s.
fn copyMemoryRegion(dst: []u8, src: []const u8) void {
    const copy_end = @min(dst.len, src.len);
    @memcpy(dst[0..copy_end], src[0..copy_end]);
    if (dst.len > src.len) {
        @memset(dst[copy_end..dst.len], 0);
    }
}
