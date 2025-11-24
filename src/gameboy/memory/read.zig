const Gb = @import("../root.zig").Gb;
const IoReg = @import("../root.zig").IoReg;
const ApuReg = @import("../apu/root.zig").ApuReg;
const cart = @import("../cart/root.zig");

pub fn read(gb: *Gb, addr: u16) u8 {
    return switch (addr) {
        // ROM
        0x0000...0x7fff => cart.readRom(&gb.cart, addr),
        // VRAM
        0x8000...0x9fff => blk: {
            if (!gb.isVramInUse() or gb.debug.isPaused()) {
                const val = gb.vram[addr - 0x8000];
                break :blk val;
            } else {
                break :blk 0xff;
            }
        },
        // External RAM
        0xa000...0xbfff => cart.readRam(&gb.cart, addr),
        // WRAM
        0xc000...0xdfff => gb.wram[addr - 0xc000],
        // Echo RAM
        0xe000...0xfdff => gb.wram[addr - 0xe000],
        // OAM
        0xfe00...0xfe9f => blk: {
            if (!gb.isLcdOn() or !gb.ppu.scanning_oam or gb.debug.isPaused()) {
                const val = gb.oam[addr - 0xfe00];
                break :blk val;
            } else {
                break :blk 0xff;
            }
        },
        // Not useable
        0xfea0...0xfeff => blk: {
            break :blk 0xff;
        },
        // I/O Registers
        0xff00...0xff7f => {
            const reg_ix = addr - 0xff00;
            return switch (reg_ix) {
                IoReg.DIV => @truncate(gb.timer.system_counter >> 8),
                IoReg.NR10 => gb.apu.readReg(ApuReg.NR10),
                IoReg.NR11 => gb.apu.readReg(ApuReg.NR11),
                IoReg.NR12 => gb.apu.readReg(ApuReg.NR12),
                IoReg.NR13 => gb.apu.readReg(ApuReg.NR13),
                IoReg.NR14 => gb.apu.readReg(ApuReg.NR14),
                IoReg.NR21 => gb.apu.readReg(ApuReg.NR21),
                IoReg.NR22 => gb.apu.readReg(ApuReg.NR22),
                IoReg.NR23 => gb.apu.readReg(ApuReg.NR23),
                IoReg.NR24 => gb.apu.readReg(ApuReg.NR24),
                IoReg.NR30 => gb.apu.readReg(ApuReg.NR30),
                IoReg.NR31 => gb.apu.readReg(ApuReg.NR31),
                IoReg.NR32 => gb.apu.readReg(ApuReg.NR32),
                IoReg.NR33 => gb.apu.readReg(ApuReg.NR33),
                IoReg.NR34 => gb.apu.readReg(ApuReg.NR34),
                IoReg.NR41 => gb.apu.readReg(ApuReg.NR41),
                IoReg.NR42 => gb.apu.readReg(ApuReg.NR42),
                IoReg.NR43 => gb.apu.readReg(ApuReg.NR43),
                IoReg.NR44 => gb.apu.readReg(ApuReg.NR44),
                IoReg.NR50 => gb.apu.readReg(ApuReg.NR50),
                IoReg.NR51 => gb.apu.readReg(ApuReg.NR51),
                IoReg.NR52 => gb.apu.readReg(ApuReg.NR52),
                0x30...0x3f => gb.apu.readWavRam(reg_ix - 0x30),
                else => gb.io_regs[reg_ix],
            };
        },
        // HRAM
        0xff80...0xfffe => gb.hram[addr - 0xff80],
        // IE
        0xffff => gb.ie,
    };
}
