const std = @import("std");
const Gb = @import("../root.zig").Gb;
const IoReg = @import("../root.zig").IoReg;
const mem = @import("../memory/root.zig");

pub fn runDma(gb: *Gb) void {
    var cycles = gb.dma.cycles + gb.dma.cycles_odd;

    while (cycles >= 4) {
        cycles -= 4;

        switch (gb.dma.mode) {
            .idle => {
                if (gb.dma.transferPending) {
                    gb.dma.transferPending = false;
                    gb.dma.startAddr = @as(u16, @intCast(gb.io_regs[IoReg.DMA])) << 8;
                    gb.dma.bytesTransferred = 0;
                    gb.dma.mode = .transfer;
                }
            },
            .transfer => {
                const i = gb.dma.bytesTransferred;
                gb.oam[i] = mem.read(gb, gb.dma.startAddr + i);
                gb.dma.bytesTransferred += 1;
                if (gb.dma.bytesTransferred >= 160) {
                    gb.dma.mode = .idle;
                }
            },
        }
    }

    gb.dma.cycles_odd = cycles;
    gb.dma.cycles = 0;
}
