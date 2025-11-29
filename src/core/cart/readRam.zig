const std = @import("std");
const Cart = @import("./cart.zig").Cart;

pub fn readRam(cart: *Cart, addr: u16) u8 {
    std.debug.assert(addr >= 0xa000 and addr < 0xc000);

    if (!cart.has_ram) {
        std.log.warn("Attempt to read from cartridge RAM while no RAM is present (${x:0>4})", .{addr});
        return 0xff;
    }

    switch (cart.mapper) {
        .none => {
            std.log.warn("Attempt to read from cartridge RAM in ROM-only cartridge (${x:0>4})", .{addr});
            return 0xff;
        },
        .mbc1 => |mbc1| {
            if (mbc1.ram_enable == 0) {
                return 0xff;
            }
            const actual_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(mbc1.current_ram_bank)));
            if (actual_addr < cart.ram.len) {
                return cart.ram[actual_addr];
            } else {
                return 0xff;
            }
        },
        .mbc3 => |mbc3| {
            if (mbc3.ram_timer_enable == 0) {
                return 0xff;
            }

            switch (mbc3.ram_bank_rtc_reg_select) {
                0x00...0x07 => {
                    const physical_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(mbc3.ram_bank_rtc_reg_select)));
                    if (physical_addr < cart.ram.len) {
                        return cart.ram[physical_addr];
                    } else {
                        return 0xff;
                    }
                },
                0x08 => return mbc3.rtc.latched_s,
                0x09 => return mbc3.rtc.latched_m,
                0x0a => return mbc3.rtc.latched_h,
                0x0b => return mbc3.rtc.latched_dl,
                0x0c => return mbc3.rtc.latched_dh,
                else => {
                    return 0xff;
                },
            }
        },
    }
}
