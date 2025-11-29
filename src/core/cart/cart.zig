const std = @import("std");
const MbcReg = @import("./mbc_reg.zig").MbcReg;

const Mbc1 = struct {
    ram_enable: u1,
    current_rom_bank: u5,
    current_ram_bank: u2,
    banking_mode: u1,

    pub fn init() Mbc1 {
        return .{
            .ram_enable = 0,
            .current_rom_bank = 1,
            .current_ram_bank = 0,
            .banking_mode = 0,
        };
    }

    pub fn reset(self: *Mbc1) void {
        self.ram_enable = 0;
        self.current_rom_bank = 1;
        self.current_ram_bank = 0;
        self.banking_mode = 0;
    }
};

const Rtc = struct {
    unix_timestamp: u64,
    s: u8,
    m: u8,
    h: u8,
    dl: u8,
    dh: u8,
    latched_s: u8,
    latched_m: u8,
    latched_h: u8,
    latched_dl: u8,
    latched_dh: u8,

    pub fn init() Rtc {
        return .{
            .unix_timestamp = 0,
            .s = 0,
            .m = 0,
            .h = 0,
            .dl = 0,
            .dh = 0,
            .latched_s = 0,
            .latched_m = 0,
            .latched_h = 0,
            .latched_dl = 0,
            .latched_dh = 0,
        };
    }

    pub fn latch(rtc: *Rtc) void {
        rtc.latched_s = rtc.s;
        rtc.latched_m = rtc.m;
        rtc.latched_h = rtc.h;
        rtc.latched_dl = rtc.dl;
        rtc.latched_dh = rtc.dh;
    }
};

const Mbc3 = struct {
    const LatchState = enum {
        waiting_for_00,
        waiting_for_01,
    };

    rtc: Rtc,
    ram_timer_enable: u1,
    rom_bank: u7,
    ram_bank_rtc_reg_select: u4,
    latch_state: LatchState,

    pub fn init() Mbc3 {
        return .{
            .rtc = Rtc.init(),
            .ram_timer_enable = 0,
            .rom_bank = 0,
            .ram_bank_rtc_reg_select = 0,
            .latch_state = .waiting_for_00,
        };
    }

    pub fn reset(self: *Mbc3) void {
        self.ram_timer_enable = 0;
        self.rom_bank = 0;
        self.ram_bank_rtc_reg_select = 0;
        self.latch_state = .waiting_for_00;
    }
};

const MapperTag = enum {
    none,
    mbc1,
    mbc3,
};

const Mapper = union(MapperTag) {
    none: void,
    mbc1: Mbc1,
    mbc3: Mbc3,
};

pub const Cart = struct {
    rom_title: []const u8,
    rom: []const u8,
    ram: []u8,
    mapper: Mapper,
    has_ram: bool,
    has_battery: bool,
    rom_size: u32,
    ram_size: u32,
    global_checksum: u16,

    pub fn init(rom: []const u8, save_data: ?[]const u8, alloc: std.mem.Allocator) !Cart {
        const rom_title = rom[0x0134..0x0144];
        const cart_type = rom[0x0147];
        const cart_info = switch (cart_type) {
            0x00 => .{ Mapper.none, false, false },
            // MBC1
            0x01 => .{ Mapper{ .mbc1 = Mbc1.init() }, false, false },
            0x02 => .{ Mapper{ .mbc1 = Mbc1.init() }, true, false },
            0x03 => .{ Mapper{ .mbc1 = Mbc1.init() }, true, true },
            // MBC3
            0x11 => .{ Mapper{ .mbc3 = Mbc3.init() }, false, false },
            0x12 => .{ Mapper{ .mbc3 = Mbc3.init() }, true, false },
            0x13 => .{ Mapper{ .mbc3 = Mbc3.init() }, true, true },
            else => {
                std.log.err("Cartridge type ${x:0>2} is not currently supported.\n", .{cart_type});
                return error.UnsupportedCartridgeType;
            },
        };
        const mapper = cart_info[0];
        const has_ram = cart_info[1];
        const has_battery = cart_info[2];

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
        var ram = try alloc.alloc(u8, ram_size);

        if (save_data) |data| {
            if (data.len != ram.len) {
                std.log.warn("save data size does not match RAM size\n", .{});
            }

            for (0..ram.len, 0..data.len) |ram_i, data_i| {
                ram[ram_i] = data[data_i];
            }
        }

        const global_checksum = std.mem.readInt(u16, rom[0x014e..0x0150], .big);

        return Cart{
            .rom_title = rom_title,
            .rom = rom,
            .ram = ram,
            .mapper = mapper,
            .has_ram = has_ram,
            .has_battery = has_battery,
            .rom_size = rom_size,
            .ram_size = ram_size,
            .global_checksum = global_checksum,
        };
    }

    pub fn deinit(cart: *const Cart, alloc: std.mem.Allocator) void {
        alloc.free(cart.ram);
    }

    pub fn printState(cart: *const Cart, writer: *std.Io.Writer) !void {
        try writer.print("title={s}\n", .{cart.rom_title});

        const mapper_str = switch (cart.mapper) {
            .none => "none",
            .mbc1 => "mbc1",
            .mbc3 => "mbc3",
        };
        try writer.print("mapper={s} has_ram={d} has_battery={d} rom_size={} ram_size={}\n", .{
            mapper_str,
            if (cart.has_ram) @as(u1, 1) else @as(u1, 0),
            if (cart.has_battery) @as(u1, 1) else @as(u1, 0),
            cart.rom_size,
            cart.ram_size,
        });

        switch (cart.mapper) {
            .mbc1 => |mbc1| {
                try writer.print(
                    "rom_bank={} ram_bank={} ram_enable={} banking_mode={}\n",
                    .{
                        mbc1.current_rom_bank,
                        mbc1.current_ram_bank,
                        mbc1.ram_enable,
                        mbc1.banking_mode,
                    },
                );
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
            .mbc1 => |mbc1| mbc1.current_rom_bank,
            .mbc3 => |mbc3| mbc3.rom_bank,
        };
    }

    pub fn persistRam(cart: *const Cart, path: []const u8) !void {
        if (!cart.has_battery) {
            return;
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(cart.ram);
    }

    pub fn reset(cart: *Cart) void {
        switch (cart.mapper) {
            .none => {},
            .mbc1 => cart.mapper.mbc1.reset(),
            .mbc3 => cart.mapper.mbc3.reset(),
        }
    }

    pub fn getMbcRegisters(
        cart: *Cart,
        buf: *[16]MbcReg,
    ) []MbcReg {
        switch (cart.mapper) {
            .none => {
                return buf[0..0];
            },
            .mbc1 => |mbc1| {
                buf[0] = .{ .addr = 0x0000, .val = if (mbc1.ram_enable == 1) 0x0a else 0x00 };
                buf[1] = .{ .addr = 0x2000, .val = @intCast(mbc1.current_rom_bank) };
                buf[2] = .{ .addr = 0x4000, .val = @intCast(mbc1.current_ram_bank) };
                buf[3] = .{ .addr = 0x6000, .val = @intCast(mbc1.banking_mode) };
                return buf[0..4];
            },
            else => std.debug.panic("TODO implement for {}\n", .{cart.mapper}),
        }
    }
};
