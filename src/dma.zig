const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;

pub fn stepDma(gb: *Gb) void {
    switch (gb.dma.mode) {
        .idle => {
            if (gb.dma.transferPending) {
                gb.dma.transferPending = false;
                gb.dma.startAddr = @as(u16, @intCast(gb.read(IoReg.DMA))) << 8;
                gb.dma.bytesTransferred = 0;
                gb.dma.mode = .transfer;
            }
        },
        .transfer => {
            if (gb.dma.bytesTransferred < 160) {
                const i = gb.dma.bytesTransferred;
                gb.write(0xfe00 + i, gb.read(gb.dma.startAddr + i));
                gb.dma.bytesTransferred += 1;
            } else {
                gb.dma.mode = .idle;
            }
        },
    }
}
