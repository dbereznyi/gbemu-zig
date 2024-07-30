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

pub const ExecState = enum {
    running,
    halted,
    haltedSkipInterrupt,
    stopped,
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

    // for instructions that evaluate a condition,
    // this is set to true if the condition evaluated to true
    branchCond: bool,
    ime: bool,
    execState: ExecState,

    vram: []u8,
    vramMutex: std.Thread.Mutex,
    wram: []u8,
    ioRegs: []std.atomic.Value(u8),
    hram: []u8,
    ie: u8,
    rom: []const u8,
    cycles: u64,

    pub fn init(alloc: std.mem.Allocator, rom: []const u8) !Gb {
        const vram = try alloc.alloc(u8, 8 * 1024);
        const wram = try alloc.alloc(u8, 8 * 1024);
        var ioRegs = try alloc.alloc(std.atomic.Value(u8), 128);
        for (ioRegs, 0..) |_, i| {
            ioRegs[i] = std.atomic.Value(u8).init(0);
        }
        const hram = try alloc.alloc(u8, 128);

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
            .vram = vram,
            .vramMutex = std.Thread.Mutex{},
            .wram = wram,
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

    pub fn read(gb: *Gb, addr: u16) u8 {
        if (addr < 0x8000) {
            return gb.rom[addr];
        } else if (addr < 0xa000) {
            // VRAM
            if (gb.vramMutex.tryLock()) {
                const val = gb.vram[addr - 0x8000];
                gb.vramMutex.unlock();
                return val;
            } else {
                // garbage data is returned when VRAM is in use by the PPU
                return 0xff;
            }
        } else if (addr < 0xc000) {
            // external RAM
        } else if (addr < 0xe000) {
            // WRAM
            return gb.wram[addr - 0xc000];
        } else if (addr < 0xfe00) {
            // echo RAM
        } else if (addr < 0xfea0) {
            // OAM
        } else if (addr < 0xff00) {
            // not useable
        } else if (addr < 0xff80) {
            // I/O registers
            return gb.ioRegs[addr - 0xff00].load(AtomicOrder.monotonic);
        } else if (addr < 0xffff) {
            // HRAM
            return gb.hram[addr - 0xff80];
        } else {
            // IE
            return gb.ie;
        }

        return 0; // TODO implement rest of branches above
    }

    pub fn write(gb: *Gb, addr: u16, val: u8) void {
        if (addr < 0x4000) {
            // ROM bank 00
        } else if (addr < 0x8000) {
            // ROM bank 01~NN
        } else if (addr < 0xa000) {
            // VRAM
            if (gb.vramMutex.tryLock()) {
                gb.vram[addr - 0x8000] = val;
                gb.vramMutex.unlock();
            }
        } else if (addr < 0xc000) {
            // external RAM
        } else if (addr < 0xe000) {
            // WRAM
            gb.wram[addr - 0xc000] = val;
        } else if (addr < 0xfe00) {
            // echo RAM
        } else if (addr < 0xfea0) {
            // OAM
        } else if (addr < 0xff00) {
            // not useable
        } else if (addr < 0xff80) {
            // I/O registers
            gb.ioRegs[addr - 0xff00].store(val, AtomicOrder.monotonic);
        } else if (addr < 0xffff) {
            // HRAM
            gb.hram[addr - 0xff80] = val;
        } else {
            // IE
            gb.ie = val;
        }
    }
};
