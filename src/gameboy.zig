const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const AtomicOrder = std.builtin.AtomicOrder;

pub const IoReg = .{
    .JOYP = 0xff00,
    .IF = 0xff0f,
    .LCDC = 0xff40,
    .STAT = 0xff41,
    .SCY = 0xff42,
    .SCX = 0xff43,
    .LY = 0xff44,
    .LYC = 0xff45,
    .DMA = 0xff46,
    .BGP = 0xff47,
    .OBP0 = 0xff48,
    .OBP1 = 0xff49,
    .WY = 0xff4a,
    .WX = 0xff4b,
    .IE = 0xffff,
};

pub const LcdcFlag = .{
    .ON = 0b1000_0000,
    .OFF = 0b0000_0000,

    .WIN_TILE_MAP = 0b0100_0000,

    .WIN_ENABLE = 0b0010_0000,
    .WIN_DISABLE = 0b0000_0000,

    .TILE_DATA = 0b0001_0000,
    .BG_TILE_MAP = 0b0000_1000,

    .OBJ_SIZE_LARGE = 0b0000_0100,
    .OBJ_SIZE_NORMAL = 0b0000_0000,

    .OBJ_ENABLE = 0b0000_0010,
    .OBJ_DISABLE = 0b0000_0000,

    .BG_WIN_ENABLE = 0b0000_0001,
    .BG_WIN_DISABLE = 0b0000_0000,
};

pub const ObjFlag = .{
    .PRIORITY_LOW = 0b1000_0000,
    .PRIORITY_NORMAL = 0b0000_0000,

    .Y_FLIP_ON = 0b0100_0000,
    .Y_FLIP_OFF = 0b0000_0000,

    .X_FLIP_ON = 0b0010_0000,
    .X_FLIP_OFF = 0b0000_0000,

    .PALETTE_1 = 0b0001_0000,
    .PALETTE_0 = 0b0000_0000,
};

pub const ExecState = enum {
    running,
    halted,
    haltedSkipInterrupt,
    stopped,
};

pub const Interrupt = .{
    .VBLANK = @as(u8, 0b0000_0001),
    .STAT = @as(u8, 0b0000_0010),
    .TIMER = @as(u8, 0b0000_0100),
    .SERIAL = @as(u8, 0b0000_1000),
    .JOYPAD = @as(u8, 0b0001_0000),
};

pub const StatFlag = .{
    .MODE_0 = 0b1111_1100,
    .MODE_1 = 0b1111_1101,
    .MODE_2 = 0b1111_1110,
    .MODE_3 = 0b1111_1111,

    .LYC_INCIDENT_TRUE = 0b0000_0100,
    .LYC_INCIDENT_FALSE = 0b1111_1011,

    .INT_MODE_0_ENABLE = 0b0000_1000,
    .INT_MODE_0_DISABLE = 0b1111_0111,

    .INT_MODE_1_ENABLE = 0b0001_0000,
    .INT_MODE_1_DISABLE = 0b1110_1111,

    .INT_MODE_2_ENABLE = 0b0010_0000,
    .INT_MODE_2_DISABLE = 0b1101_1111,

    .INT_LYC_INCIDENT_ENABLE = 0b0100_0000,
    .INT_LYC_INCIDENT_DISABLE = 0b1011_1111,
};

