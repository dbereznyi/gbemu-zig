const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const AtomicOrder = std.builtin.AtomicOrder;
const Instr = @import("cpu/instruction.zig").Instr;
const as16 = @import("util.zig").as16;

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

pub const JoypFlag = .{
    .SELECT_BUTTONS = 0b0010_0000,
    .SELECT_DPAD = 0b0001_0000,
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

pub const ExecState = enum {
    running,
    halted,
    haltedDiscardInterrupt,
    stopped,
};

pub const Button = .{
    .A = 0b0000_0001,
    .B = 0b0000_0010,
    .SELECT = 0b0000_0100,
    .START = 0b0000_1000,
    .RIGHT = 0b0001_0000,
    .LEFT = 0b0010_0000,
    .UP = 0b0100_0000,
    .DOWN = 0b1000_0000,
};

const Debug = struct {
    paused: std.atomic.Value(bool),
    stepModeEnabled: bool,
    breakpoints: std.ArrayList(u16),
    stackBase: u16,

    frameTimeNs: u64,

    pub fn init(breakpoints: std.ArrayList(u16)) Debug {
        return Debug{
            .paused = std.atomic.Value(bool).init(false),
            .stepModeEnabled = false,
            .breakpoints = breakpoints,
            .stackBase = 0xfffe,

            .frameTimeNs = 0,
        };
    }

    pub fn isPaused(debug: *Debug) bool {
        return debug.paused.load(.monotonic);
    }

    pub fn setPaused(debug: *Debug, val: bool) void {
        debug.paused.store(val, .monotonic);
    }
};

const Dma = struct {
    const Mode = enum {
        idle,
        transfer,
    };

    mode: Dma.Mode,
    transferPending: bool,
    startAddr: u16,
    bytesTransferred: u16,

    pub fn init() Dma {
        return Dma{
            .mode = .idle,
            .transferPending = false,
            .startAddr = 0x0000,
            .bytesTransferred = 0,
        };
    }

    pub fn printState(dma: *const Dma) void {
        std.debug.print("mode={s} transferPending={} startAddr={x:0>4} bytesTransferred={}\n", .{
            switch (dma.mode) {
                .idle => "idle",
                .transfer => "transfer",
            },
            dma.transferPending,
            dma.startAddr,
            dma.bytesTransferred,
        });
    }
};

const Joypad = struct {
    const Mode = enum {
        waitingForLowEdge,
        lowEdge,
    };

    mode: Joypad.Mode,
    data: std.atomic.Value(u8),
    cyclesSinceLowEdgeTransition: u8,

    pub fn init() Joypad {
        return Joypad{
            .mode = .waitingForLowEdge,
            .data = std.atomic.Value(u8).init(0),
            .cyclesSinceLowEdgeTransition = 0,
        };
    }

    pub fn readButtons(joypad: *Joypad) u4 {
        return @truncate(joypad.data.load(.monotonic));
    }

    pub fn readDpad(joypad: *Joypad) u4 {
        return @truncate((joypad.data.load(.monotonic) & 0b1111_0000) >> 4);
    }

    pub fn pressButton(joypad: *Joypad, button: u8) void {
        _ = joypad.data.fetchOr(button, .monotonic);
    }

    pub fn releaseButton(joypad: *Joypad, button: u8) void {
        _ = joypad.data.fetchAnd(~button, .monotonic);
    }

    pub fn printState(joypad: *Joypad) void {
        std.debug.print("data={b:0>8} cyclesSinceLowEdgeTransition={}\n", .{ joypad.data.load(.monotonic), joypad.cyclesSinceLowEdgeTransition });
    }
};

pub const Ppu = struct {
    pub const Mode = enum {
        oam,
        drawing,
        hBlank,
        vBlank,
    };

    pub const ObjectAttribute = struct {
        y: u8,
        x: u8,
        tileNumber: u8,
        flags: u8,
        oamIndex: usize, // used for sorting

        pub fn isLessThan(_: void, lhs: ObjectAttribute, rhs: ObjectAttribute) bool {
            if (lhs.x != rhs.x) {
                return lhs.x < rhs.x;
            }

            return lhs.oamIndex < rhs.oamIndex;
        }
    };

    pub const Palette = .{
        // A black-and-white palette. Seems to be used often by emulators/later consoles.
        .GREY = [4]Pixel{
            .{ .r = 255, .g = 255, .b = 255 },
            .{ .r = 127, .g = 127, .b = 127 },
            .{ .r = 63, .g = 63, .b = 63 },
            .{ .r = 0, .g = 0, .b = 0 },
        },
        // A green-ish palette. Closer in feel to original DMG graphics.
        .GREEN = [4]Pixel{
            .{ .r = 239, .g = 255, .b = 222 },
            .{ .r = 173, .g = 215, .b = 148 },
            .{ .r = 82, .g = 146, .b = 115 },
            .{ .r = 24, .g = 52, .b = 66 },
        },
    };

    dots: usize,
    palette: [4]Pixel,
    y: usize,
    x: usize,
    wy: u8,
    windowY: usize,
    mode: Ppu.Mode,
    objAttrsLineBuf: [10]Ppu.ObjectAttribute,
    objAttrsLine: []Ppu.ObjectAttribute,

    pub fn init(palette: [4]Pixel) Ppu {
        return Ppu{
            .dots = 0,
            .palette = palette,
            .y = 0,
            .x = 0,
            .wy = 0,
            .windowY = 0,
            .mode = .oam,
            .objAttrsLineBuf = undefined,
            .objAttrsLine = undefined,
        };
    }

    pub fn printState(ppu: *const Ppu) void {
        std.debug.print("dots={d:>6} y={d:0>3} x={d:0>3} wy={d:0>3} windowY={d:0>3} mode={}\n", .{
            ppu.dots,
            ppu.y,
            ppu.x,
            ppu.wy,
            ppu.windowY,
            ppu.mode,
        });
    }
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
    wram: []u8,
    oam: []u8,
    ioRegs: []std.atomic.Value(u8),
    hram: []u8,
    ie: u8,
    rom: []const u8,

    ppu: Ppu,
    joypad: Joypad,
    dma: Dma,

    screen: []Pixel,

    scanningOam: bool,
    isDrawing: bool,
    inVBlank: std.atomic.Value(bool),

    running: std.atomic.Value(bool),

    debug: Debug,

    pub fn init(alloc: std.mem.Allocator, rom: []const u8, palette: [4]Pixel) !Gb {
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
        ioRegs[IoReg.JOYP - 0xff00].store(0b0011_1111, .monotonic);

        const hram = try alloc.alloc(u8, 128);
        for (hram, 0..) |_, i| {
            hram[i] = 0;
        }

        const screen: []Pixel = try alloc.alloc(Pixel, 160 * 144);
        for (screen) |*pixel| {
            pixel.* = palette[0];
        }

        const breakpoints = try std.ArrayList(u16).initCapacity(alloc, 128);

        return Gb{
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
            .branchCond = false,
            .ime = false,
            .execState = ExecState.running,
            .skipPcIncrement = false,
            .vram = vram,
            .wram = wram,
            .oam = oam,
            .ioRegs = ioRegs,
            .hram = hram,
            .ie = 0,
            .rom = rom,
            .screen = screen,
            .ppu = Ppu.init(palette),
            .joypad = Joypad.init(),
            .dma = Dma.init(),
            .scanningOam = false,
            .isDrawing = false,
            .inVBlank = std.atomic.Value(bool).init(false),
            .running = std.atomic.Value(bool).init(true),
            .debug = Debug.init(breakpoints),
        };
    }

    pub fn deinit(gb: *const Gb, alloc: std.mem.Allocator) void {
        alloc.free(gb.vram);
        alloc.free(gb.wram);
        alloc.free(gb.oam);
        alloc.free(gb.ioRegs);
        alloc.free(gb.hram);
        alloc.free(gb.screen);
        gb.debug.breakpoints.deinit();
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
        const lcdOn = gb.ioRegs[IoReg.LCDC - 0xff00].load(.monotonic) & LcdcFlag.ON > 0;
        return lcdOn and gb.isDrawing;
    }

    pub fn isLcdOn(gb: *Gb) bool {
        return gb.ioRegs[IoReg.LCDC - 0xff00].load(.monotonic) & LcdcFlag.ON > 0;
    }

    pub fn isInVBlank(gb: *Gb) bool {
        return gb.inVBlank.load(.monotonic);
    }

    pub fn read(gb: *Gb, addr: u16) u8 {
        return switch (addr) {
            // ROM bank 00
            0x0000...0x3fff => gb.rom[addr],
            // ROM bank 01-NN
            0x4000...0x7fff => gb.rom[addr], // TODO handle bank switching
            // VRAM
            0x8000...0x9fff => blk: {
                if (!gb.isVramInUse()) {
                    const val = gb.vram[addr - 0x8000];
                    break :blk val;
                } else {
                    // garbage data is returned when VRAM is in use by the PPU
                    std.log.warn("Attempted to read from VRAM while in use (${x})\n", .{addr});
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
                if (!gb.isLcdOn() or !gb.scanningOam) {
                    const val = gb.oam[addr - 0xfe00];
                    break :blk val;
                } else {
                    // garbage data is returned when ORAM is in use by the PPU
                    std.log.warn("Attempted to read from OAM while in use (${x})\n", .{addr});
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
                if (!gb.isVramInUse()) {
                    gb.vram[addr - 0x8000] = val;
                } else {
                    std.debug.panic("Attempted to write to VRAM while in use (${x} -> {x})\n", .{ val, addr });
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
                if (!gb.isLcdOn() or !gb.scanningOam) {
                    gb.oam[addr - 0xfe00] = val;
                } else {
                    std.log.warn("Attempted to write to OAM while in use (${x} -> {x})\n", .{ val, addr });
                }
            },
            // Not useable
            0xfea0...0xfeff => std.debug.panic("Attempted to write to prohibited memory (${x} -> ${x})\n", .{ val, addr }),
            // I/O Registers
            0xff00...0xff7f => {
                gb.ioRegs[addr - 0xff00].store(val, .monotonic);
                if (addr == IoReg.DMA) {
                    gb.dma.transferPending = true;
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
        _ = gb.ioRegs[IoReg.STAT - 0xff00].fetchAnd(StatFlag.MODE_CLEAR, .monotonic);
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
        _ = gb.ioRegs[IoReg.IF - 0xff00].fetchOr(interrupt, .monotonic);
    }

    pub fn clearInterrupt(gb: *Gb, interrupt: u8) void {
        _ = gb.ioRegs[IoReg.IF - 0xff00].fetchAnd(~interrupt, .monotonic);
    }

    pub fn isInterruptEnabled(gb: *Gb, interrupt: u8) bool {
        return gb.ie & interrupt > 0;
    }

    pub fn isInterruptPending(gb: *Gb, interrupt: u8) bool {
        return gb.ioRegs[IoReg.IF - 0xff00].load(.monotonic) & interrupt > 0;
    }

    pub fn anyInterruptsPending(gb: *Gb) bool {
        return gb.ioRegs[IoReg.IF - 0xff00].load(.monotonic) > 0;
    }

    pub fn printDebugState(gb: *Gb) void {
        std.debug.print("PC: ${x:0>4} SP: ${x:0>4}\n", .{ gb.pc, gb.sp });
        std.debug.print("Z: {} N: {} H: {} C: {}\n", .{ gb.zero, gb.negative, gb.halfCarry, gb.carry });
        std.debug.print("A: ${x:0>2} B: ${x:0>2} D: ${x:0>2} H: ${x:0>2}\n", .{ gb.a, gb.b, gb.d, gb.h });
        std.debug.print("F: ${x:0>2} C: ${x:0>2} E: ${x:0>2} L: ${x:0>2}\n", .{ gb.readFlags(), gb.c, gb.e, gb.l });
        std.debug.print("LY: ${x:0>2} LCDC: %{b:0>8} STAT: %{b:0>8}\n", .{
            gb.read(IoReg.LY),
            gb.read(IoReg.LCDC),
            gb.read(IoReg.STAT),
        });
        std.debug.print("IE: %{b:0>8} IF: %{b:0>8}\n", .{
            gb.read(IoReg.IE),
            gb.read(IoReg.IF),
        });
    }
};
