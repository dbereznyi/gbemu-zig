const std = @import("std");
const format = std.fmt.format;

pub const Cart = struct {
    const Mapper = enum {
        none,
        mbc1,
        mbc2,
        mmm01,
        mbc3,
        mbc5,
        mbc6,
        mbc7,
        pocket_camera,
        bandai_tama5,
        huc3,
        huc1,
    };
    const Mbc1Registers = struct {
        ram_enable: u1,
        current_rom_bank: u5,
        current_ram_bank: u2,
        banking_mode: u1,
    };

    rom: []const u8,
    ram: []u8,
    mapper: Cart.Mapper,
    has_ram: bool,
    has_battery: bool,
    rom_size: u32,
    ram_size: u32,

    mbc1: Mbc1Registers,

    pub fn init(rom: []const u8, alloc: std.mem.Allocator) !Cart {
        const cart_type = rom[0x0147];
        const cart_info = switch (cart_type) {
            0x00 => .{ Mapper.none, false, false },
            0x01 => .{ Mapper.mbc1, false, false },
            0x02 => .{ Mapper.mbc1, true, false },
            0x03 => .{ Mapper.mbc1, true, true },
            else => {
                std.log.err("Cartridge type ${x:0>2} is not currently supported.\n", .{cart_type});
                return error.UnsupportedCartridgeType;
            },
        };

        const rom_size: u32 = switch (rom[0x0148]) {
            0x00 => 32 * 1024,
            0x01 => 64 * 1024,
            0x02 => 128 * 1024,
            0x03 => 256 * 1024,
            0x04 => 512 * 1024,
            0x05 => 1024 * 1024,
            0x06 => 2 * 1024 * 1024,
            0x07 => 4 * 1024 * 1024,
            0x08 => 8 * 1024 * 1024,
            else => {
                std.log.err("Invalid value ${x:0>2} for ROM size.\n", .{rom[0x0148]});
                return error.BadRomSize;
            },
        };
        if (rom.len != rom_size) {
            std.log.err("Reported ROM size ({x:0>2}) does not match actual ROM size ({}).\n", .{ rom_size, rom.len });
            return error.RomSizeMismatch;
        }

        const ram_size: u32 = switch (rom[0x0149]) {
            0x00 => 0,
            0x02 => 8 * 1024,
            0x03 => 32 * 1024,
            0x04 => 128 * 1024,
            0x05 => 64 * 1024,
            else => {
                std.log.err("Invalid value ${} for RAM size.\n", .{rom[0x0149]});
                return error.BadRamSize;
            },
        };
        const ram = try alloc.alloc(u8, ram_size);

        return Cart{
            .rom = rom,
            .ram = ram,
            .mapper = cart_info[0],
            .has_ram = cart_info[1],
            .has_battery = cart_info[2],
            .mbc1 = .{
                .ram_enable = 0,
                .current_rom_bank = 1,
                .current_ram_bank = 0,
                .banking_mode = 0,
            },
            .rom_size = rom_size,
            .ram_size = ram_size,
        };
    }

    pub fn deinit(cart: *const Cart, alloc: std.mem.Allocator) void {
        alloc.free(cart.ram);
    }

    pub fn printState(cart: *const Cart, writer: anytype) !void {
        const mapper_str = switch (cart.mapper) {
            .none => "none",
            .mbc1 => "mbc1",
            .mbc2 => "mbc2",
            .mmm01 => "mmm01",
            .mbc3 => "mbc3",
            .mbc5 => "mbc5",
            .mbc6 => "mbc6",
            .mbc7 => "mbc7",
            .pocket_camera => "pocket_camera",
            .bandai_tama5 => "bandai_tama5",
            .huc3 => "huc3",
            .huc1 => "huc1",
        };
        try format(writer, "mapper={s} has_ram={d} has_battery={d} rom_size={} ram_size={}\n", .{ mapper_str, if (cart.has_ram) @as(u1, 1) else @as(u1, 0), if (cart.has_battery) @as(u1, 1) else @as(u1, 0), cart.rom_size, cart.ram_size });

        switch (cart.mapper) {
            .mbc1 => {
                try format(writer, "rom_bank={} ram_bank={} ram_enable={} banking_mode={}\n", .{ cart.mbc1.current_rom_bank, cart.mbc1.current_ram_bank, cart.mbc1.ram_enable, cart.mbc1.banking_mode });
            },
            else => {},
        }
    }

    pub fn getBank(cart: *const Cart, addr: u16) u8 {
        if (addr < 0x4000) {
            return 0;
        }
        return switch (cart.mapper) {
            .none => 1,
            .mbc1 => cart.mbc1.current_rom_bank,
            else => std.debug.panic("TODO implement getCurrentlySelectedBank read for {}\n", .{cart.mapper}),
        };
    }

    pub fn readRom(cart: *Cart, addr: u16) u8 {
        std.debug.assert(addr < 0x8000);

        switch (cart.mapper) {
            .none => {
                return cart.rom[addr];
            },
            .mbc1 => {
                if (addr < 0x4000) {
                    // TODO handle bank 0 being switched out
                    return cart.rom[addr];
                }
                const actual_addr = @as(usize, @intCast(addr)) + (0x4000 * (@as(usize, @intCast(cart.mbc1.current_rom_bank)) - 1));
                std.debug.assert(actual_addr < cart.rom.len);
                return cart.rom[actual_addr];
            },
            else => std.debug.panic("TODO implement ROM read for {}\n", .{cart.mapper}),
        }
    }

    pub fn writeRom(cart: *Cart, addr: u16, val: u8) void {
        std.debug.assert(addr < 0x8000);

        switch (cart.mapper) {
            .none => {
                std.log.warn("Attempt to write to ROM with no mapper present (${x:0>2} -> {x:0>4})\n", .{ val, addr });
            },
            .mbc1 => switch (addr) {
                // RAM Enable
                0x0000...0x1fff => {
                    if ((val & 0x0f) == 0x0a) {
                        cart.mbc1.ram_enable = 1;
                    } else {
                        cart.mbc1.ram_enable = 0;
                    }
                },
                // ROM bank select
                0x2000...0x3fff => {
                    // TODO handle more nuanced behavior (e.g. small ROMs masking fewer bits)
                    const bank: u5 = @truncate(val & 0b0001_1111);
                    cart.mbc1.current_rom_bank = if (bank == 0) 1 else bank;
                },
                // RAM bank select
                0x4000...0x5fff => {
                    if (cart.mbc1.banking_mode == 1) {
                        const bank: u2 = @truncate(val & 0b0000_0011);
                        cart.mbc1.current_ram_bank = bank;
                    }
                },
                // Banking mode select
                0x6000...0x7fff => {
                    const mode: u1 = @truncate(val & 0b0000_0001);
                    cart.mbc1.banking_mode = mode;
                },
                else => std.debug.panic("Invalid address for cartridge write: ${x:0>4}", .{addr}),
            },
            else => std.debug.panic("TODO implement ROM write for {}\n", .{cart.mapper}),
        }
    }

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
                std.debug.assert(actual_addr < cart.ram.len);
                return cart.ram[actual_addr];
            },
            else => std.debug.panic("TODO implement RAM read for {}\n", .{cart.mapper}),
        }
    }

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
                std.debug.assert(actual_addr < cart.ram.len);
                cart.ram[actual_addr] = val;
            },
            else => std.debug.panic("TODO implement RAM read for {}\n", .{cart.mapper}),
        }
    }
};
