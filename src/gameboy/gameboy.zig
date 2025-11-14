const std = @import("std");
const Pixel = @import("../pixel.zig").Pixel;
const as16 = @import("../util.zig").as16;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;
const PrefixOp = @import("cpu/prefix_op.zig").PrefixOp;
const Debug = @import("debug/debug.zig").Debug;
const Timer = @import("timer/timer.zig").Timer;
const Dma = @import("dma/dma.zig").Dma;
const Cart = @import("cart.zig").Cart;
const Joypad = @import("joypad/joypad.zig").Joypad;
const Ppu = @import("ppu/ppu.zig").Ppu;
const Apu = @import("apu/apu.zig").Apu;
const ApuReg = @import("apu/apu.zig").ApuReg;

pub const IoReg = .{
    .JOYP = 0x00,
    .DIV = 0x04,
    .TIMA = 0x05,
    .TMA = 0x06,
    .TAC = 0x07,
    .IF = 0x0f,
    .NR10 = 0x10,
    .NR11 = 0x11,
    .NR12 = 0x12,
    .NR13 = 0x13,
    .NR14 = 0x14,
    .NR21 = 0x16,
    .NR22 = 0x17,
    .NR23 = 0x18,
    .NR24 = 0x19,
    .NR30 = 0x1a,
    .NR31 = 0x1b,
    .NR32 = 0x1c,
    .NR33 = 0x1d,
    .NR34 = 0x1e,
    .NR41 = 0x20,
    .NR42 = 0x21,
    .NR43 = 0x22,
    .NR44 = 0x23,
    .NR50 = 0x24,
    .NR51 = 0x25,
    .NR52 = 0x26,
    .LCDC = 0x40,
    .STAT = 0x41,
    .SCY = 0x42,
    .SCX = 0x43,
    .LY = 0x44,
    .LYC = 0x45,
    .DMA = 0x46,
    .BGP = 0x47,
    .OBP0 = 0x48,
    .OBP1 = 0x49,
    .WY = 0x4a,
    .WX = 0x4b,
    .IE = 0xff,
};

