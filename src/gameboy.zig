const std = @import("std");

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

    vram: []u8,
    wram: []u8,
    ioRegs: []u8,
    hram: []u8,
    rom: []const u8,
    cycles: u64,
};

pub fn initGb(alloc: std.mem.Allocator, rom: []const u8) !Gb {
    const vram = try alloc.alloc(u8, 8 * 1024);
    const wram = try alloc.alloc(u8, 8 * 1024);
    const ioRegs = try alloc.alloc(u8, 128);
    const hram = try alloc.alloc(u8, 128);
    return Gb{
        .pc = 0,
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
        .vram = vram,
        .wram = wram,
        .ioRegs = ioRegs,
        .hram = hram,
        .rom = rom,
        .cycles = 0,
    };
}

pub fn readAddr(gb: *const Gb, addr: u16) u8 {
    if (addr < 0x8000) {
        // ROM
        return gb.rom[addr];
    } else if (addr < 0xa000) {
        // VRAM
        return gb.vram[addr - 0xa000];
    } else if (addr < 0xc000) {
        // external RAM
    } else if (addr < 0xe000) {
        // WRAM
        return gb.wram[addr - 0xe000];
    } else if (addr < 0xfe00) {
        // echo RAM
    } else if (addr < 0xfea0) {
        // OAM
    } else if (addr < 0xff00) {
        // not useable
    } else if (addr < 0xff80) {
        // I/O registers
        return gb.ioRegs[addr - 0xff80];
    } else if (addr < 0xffff) {
        // HRAM
        return gb.hram[addr - 0xffff];
    } else {
        // IE
    }

    return 0; // TODO implement rest of branches above
}

pub fn writeAddr(gb: *Gb, addr: u16, val: u8) void {
    if (addr < 0x4000) {
        // ROM bank 00
    } else if (addr < 0x8000) {
        // ROM bank 01~NN
    } else if (addr < 0xa000) {
        // VRAM
        gb.vram[addr - 0xa000] = val;
    } else if (addr < 0xc000) {
        // external RAM
    } else if (addr < 0xe000) {
        // WRAM
        gb.wram[addr - 0xe000] = val;
    } else if (addr < 0xfe00) {
        // echo RAM
    } else if (addr < 0xfea0) {
        // OAM
    } else if (addr < 0xff00) {
        // not useable
    } else if (addr < 0xff80) {
        // I/O registers
        gb.ioRegs[addr - 0xff80] = val;
    } else if (addr < 0xffff) {
        // HRAM
        gb.hram[addr - 0xffff] = val;
    } else {
        // IE
    }
}
