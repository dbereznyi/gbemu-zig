const Gb = @import("../root.zig").Gb;
const IoReg = @import("../root.zig").IoReg;
const ApuReg = @import("../apu/root.zig").ApuReg;
const cart = @import("../cart/root.zig");

pub fn write(gb: *Gb, addr: u16, val: u8) void {
    switch (addr) {
        // ROM
        0x0000...0x7fff => cart.writeRom(&gb.cart, addr, val),
        // VRAM
        0x8000...0x9fff => {
            if (!gb.isVramInUse() or gb.debug.isPaused()) {
                gb.vram[addr - 0x8000] = val;
            }
        },
        // External RAM
        0xa000...0xbfff => cart.writeRam(&gb.cart, addr, val),
        // WRAM
        0xc000...0xdfff => {
            gb.wram[addr - 0xc000] = val;
        },
        // Echo RAM
        0xe000...0xfdff => {
            gb.wram[addr - 0xe000] = val;
        },
        // OAM
        0xfe00...0xfe9f => {
            if (!gb.isLcdOn() or !gb.ppu.scanning_oam or gb.debug.isPaused()) {
                gb.oam[addr - 0xfe00] = val;
            }
        },
        // Not useable
        0xfea0...0xfeff => {},
        // I/O Registers
        0xff00...0xff7f => {
            const reg_ix = addr - 0xff00;
            switch (reg_ix) {
                IoReg.DIV => {
                    gb.timer.system_counter = 0;
                },
                IoReg.NR10 => gb.apu.writeReg(ApuReg.NR10, val),
                IoReg.NR11 => gb.apu.writeReg(ApuReg.NR11, val),
                IoReg.NR12 => gb.apu.writeReg(ApuReg.NR12, val),
                IoReg.NR13 => gb.apu.writeReg(ApuReg.NR13, val),
                IoReg.NR14 => gb.apu.writeReg(ApuReg.NR14, val),
                IoReg.NR21 => gb.apu.writeReg(ApuReg.NR21, val),
                IoReg.NR22 => gb.apu.writeReg(ApuReg.NR22, val),
                IoReg.NR23 => gb.apu.writeReg(ApuReg.NR23, val),
                IoReg.NR24 => gb.apu.writeReg(ApuReg.NR24, val),
                IoReg.NR30 => gb.apu.writeReg(ApuReg.NR30, val),
                IoReg.NR31 => gb.apu.writeReg(ApuReg.NR31, val),
                IoReg.NR32 => gb.apu.writeReg(ApuReg.NR32, val),
                IoReg.NR33 => gb.apu.writeReg(ApuReg.NR33, val),
                IoReg.NR34 => gb.apu.writeReg(ApuReg.NR34, val),
                IoReg.NR41 => gb.apu.writeReg(ApuReg.NR41, val),
                IoReg.NR42 => gb.apu.writeReg(ApuReg.NR42, val),
                IoReg.NR43 => gb.apu.writeReg(ApuReg.NR43, val),
                IoReg.NR44 => gb.apu.writeReg(ApuReg.NR44, val),
                IoReg.NR50 => gb.apu.writeReg(ApuReg.NR50, val),
                IoReg.NR51 => gb.apu.writeReg(ApuReg.NR51, val),
                IoReg.NR52 => gb.apu.writeReg(ApuReg.NR52, val),
                0x30...0x3f => gb.apu.writeWavRam(reg_ix - 0x30, val),
                IoReg.DMA => {
                    gb.io_regs[reg_ix] = val;
                    gb.dma.transferPending = true;
                },
                else => {
                    gb.io_regs[reg_ix] = val;
                },
            }
        },
        // HRAM
        0xff80...0xfffe => {
            gb.hram[addr - 0xff80] = val;
        },
        // IE
        0xffff => {
            gb.ie = val;
        },
    }
}
