const std = @import("std");
const format = std.fmt.format;

pub const Dma = struct {
    const Mode = enum {
        idle,
        transfer,
    };

    mode: Dma.Mode,
    transferPending: bool,
    startAddr: u16,
    bytesTransferred: u16,
    cycles: usize,
    cycles_odd: usize,

    pub fn init() Dma {
        return Dma{
            .mode = .idle,
            .transferPending = false,
            .startAddr = 0x0000,
            .bytesTransferred = 0,
            .cycles = 0,
            .cycles_odd = 0,
        };
    }

    pub fn printState(dma: *const Dma, writer: *std.Io.Writer) !void {
        try writer.print("mode={s} transferPending={} startAddr={x:0>4} bytesTransferred={}\n", .{
            switch (dma.mode) {
                .idle => "idle",
                .transfer => "transfer",
            },
            dma.transferPending,
            dma.startAddr,
            dma.bytesTransferred,
        });
    }

    pub fn reset(dma: *Dma) void {
        dma.mode = .idle;
        dma.transferPending = false;
        dma.startAddr = 0x0000;
        dma.bytesTransferred = 0;
        dma.cycles = 0;
        dma.cycles_odd = 0;
    }
};
