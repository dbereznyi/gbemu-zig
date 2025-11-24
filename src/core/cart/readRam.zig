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
        .mbc1 => {
            if (cart.mbc1.ram_enable == 0) {
                return 0xff;
            }
            const actual_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(cart.mbc1.current_ram_bank)));
            if (actual_addr < cart.ram.len) {
                return cart.ram[actual_addr];
            } else {
                return 0xff;
            }
        },
        else => std.debug.panic("TODO implement RAM read for {}\n", .{cart.mapper}),
    }
}
