const std = @import("std");
const Cart = @import("./cart.zig").Cart;

pub fn writeRam(cart: *Cart, addr: u16, val: u8) void {
    std.debug.assert(addr >= 0xa000 and addr < 0xc000);

    if (!cart.has_ram) {
        std.log.warn("Attempt to write to cartridge RAM while no RAM is present (${x:0>2} -> ${x:0>4})", .{ val, addr });
        return;
    }

    switch (cart.mapper) {
        .none => {
            std.log.warn("Attempt to write to cartridge RAM in ROM-only cartridge (${x:0>2} -> ${x:0>4})", .{ val, addr });
        },
        .mbc1 => |mbc1| {
            if (mbc1.ram_enable == 0) {
                return;
            }
            const actual_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(mbc1.current_ram_bank)));
            if (actual_addr < cart.ram.len) {
                cart.ram[actual_addr] = val;
            }
        },
        .mbc3 => |*mbc3| {
            if (mbc3.ram_timer_enable == 0) {
                return;
            }

            switch (mbc3.ram_bank_rtc_reg_select) {
                0x00...0x07 => {
                    const physical_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(mbc3.ram_bank_rtc_reg_select)));
                    if (physical_addr < cart.ram.len) {
                        cart.ram[physical_addr] = val;
                    }
                },
                0x08 => mbc3.rtc.s = val,
                0x09 => mbc3.rtc.m = val,
                0x0a => mbc3.rtc.h = val,
                0x0b => mbc3.rtc.dl = val,
                0x0c => mbc3.rtc.dh = val,
                else => {},
            }
        },
    }
}
