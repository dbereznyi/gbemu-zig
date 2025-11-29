const std = @import("std");
const Cart = @import("./cart.zig").Cart;

pub fn writeRom(cart: *Cart, addr: u16, val: u8) void {
    std.debug.assert(addr < 0x8000);

    switch (cart.mapper) {
        .none => {
            std.log.warn("Attempt to write to ROM with no mapper present (${x:0>2} -> {x:0>4})\n", .{ val, addr });
        },
        .mbc1 => |*mbc1| switch (addr) {
            // RAM Enable
            0x0000...0x1fff => {
                if ((val & 0x0f) == 0x0a) {
                    mbc1.ram_enable = 1;
                } else {
                    mbc1.ram_enable = 0;
                }
            },
            // ROM bank select
            0x2000...0x3fff => {
                // TODO handle more nuanced behavior (e.g. small ROMs masking fewer bits)
                const bank: u5 = @truncate(val & 0b0001_1111);
                mbc1.current_rom_bank = if (bank == 0) 1 else bank;
            },
            // RAM bank select
            0x4000...0x5fff => {
                if (mbc1.banking_mode == 1) {
                    const bank: u2 = @truncate(val & 0b0000_0011);
                    mbc1.current_ram_bank = bank;
                }
            },
            // Banking mode select
            0x6000...0x7fff => {
                const mode: u1 = @truncate(val & 0b0000_0001);
                mbc1.banking_mode = mode;
            },
            else => std.debug.panic("Invalid address for cartridge write: ${x:0>4}", .{addr}),
        },
        .mbc3 => |*mbc3| switch (addr) {
            // RAM & Timer Enable
            0x0000...0x1fff => {
                mbc3.ram_timer_enable = if ((val & 0x0f) == 0x0a) 1 else 0;
            },
            // ROM Bank Number
            0x2000...0x3fff => {
                mbc3.rom_bank = @truncate(val);
            },
            // RAM Bank Number / RTC Register Select
            0x4000...0x5fff => {
                mbc3.ram_bank_rtc_reg_select = @truncate(val);
            },
            // Latch Clock Data
            0x6000...0x7fff => {
                switch (mbc3.latch_state) {
                    .waiting_for_00 => {
                        mbc3.latch_state = .waiting_for_01;
                    },
                    .waiting_for_01 => {
                        mbc3.latch_state = .waiting_for_00;
                        mbc3.rtc.latch();
                    },
                }
            },
            else => {},
        },
    }
}
