const std = @import("std");
const Cart = @import("./cart.zig").Cart;

pub fn readRom(cart: *Cart, addr: u16) u8 {
    std.debug.assert(addr < 0x8000);

    switch (cart.mapper) {
        .none => {
            if (addr < cart.rom.len) {
                return cart.rom[addr];
            } else {
                std.debug.panic("Bad ROM read. Tried to read offset {} while max offset is {}\n", .{
                    addr,
                    cart.rom.len - 1,
                });
            }
        },
        .mbc1 => |mbc1| {
            if (addr < 0x4000) {
                // TODO handle bank 0 being switched out
                return cart.rom[addr];
            }
            const masked_addr: usize = addr & 0b11_1111_1111_1111;
            const rom_bank_upper: usize = if (cart.rom.len >= 1024 * 1024) @intCast(mbc1.current_ram_bank) else 0;
            const rom_bank_number: usize = rom_bank_upper << 5 | @as(usize, @intCast(mbc1.current_rom_bank));
            const physical_addr = (rom_bank_number << 14) | masked_addr;

            if (physical_addr < cart.rom.len) {
                return cart.rom[physical_addr];
            } else {
                std.debug.panic("Bad ROM read. masked_addr={b:0>16} rom_bank_number={b:0>7} physical_addr={b} ({d}) len={b}\n", .{
                    masked_addr,
                    rom_bank_number,
                    physical_addr,
                    physical_addr,
                    cart.rom.len,
                });
            }
        },
        .mbc3 => |mbc3| {
            if (addr < 0x4000) {
                return cart.rom[addr];
            }
            const masked_addr: usize = addr & 0b1_1111_1111;
            const rom_bank: usize = @intCast(mbc3.rom_bank);
            const physical_addr = (rom_bank << 9) | masked_addr;

            if (physical_addr < cart.rom.len) {
                return cart.rom[physical_addr];
            } else {
                std.debug.panic("Bad ROM read. masked_addr={b:0>16} rom_bank={b:0>7} physical_addr={b} ({d}) len={b}\n", .{
                    masked_addr,
                    rom_bank,
                    physical_addr,
                    physical_addr,
                    cart.rom.len,
                });
            }
        },
    }
}
