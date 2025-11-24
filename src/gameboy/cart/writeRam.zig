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
        .mbc1 => {
            if (cart.mbc1.ram_enable == 0) {
                return;
            }
            const actual_addr = (@as(usize, @intCast(addr)) - 0xa000) + (0x2000 * @as(usize, @intCast(cart.mbc1.current_ram_bank)));
            if (actual_addr < cart.ram.len) {
                cart.ram[actual_addr] = val;
            }
        },
        else => std.debug.panic("TODO implement RAM read for {}\n", .{cart.mapper}),
    }
}
