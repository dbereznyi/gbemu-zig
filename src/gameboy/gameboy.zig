const std = @import("std");
const Pixel = @import("../pixel.zig").Pixel;
const as16 = @import("../util.zig").as16;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;
const format = std.fmt.format;
const PrefixOp = @import("cpu/prefix_op.zig").PrefixOp;
const Debug = @import("debug/debug.zig").Debug;
const Timer = @import("timer/timer.zig").Timer;
const Dma = @import("dma/dma.zig").Dma;
const Cart = @import("cart.zig").Cart;
const Joypad = @import("joypad/joypad.zig").Joypad;
const Ppu = @import("ppu/ppu.zig").Ppu;

pub const IoReg = .{
    .JOYP = 0xff00,
    .DIV = 0xff04,
    .TIMA = 0xff05,
    .TMA = 0xff06,
    .TAC = 0xff07,
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
    pub const State = enum {
        running,
        halted,
        handling_interrupt,
        stopped,
    };

    state: State,

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

    // Internal registers.
    ir: u8,
    current_instr_cycle: u3,
    w: u8,
    z: u8,
    prefix_op: PrefixOp,
    cycles_until_ei: u2,
    ime: bool,

    vram: []u8,
    wram: []u8,
    oam: []u8,
    io_regs: []u8,
    hram: []u8,
    ie: u8,

    cart: Cart,
    ppu: Ppu,
    joypad: Joypad,
    dma: Dma,
    timer: Timer,
    debug: Debug,

    screen: []Pixel,

    scanningOam: bool,
    isDrawing: bool,
    inVBlank: std.atomic.Value(bool),
    running: std.atomic.Value(bool),

    cycles: u64,

    pub fn init(
        alloc: std.mem.Allocator,
        rom: []const u8,
        save_data: ?[]const u8,
        palette: Ppu.Palette,
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
        io_regs[IoReg.JOYP - 0xff00] = 0b1111_1111;

        const hram = try alloc.alloc(u8, 128);
        for (hram, 0..) |_, i| {
            hram[i] = 0;
        }

        const screen: []Pixel = try alloc.alloc(Pixel, 160 * 144);
        for (screen) |*pixel| {
            pixel.* = palette.data()[0];
        }

        return Gb{
            .state = .running,
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
            .ir = 0,
            .current_instr_cycle = 0,
            .w = 0,
            .z = 0,
            .prefix_op = undefined,
            .cycles_until_ei = 0,
            .ime = false,
            .vram = vram,
            .wram = wram,
            .oam = oam,
            .io_regs = io_regs,
            .hram = hram,
            .ie = 0,
            .cart = try Cart.init(rom, save_data, alloc),
            .screen = screen,
            .ppu = Ppu.init(palette),
            .joypad = Joypad.init(),
            .dma = Dma.init(),
            .timer = Timer.init(),
            .debug = try Debug.init(alloc),
            .scanningOam = false,
            .isDrawing = false,
            .inVBlank = std.atomic.Value(bool).init(false),
            .running = std.atomic.Value(bool).init(true),
            .cycles = 0,
        };
    }

    pub fn deinit(gb: *const Gb, alloc: std.mem.Allocator) void {
        alloc.free(gb.vram);
        alloc.free(gb.wram);
        alloc.free(gb.oam);
        alloc.free(gb.io_regs);
        alloc.free(gb.hram);
        alloc.free(gb.screen);
        gb.cart.deinit(alloc);
        gb.debug.deinit();
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

    pub fn push16(gb: *Gb, value: u16) void {
        const high: u8 = @truncate(value >> 8);
        const low: u8 = @truncate(value);
        gb.sp -%= 1;
        gb.write(gb.sp, high);
        gb.sp -%= 1;
        gb.write(gb.sp, low);
    }

    pub fn pop16(gb: *Gb) u16 {
        const low = gb.read(gb.sp);
        gb.sp +%= 1;
        const high = gb.read(gb.sp);
        gb.sp +%= 1;
        return as16(high, low);
    }

    pub fn isVramInUse(gb: *Gb) bool {
        const lcdOn = gb.io_regs[IoReg.LCDC - 0xff00] & LcdcFlag.ON > 0;
        return lcdOn and gb.isDrawing;
    }

    pub fn isLcdOn(gb: *Gb) bool {
        return gb.io_regs[IoReg.LCDC - 0xff00] & LcdcFlag.ON > 0;
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
                    // garbage data is returned when VRAM is in use by the PPU
                    std.log.warn("Attempted to read from VRAM while in use (${x})\n", .{addr});
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
                if (!gb.isLcdOn() or !gb.scanningOam or gb.debug.isPaused()) {
                    const val = gb.oam[addr - 0xfe00];
                    break :blk val;
                } else {
                    // garbage data is returned when ORAM is in use by the PPU
                    std.log.warn("Attempted to read from OAM while in use (${x})\n", .{addr});
                    break :blk 0xff;
                }
            },
            // Not useable
            0xfea0...0xfeff => gb.panic("Attempted to read from prohibited memory at ${x}\n", .{addr}),
            // I/O Registers
            0xff00...0xff7f => gb.io_regs[addr - 0xff00],
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
                } else {
                    std.log.warn("Attempted to write to VRAM while in use (${x} -> {x})\n", .{ val, addr });
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
                std.log.warn("Writing to Echo RAM (${x} -> {x})\n", .{ val, addr });
                gb.wram[addr - 0xe000] = val;
            },
            // OAM
            0xfe00...0xfe9f => {
                if (!gb.isLcdOn() or !gb.scanningOam or gb.debug.isPaused()) {
                    gb.oam[addr - 0xfe00] = val;
                } else {
                    std.log.warn("Attempted to write to OAM while in use (${x} -> {x})\n", .{ val, addr });
                }
            },
            // Not useable
            0xfea0...0xfeff => gb.panic("Attempted to write to prohibited memory (${x} -> ${x})\n", .{ val, addr }),
            // I/O Registers
            0xff00...0xff7f => {
                gb.io_regs[addr - 0xff00] = val;
                switch (addr) {
                    IoReg.DIV => {
                        gb.io_regs[addr - 0xff00] = 0;
                        gb.timer.system_counter = 0;
                    },
                    IoReg.DMA => gb.dma.transferPending = true,
                    else => {},
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
        gb.io_regs[IoReg.STAT - 0xff00] &= StatFlag.MODE_CLEAR;
        gb.io_regs[IoReg.STAT - 0xff00] |= mode;
    }

    pub fn setStatLycIncident(gb: *Gb, isIncident: bool) void {
        if (isIncident) {
            gb.io_regs[IoReg.STAT - 0xff00] |= StatFlag.LYC_INCIDENT_TRUE;
        } else {
            gb.io_regs[IoReg.STAT - 0xff00] &= StatFlag.LYC_INCIDENT_FALSE;
        }
    }

    pub fn requestInterrupt(gb: *Gb, interrupt: u8) void {
        gb.io_regs[IoReg.IF - 0xff00] |= interrupt;
    }

    pub fn clearInterrupt(gb: *Gb, interrupt: u8) void {
        gb.io_regs[IoReg.IF - 0xff00] &= ~interrupt;
    }

    pub fn isInterruptEnabled(gb: *const Gb, interrupt: u8) bool {
        return gb.ie & interrupt > 0;
    }

    pub fn isInterruptPending(gb: *const Gb, interrupt: u8) bool {
        return gb.io_regs[IoReg.IF - 0xff00] & interrupt > 0;
    }

    pub fn anyInterruptsPending(gb: *const Gb) bool {
        const if_ = gb.io_regs[IoReg.IF - 0xff00];
        return (gb.ie & if_ & 0x1f) != 0;
    }

    pub fn panic(gb: *Gb, comptime msg: []const u8, args: anytype) noreturn {
        std.debug.print("\n", .{});
        gb.debug.printExecutionTrace(std.io.getStdOut().writer(), Debug.MAX_TRACE_LENGTH) catch unreachable;
        std.debug.print("\n", .{});
        gb.printDebugState(std.io.getStdOut().writer()) catch unreachable;
        std.debug.print("\n", .{});
        std.debug.panic(msg, args);
    }

    pub fn printDebugState(gb: *Gb, writer: anytype) !void {
        try format(writer, "PC: ${x:0>4} SP: ${x:0>4}\n", .{ gb.pc, gb.sp });
        try format(writer, "Z: {} N: {} H: {} C: {}\n", .{ gb.zero, gb.negative, gb.halfCarry, gb.carry });
        try format(writer, "A: ${x:0>2} B: ${x:0>2} D: ${x:0>2} H: ${x:0>2}\n", .{ gb.a, gb.b, gb.d, gb.h });
        try format(writer, "F: ${x:0>2} C: ${x:0>2} E: ${x:0>2} L: ${x:0>2}\n", .{ gb.readFlags(), gb.c, gb.e, gb.l });
        try format(writer, "LY: ${x:0>2} LCDC: %{b:0>8} STAT: %{b:0>8}\n", .{
            gb.read(IoReg.LY),
            gb.read(IoReg.LCDC),
            gb.read(IoReg.STAT),
        });
        try format(writer, "IE: %{b:0>8} IF: %{b:0>8} IME: {}\n", .{
            gb.read(IoReg.IE),
            gb.read(IoReg.IF),
            @as(u1, if (gb.ime) 1 else 0),
        });
        try format(writer, "cycles: {}\n", .{gb.cycles});
    }

    pub fn printDebugTrace(gb: *Gb) !void {
        const PRINT_INSTR_BYTES = false;

        try gb.debug.printExecutionTrace(std.io.getStdOut().writer(), 5);

        var pc_offset: u16 = 0;

        for (0..6) |instr_offset| {
            var instrStrBuf: [64]u8 = undefined;
            const instr = decodeInstrAt(gb.pc + pc_offset, gb);
            const bank = gb.cart.getBank(gb.pc + pc_offset);

            const instr_str = try instr.toStr(&instrStrBuf);
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
