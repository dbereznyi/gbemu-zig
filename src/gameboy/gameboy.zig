const std = @import("std");
const decodeInstrAt = @import("cpu").decodeInstrAt;
const Debug = @import("debug/root.zig").Debug;
const Timer = @import("timer/root.zig").Timer;
const Dma = @import("dma/root.zig").Dma;
const Cart = @import("cart/root.zig").Cart;
const Joypad = @import("joypad/root.zig").Joypad;
const Ppu = @import("ppu/root.zig").Ppu;
const Apu = @import("apu/root.zig").Apu;
const ApuReg = @import("apu/root.zig").ApuReg;
const Bess = @import("bess/root.zig").Bess;

pub const IoReg = .{
    .JOYP = 0x00,
    .SB = 0x01,
    .SC = 0x02,
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

    bess: ?Bess,

    pub fn init(
        alloc: std.mem.Allocator,
        rom: []const u8,
        save_data: ?[]const u8,
    ) !Gb {
        const vram = try alloc.alloc(u8, 8 * 1024);
        @memset(vram, 0);

        const wram = try alloc.alloc(u8, 8 * 1024);
        @memset(wram, 0);

        const oam = try alloc.alloc(u8, 160);
        @memset(oam, 0);

        var io_regs = try alloc.alloc(u8, 128);
        @memset(io_regs, 0);
        io_regs[IoReg.JOYP] = 0xff;

        const hram = try alloc.alloc(u8, 128);
        @memset(hram, 0);

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
            .bess = null,
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

    pub fn panic(gb: *const Gb, comptime msg: []const u8, args: anytype) noreturn {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        stdout.print("\n", .{}) catch {};

        gb.debug.printExecutionTrace(stdout, Debug.MAX_TRACE_LENGTH) catch {};
        stdout.print("\n", .{}) catch {};
        gb.printDebugState(stdout) catch {};
        stdout.print("\n", .{}) catch {};

        stdout.flush() catch {};

        std.debug.panic(msg, args);
    }

    pub fn printDebugState(gb: *const Gb, writer: *std.Io.Writer) !void {
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
};
