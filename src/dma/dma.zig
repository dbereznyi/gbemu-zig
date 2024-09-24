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

    pub fn init() Dma {
        return Dma{
            .mode = .idle,
            .transferPending = false,
            .startAddr = 0x0000,
            .bytesTransferred = 0,
        };
    }

    pub fn printState(dma: *const Dma, writer: anytype) !void {
        try format(writer, "mode={s} transferPending={} startAddr={x:0>4} bytesTransferred={}\n", .{
            switch (dma.mode) {
                .idle => "idle",
                .transfer => "transfer",
            },
            dma.transferPending,
            dma.startAddr,
            dma.bytesTransferred,
        });
    }
};