pub const TacFlag = .{
    .ENABLE = 0b0000_0100,
    .CLOCK_SELECT = 0b0000_0011,
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

pub const Interrupt = .{
    .VBLANK = @as(u8, 0b0000_0001),
    .STAT = @as(u8, 0b0000_0010),
    .TIMER = @as(u8, 0b0000_0100),
    .SERIAL = @as(u8, 0b0000_1000),
    .JOYPAD = @as(u8, 0b0001_0000),
};

pub const StatFlag = .{
    .MODE_CLEAR = 0b1111_1100,
    .MODE_0 = 0b0000_0000,
    .MODE_1 = 0b0000_0001,
    .MODE_2 = 0b0000_0010,
    .MODE_3 = 0b0000_0011,

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
    const Self = @This();

    stopped: bool,
    halted: bool,
    halt_bug: bool,
    toggle_ime: bool,
    cycles_since_last_sync: u64,
    last_sync: std.time.Instant,

    pc: u16,
    sp: u16,
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    zero: bool,
    negative: bool,
    halfCarry: bool,
    carry: bool,

    ime: bool,

    vram: []u8,
    wram: []u8,
    oam: []u8,
    io_regs: []u8,
    hram: []u8,
    ie: u8,

    cart: Cart,
    ppu: Ppu,
    apu: Apu,
    joypad: Joypad,
    dma: Dma,
    timer: Timer,
    debug: Debug,

    running: std.atomic.Value(bool),

    pending_cycles: usize,
    cycles: u64,

    pub fn init(
        alloc: std.mem.Allocator,
        rom: []const u8,
        save_data: ?[]const u8,
    ) !Gb {
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

        var io_regs = try alloc.alloc(u8, 128);
        for (io_regs, 0..) |_, i| {
            io_regs[i] = 0;
        }
        io_regs[IoReg.JOYP] = 0xff;

        const hram = try alloc.alloc(u8, 128);
        for (hram, 0..) |_, i| {
            hram[i] = 0;
        }

        return Gb{
            .stopped = false,
            .halted = false,
            .halt_bug = false,
            .toggle_ime = false,
            .cycles_since_last_sync = 0,
            .last_sync = try std.time.Instant.now(),
            .pc = 0x0100,
            .sp = 0xfffe,
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
            .ime = false,
            .vram = vram,
            .wram = wram,
            .oam = oam,
            .io_regs = io_regs,
            .hram = hram,
            .ie = 0,
            .cart = try Cart.init(rom, save_data, alloc),
            .ppu = try Ppu.init(alloc),
            .apu = try Apu.init(alloc),
            .joypad = Joypad.init(),
            .dma = Dma.init(),
            .timer = Timer.init(),
            .debug = try Debug.init(alloc),
            .running = std.atomic.Value(bool).init(true),
            .pending_cycles = 0,
            .cycles = 0,
        };
    }

    pub fn deinit(gb: *Gb, alloc: std.mem.Allocator) void {
        alloc.free(gb.vram);
        alloc.free(gb.wram);
        alloc.free(gb.oam);
        alloc.free(gb.io_regs);
        alloc.free(gb.hram);
        gb.cart.deinit(alloc);
        gb.debug.deinit();
        gb.ppu.deinit(alloc);
        gb.apu.deinit(alloc);
    }

    pub fn reset(gb: *Gb) void {
        gb.stopped = false;
        gb.halted = false;
        gb.halt_bug = false;
        gb.toggle_ime = false;
        gb.pc = 0x0100;
        gb.sp = 0xfffe;
        gb.a = 0;
        gb.b = 0;
        gb.c = 0;
        gb.d = 0;
        gb.e = 0;
        gb.h = 0;
        gb.l = 0;
        gb.zero = false;
        gb.negative = false;
        gb.halfCarry = false;
        gb.carry = false;
        gb.ime = false;
        @memset(gb.vram, 0);
        @memset(gb.wram, 0);
        @memset(gb.oam, 0);
        @memset(gb.io_regs, 0);
        gb.io_regs[IoReg.JOYP] = 0xff;
        @memset(gb.hram, 0);
        gb.ie = 0;
        gb.cart.reset();
        gb.ppu.reset();
        gb.apu.reset();
        gb.joypad.reset();
        gb.dma.reset();
        gb.timer.reset();
        gb.debug.reset();
        gb.pending_cycles = 0;
        gb.cycles = 0;
    }

    pub fn setVblankCallback(gb: *Gb, vblank_callback: Ppu.VblankCallback) void {
        gb.ppu.setVblankCallback(vblank_callback);
    }

    pub fn setAudioCallback(gb: *Gb, audio_callback: Apu.AudioCallback) void {
        gb.apu.setAudioCallback(audio_callback);
    }

    pub fn isRunning(gb: *Gb) bool {
        return gb.running.load(.monotonic);
    }

    pub fn setIsRunning(gb: *Gb, val: bool) void {
        gb.running.store(val, .monotonic);
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

    pub fn isVramInUse(gb: *Gb) bool {
        const lcdOn = gb.io_regs[IoReg.LCDC] & LcdcFlag.ON > 0;
        return lcdOn and gb.ppu.drawing;
    }

    pub fn isLcdOn(gb: *Gb) bool {
        return gb.io_regs[IoReg.LCDC] & LcdcFlag.ON > 0;
    }

    pub fn read(gb: *Gb, addr: u16) u8 {
        return switch (addr) {
            // ROM
            0x0000...0x7fff => gb.cart.readRom(addr),
            // VRAM
            0x8000...0x9fff => blk: {
                if (!gb.isVramInUse() or gb.debug.isPaused()) {
                    const val = gb.vram[addr - 0x8000];
                    break :blk val;
                } else {
                    break :blk 0xff;
                }
            },
            // External RAM
            0xa000...0xbfff => gb.cart.readRam(addr),
            // WRAM
            0xc000...0xdfff => gb.wram[addr - 0xc000],
            // Echo RAM
            0xe000...0xfdff => gb.wram[addr - 0xe000],
            // OAM
            0xfe00...0xfe9f => blk: {
                if (!gb.isLcdOn() or !gb.ppu.scanning_oam or gb.debug.isPaused()) {
                    const val = gb.oam[addr - 0xfe00];
                    break :blk val;
                } else {
                    break :blk 0xff;
                }
            },
            // Not useable
            0xfea0...0xfeff => blk: {
                //std.log.warn("Attempted to read from prohibited memory at ${x}\n", .{addr});
                break :blk 0xff;
            },
            // I/O Registers
            0xff00...0xff7f => {
                const reg_ix = addr - 0xff00;
                return switch (reg_ix) {
                    IoReg.DIV => @truncate(gb.timer.system_counter >> 8),
                    IoReg.NR10 => gb.apu.readReg(ApuReg.NR10),
                    IoReg.NR11 => gb.apu.readReg(ApuReg.NR11),
                    IoReg.NR12 => gb.apu.readReg(ApuReg.NR12),
                    IoReg.NR13 => gb.apu.readReg(ApuReg.NR13),
                    IoReg.NR14 => gb.apu.readReg(ApuReg.NR14),
                    IoReg.NR21 => gb.apu.readReg(ApuReg.NR21),
                    IoReg.NR22 => gb.apu.readReg(ApuReg.NR22),
                    IoReg.NR23 => gb.apu.readReg(ApuReg.NR23),
                    IoReg.NR24 => gb.apu.readReg(ApuReg.NR24),
                    IoReg.NR30 => gb.apu.readReg(ApuReg.NR30),
                    IoReg.NR31 => gb.apu.readReg(ApuReg.NR31),
                    IoReg.NR32 => gb.apu.readReg(ApuReg.NR32),
                    IoReg.NR33 => gb.apu.readReg(ApuReg.NR33),
                    IoReg.NR34 => gb.apu.readReg(ApuReg.NR34),
                    IoReg.NR41 => gb.apu.readReg(ApuReg.NR41),
                    IoReg.NR42 => gb.apu.readReg(ApuReg.NR42),
                    IoReg.NR43 => gb.apu.readReg(ApuReg.NR43),
                    IoReg.NR44 => gb.apu.readReg(ApuReg.NR44),
                    IoReg.NR50 => gb.apu.readReg(ApuReg.NR50),
                    IoReg.NR51 => gb.apu.readReg(ApuReg.NR51),
                    IoReg.NR52 => gb.apu.readReg(ApuReg.NR52),
                    0x30...0x3f => gb.apu.readWavRam(reg_ix - 0x30),
                    else => gb.io_regs[reg_ix],
                };
            },
            // HRAM
            0xff80...0xfffe => gb.hram[addr - 0xff80],
            // IE
            0xffff => gb.ie,
        };
    }

    pub fn write(gb: *Gb, addr: u16, val: u8) void {
        switch (addr) {
            // ROM
            0x0000...0x7fff => gb.cart.writeRom(addr, val),
            // VRAM
            0x8000...0x9fff => {
                if (!gb.isVramInUse() or gb.debug.isPaused()) {
                    gb.vram[addr - 0x8000] = val;
                }
            },
            // External RAM
            0xa000...0xbfff => gb.cart.writeRam(addr, val),
            // WRAM
            0xc000...0xdfff => {
                gb.wram[addr - 0xc000] = val;
            },
            // Echo RAM
            0xe000...0xfdff => {
                gb.wram[addr - 0xe000] = val;
            },
            // OAM
            0xfe00...0xfe9f => {
                if (!gb.isLcdOn() or !gb.ppu.scanning_oam or gb.debug.isPaused()) {
                    gb.oam[addr - 0xfe00] = val;
                }
            },
            // Not useable
            0xfea0...0xfeff => {
                //std.log.warn("Attempted to write to prohibited memory (${x} -> ${x})\n", .{ val, addr });
            },
            // I/O Registers
            0xff00...0xff7f => {
                const reg_ix = addr - 0xff00;
                switch (reg_ix) {
                    IoReg.DIV => {
                        gb.timer.system_counter = 0;
                    },
                    IoReg.NR10 => gb.apu.writeReg(ApuReg.NR10, val),
                    IoReg.NR11 => gb.apu.writeReg(ApuReg.NR11, val),
                    IoReg.NR12 => gb.apu.writeReg(ApuReg.NR12, val),
                    IoReg.NR13 => gb.apu.writeReg(ApuReg.NR13, val),
                    IoReg.NR14 => gb.apu.writeReg(ApuReg.NR14, val),
                    IoReg.NR21 => gb.apu.writeReg(ApuReg.NR21, val),
                    IoReg.NR22 => gb.apu.writeReg(ApuReg.NR22, val),
                    IoReg.NR23 => gb.apu.writeReg(ApuReg.NR23, val),
                    IoReg.NR24 => gb.apu.writeReg(ApuReg.NR24, val),
                    IoReg.NR30 => gb.apu.writeReg(ApuReg.NR30, val),
                    IoReg.NR31 => gb.apu.writeReg(ApuReg.NR31, val),
                    IoReg.NR32 => gb.apu.writeReg(ApuReg.NR32, val),
                    IoReg.NR33 => gb.apu.writeReg(ApuReg.NR33, val),
                    IoReg.NR34 => gb.apu.writeReg(ApuReg.NR34, val),
                    IoReg.NR41 => gb.apu.writeReg(ApuReg.NR41, val),
                    IoReg.NR42 => gb.apu.writeReg(ApuReg.NR42, val),
                    IoReg.NR43 => gb.apu.writeReg(ApuReg.NR43, val),
                    IoReg.NR44 => gb.apu.writeReg(ApuReg.NR44, val),
                    IoReg.NR50 => gb.apu.writeReg(ApuReg.NR50, val),
                    IoReg.NR51 => gb.apu.writeReg(ApuReg.NR51, val),
                    IoReg.NR52 => gb.apu.writeReg(ApuReg.NR52, val),
                    0x30...0x3f => gb.apu.writeWavRam(reg_ix - 0x30, val),
                    IoReg.DMA => {
                        gb.io_regs[reg_ix] = val;
                        gb.dma.transferPending = true;
                    },
                    else => {
                        gb.io_regs[reg_ix] = val;
                    },
                }
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
        gb.io_regs[IoReg.STAT] &= StatFlag.MODE_CLEAR;
        gb.io_regs[IoReg.STAT] |= mode;
    }

    pub fn setStatLycIncident(gb: *Gb, isIncident: bool) void {
        if (isIncident) {
            gb.io_regs[IoReg.STAT] |= StatFlag.LYC_INCIDENT_TRUE;
        } else {
            gb.io_regs[IoReg.STAT] &= StatFlag.LYC_INCIDENT_FALSE;
        }
    }

    pub fn requestInterrupt(gb: *Gb, interrupt: u8) void {
        gb.io_regs[IoReg.IF] |= interrupt;
    }

    pub fn clearInterrupt(gb: *Gb, interrupt: u8) void {
        gb.io_regs[IoReg.IF] &= ~interrupt;
    }

    pub fn isInterruptEnabled(gb: *const Gb, interrupt: u8) bool {
        return gb.ie & interrupt > 0;
    }

    pub fn isInterruptPending(gb: *const Gb, interrupt: u8) bool {
        return gb.io_regs[IoReg.IF] & interrupt > 0;
    }

    pub fn anyInterruptsPending(gb: *const Gb) bool {
        const if_ = gb.io_regs[IoReg.IF];
        return (gb.ie & if_ & 0x1f) != 0;
    }

    pub fn panic(gb: *Gb, comptime msg: []const u8, args: anytype) noreturn {
        std.debug.print("\n", .{});
        var stdout_writer = std.fs.File.stdout().writerStreaming(&.{}).interface;
        gb.debug.printExecutionTrace(&stdout_writer, Debug.MAX_TRACE_LENGTH) catch {};
        std.debug.print("\n", .{});
        gb.printDebugState(&stdout_writer) catch {};
        std.debug.print("\n", .{});
        std.debug.panic(msg, args);
    }

    pub fn printDebugState(gb: *Gb, writer: *std.Io.Writer) !void {
        try writer.print("PC: ${x:0>4} SP: ${x:0>4}\n", .{ gb.pc, gb.sp });
        try writer.print("Z: {} N: {} H: {} C: {}\n", .{ gb.zero, gb.negative, gb.halfCarry, gb.carry });
        try writer.print("A: ${x:0>2} B: ${x:0>2} D: ${x:0>2} H: ${x:0>2}\n", .{ gb.a, gb.b, gb.d, gb.h });
        try writer.print("F: ${x:0>2} C: ${x:0>2} E: ${x:0>2} L: ${x:0>2}\n", .{ gb.readFlags(), gb.c, gb.e, gb.l });
        try writer.print("LY: ${x:0>2} LCDC: %{b:0>8} STAT: %{b:0>8}\n", .{
            gb.io_regs[IoReg.LY],
            gb.io_regs[IoReg.LCDC],
            gb.io_regs[IoReg.STAT],
        });
        try writer.print("IE: %{b:0>8} IF: %{b:0>8} IME: {}\n", .{
            gb.ie,
            gb.io_regs[IoReg.IF],
            @as(u1, if (gb.ime) 1 else 0),
        });
        try writer.print("cycles: {}\n", .{gb.cycles});
    }

    pub fn printDebugTrace(gb: *Gb) !void {
        const PRINT_INSTR_BYTES = true;

        var stdout_writer = std.fs.File.stdout().writerStreaming(&.{}).interface;
        try gb.debug.printExecutionTrace(&stdout_writer, 5);

        var pc_offset: u16 = 0;

        for (0..6) |instr_offset| {
            var instrStrBuf: [64]u8 = undefined;
            const instr = decodeInstrAt(gb.pc + pc_offset, gb);
            const bank = gb.cart.getBank(gb.pc + pc_offset);

            const instr_str = try instr.toStr(&instrStrBuf);
            // TODO display correct address space for non-ROM addresses
            std.debug.print("{s} rom{d:_>3}::{x:0>4}: {s} ", .{
                if (instr_offset == 0) "==>" else "   ",
                bank,
                gb.pc + pc_offset,
                instr_str,
            });

            if (PRINT_INSTR_BYTES) {
                std.debug.print("(", .{});
                for (0..instr.size()) |i| {
                    std.debug.print("${x:0>2}", .{gb.read(gb.pc + pc_offset + @as(u16, @intCast(i)))});
                    if (i < instr.size() - 1) {
                        std.debug.print(" ", .{});
                    }
                }
                std.debug.print(")", .{});
            }
            std.debug.print("\n", .{});

            pc_offset += instr.size();
        }
    }
};