pub const Gb = struct {
    pc: u16,
    sp: u16,
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    // flags (F register)
    zero: bool,
    negative: bool,
    halfCarry: bool,
    carry: bool,

    // For instructions that evaluate a condition,
    // this is set to true if the condition evaluated to true.
    branchCond: bool,
    ime: bool,
    execState: ExecState,
    // Used to simulate the bug that occurs when HALT is called with IME not set
    // and interrupts pending.
    skipPcIncrement: bool,

    vram: []u8,
    vramMutex: std.Thread.Mutex,
    wram: []u8,
    oam: []u8,
    oamMutex: std.Thread.Mutex,
    ioRegs: []std.atomic.Value(u8),
    hram: []u8,
    ie: u8,
    rom: []const u8,
    cycles: u64,

    pub fn init(alloc: std.mem.Allocator, rom: []const u8) !Gb {
        const vram = try alloc.alloc(u8, 8 * 1024);
        for (vram, 0..) |_, i| {
            vram[i] = 0;
        }
        const wram = try alloc.alloc(u8, 8 * 1024);
        for (wram, 0..) |_, i| {
            wram[i] = 0;
        }
        const oam = try alloc.alloc(u8, 160);
        for (oam, 0..) |_, i| {
            oam[i] = 0;
        }
        var ioRegs = try alloc.alloc(std.atomic.Value(u8), 128);
        for (ioRegs, 0..) |_, i| {
            ioRegs[i] = std.atomic.Value(u8).init(0);
        }
        const hram = try alloc.alloc(u8, 128);
        for (hram, 0..) |_, i| {
            hram[i] = 0;
        }

        return Gb{
            .pc = 0x0100,
            .sp = 0,
            .a = 0,
            .b = 0,
            .c = 0,
            .d = 0,
            .e = 0,
            .h = 0,
            .l = 0,
            .zero = false,
            .negative = false,
            .halfCarry = false,
            .carry = false,
            .branchCond = false,
            .ime = false,
            .execState = ExecState.running,
            .skipPcIncrement = false,
            .vram = vram,
            .vramMutex = std.Thread.Mutex{},
            .wram = wram,
            .oam = oam,
            .oamMutex = std.Thread.Mutex{},
            .ioRegs = ioRegs,
            .hram = hram,
            .ie = 0,
            .rom = rom,
            .cycles = 0,
        };
    }

    pub fn deinit(gb: *const Gb, alloc: std.mem.Allocator) void {
        alloc.free(gb.vram);
        alloc.free(gb.wram);
        alloc.free(gb.oam);
        alloc.free(gb.ioRegs);
        alloc.free(gb.hram);
    }

    pub fn readFlags(gb: *const Gb) u8 {
        const z: u8 = if (gb.zero) 0b1000_0000 else 0;
        const n: u8 = if (gb.negative) 0b0100_0000 else 0;
        const h: u8 = if (gb.halfCarry) 0b0010_0000 else 0;
        const c: u8 = if (gb.carry) 0b0001_0000 else 0;

        return z | n | h | c;
    }

    pub fn writeFlags(gb: *Gb, flags: u8) void {
        gb.zero = flags & 0b1000_0000 > 0;
        gb.negative = flags & 0b0100_0000 > 0;
        gb.halfCarry = flags & 0b0010_0000 > 0;
        gb.carry = flags & 0b0001_0000 > 0;
    }

    pub fn pushPc(gb: *Gb) void {
        const high: u8 = @truncate(gb.pc >> 8);
        const low: u8 = @truncate(gb.pc);
        gb.sp -%= 1;
        gb.write(gb.sp, high);
        gb.sp -%= 1;
        gb.write(gb.sp, low);
    }

    pub fn read(gb: *Gb, addr: u16) u8 {
        return switch (addr) {
            // ROM bank 00
            0x0000...0x3fff => gb.rom[addr],
            // ROM bank 01-NN
            0x4000...0x7fff => gb.rom[addr], // TODO handle bank switching
            // VRAM
            0x8000...0x9fff => blk: {
                if (gb.vramMutex.tryLock()) {
                    const val = gb.vram[addr - 0x8000];
                    gb.vramMutex.unlock();
                    break :blk val;
                } else {
                    // garbage data is returned when VRAM is in use by the PPU
                    std.log.warn("Attempted to read from VRAM outside of HBLANK/VBLANK (${x})\n", .{addr});
                    break :blk 0xff;
                }
            },
            // External RAM
            0xa000...0xbfff => 0xff, // TODO implement
            // WRAM
            0xc000...0xdfff => gb.wram[addr - 0xc000],
            // Echo RAM
            0xe000...0xfdff => gb.wram[addr - 0xc000],
            // OAM
            0xfe00...0xfe9f => blk: {
                if (gb.oamMutex.tryLock()) {
                    const val = gb.oam[addr - 0xfe00];
                    gb.oamMutex.unlock();
                    break :blk val;
                } else {
                    // garbage data is returned when ORAM is in use by the PPU
                    std.log.warn("Attempted to read from VRAM outside of HBLANK/VBLANK (${x})\n", .{addr});
                    break :blk 0xff;
                }
            },
            // Not useable
            0xfea0...0xfeff => std.debug.panic("Attempted to read from prohibited memory at ${x}\n", .{addr}),
            // I/O Registers
            0xff00...0xff7f => gb.ioRegs[addr - 0xff00].load(.monotonic),
            // HRAM
            0xff80...0xfffe => gb.hram[addr - 0xff80],
            // IE
            0xffff => gb.ie,
        };
    }

    pub fn write(gb: *Gb, addr: u16, val: u8) void {
        switch (addr) {
            // ROM bank 00
            0x0000...0x3fff => std.debug.panic("Attempted to write to ROM bank 0 (${x} -> ${x})\n", .{ val, addr }),
            // ROM bank 01-NN
            0x4000...0x7fff => std.debug.panic("Cartridge operations are not yet implemented (${x} -> ${x})\n", .{ val, addr }), // TODO handle bank switching
            // VRAM
            0x8000...0x9fff => {
                if (gb.vramMutex.tryLock()) {
                    gb.vram[addr - 0x8000] = val;
                    gb.vramMutex.unlock();
                } else {
                    std.log.warn("Attempted to write to VRAM outside of HBLANK/VBLANK (${x} -> {x})\n", .{ val, addr });
                }
            },
            // External RAM
            0xa000...0xbfff => std.debug.panic("Writing to external RAM is not implemented (${x} -> {x})\n", .{ val, addr }), // TODO implement
            // WRAM
            0xc000...0xdfff => {
                gb.wram[addr - 0xc000] = val;
            },
            // Echo RAM
            0xe000...0xfdff => {
                std.log.warn("Writing to Echo RAM (${x} -> {x})\n", .{ val, addr });
                gb.wram[addr - 0xc000] = val;
            },
            // OAM
            0xfe00...0xfe9f => {
                gb.oam[addr - 0xfe00] = val;
            },
            // Not useable
            0xfea0...0xfeff => std.debug.panic("Attempted to write to prohibited memory (${x} -> ${x})\n", .{ val, addr }),
            // I/O Registers
            0xff00...0xff7f => {
                gb.ioRegs[addr - 0xff00].store(val, .monotonic);
            },
            // HRAM
            0xff80...0xfffe => {
                gb.hram[addr - 0xff80] = val;
            },
            // IE
            0xffff => {
                gb.ie = val;
            },
        }
    }

    pub fn setStatMode(gb: *Gb, mode: u8) void {
        _ = gb.ioRegs[IoReg.STAT - 0xff00].fetchAnd(StatFlag.MODE_0, .monotonic);
        _ = gb.ioRegs[IoReg.STAT - 0xff00].fetchOr(mode, .monotonic);
    }

    pub fn setStatLycIncident(gb: *Gb, isIncident: bool) void {
        if (isIncident) {
            _ = gb.ioRegs[IoReg.STAT - 0xff00].fetchOr(StatFlag.LYC_INCIDENT_TRUE, .monotonic);
        } else {
            _ = gb.ioRegs[IoReg.STAT - 0xff00].fetchAnd(StatFlag.LYC_INCIDENT_FALSE, .monotonic);
        }
    }

    pub fn requestInterrupt(gb: *Gb, interrupt: u8) void {
        // TODO handle "STAT blocking" behavior
        _ = gb.ioRegs[IoReg.IF - 0xff00].fetchOr(interrupt, .monotonic);
    }
};
