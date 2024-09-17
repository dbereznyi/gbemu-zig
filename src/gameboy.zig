const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Instr = @import("cpu/instruction.zig").Instr;
const as16 = @import("util.zig").as16;
const BoundedStack = @import("util.zig").BoundedStack;
const DebugCmd = @import("debug/cmd.zig").DebugCmd;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;
const format = std.fmt.format;
const PrefixOp = @import("cpu/prefix_op.zig").PrefixOp;

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

pub const JoypFlag = .{
    .SELECT_BUTTONS = 0b0010_0000,
    .SELECT_DPAD = 0b0001_0000,
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

pub const ExecState = enum {
    running,
    handling_interrupt,
    halted,
    haltedDiscardInterrupt,
    stopped,
};

pub const Button = enum(u8) {
    a = 0b0000_0001,
    b = 0b0000_0010,
    select = 0b0000_0100,
    start = 0b0000_1000,
    right = 0b0001_0000,
    left = 0b0010_0000,
    up = 0b0100_0000,
    down = 0b1000_0000,
};

pub const Debug = struct {
    const TraceLine = struct {
        bank: u8,
        pc: u16,
        instr: Instr,
    };
    pub const Breakpoint = struct {
        bank: u8,
        addr: u16,
    };
    pub const MAX_TRACE_LENGTH = 16;

    paused: std.atomic.Value(bool),
    skipCurrentInstruction: bool,
    stepModeEnabled: bool,
    breakpoints: std.ArrayList(Breakpoint),
    stackBase: u16,
    executionTrace: BoundedStack(TraceLine, MAX_TRACE_LENGTH),

    frameTimeNs: u64,

    lastCommand: ?DebugCmd,
    pendingCommand: ?DebugCmd,
    pendingResultBuf: []u8,
    pendingResult: ?[]u8,
    pendingResultSem: std.Thread.Semaphore,

    stdOutMutex: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator) !Debug {
        const breakpoints = try std.ArrayList(Breakpoint).initCapacity(alloc, 128);
        const executionTrace = BoundedStack(TraceLine, MAX_TRACE_LENGTH).init();
        const pendingResultBuf = try alloc.alloc(u8, 8 * 1024);

        return Debug{
            .paused = std.atomic.Value(bool).init(false),
            .skipCurrentInstruction = false,
            .stepModeEnabled = false,
            .breakpoints = breakpoints,
            .stackBase = 0xfffe,
            .executionTrace = executionTrace,

            .frameTimeNs = 0,

            .lastCommand = null,
            .pendingCommand = null,
            .pendingResultBuf = pendingResultBuf,
            .pendingResult = null,
            .pendingResultSem = std.Thread.Semaphore{},

            .stdOutMutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(debug: *const Debug) void {
        debug.breakpoints.deinit();
    }

    pub fn isPaused(debug: *Debug) bool {
        return debug.paused.load(.monotonic);
    }

    pub fn setPaused(debug: *Debug, val: bool) void {
        debug.paused.store(val, .monotonic);
    }

    pub fn sendCommand(debug: *Debug, cmd: DebugCmd) void {
        debug.pendingCommand = cmd;
    }

    pub fn receiveCommand(debug: *Debug) ?DebugCmd {
        return debug.pendingCommand;
    }

    pub fn acknowledgeCommand(debug: *Debug) void {
        debug.pendingCommand = null;
        debug.pendingResultSem.post();
    }

    pub fn addToExecutionTrace(debug: *Debug, bank: u8, pc: u16, instr: Instr) void {
        debug.executionTrace.push(.{ .bank = bank, .pc = pc, .instr = instr });
    }

    pub fn printExecutionTrace(debug: *const Debug, writer: anytype, count: usize) !void {
        std.debug.assert(count <= MAX_TRACE_LENGTH);

        var items_buf: [MAX_TRACE_LENGTH]TraceLine = undefined;
        const items = debug.executionTrace.getItemsReversed(&items_buf);
        const start_index = items.len -| count;
        for (start_index..items.len) |i| {
            const item = items[i];
            var instr_str_buf: [64]u8 = undefined;
            const instr_str = item.instr.toStr(&instr_str_buf) catch "?";
            try format(writer, "    rom{d:_>3}::{x:0>4}: {s}\n", .{ item.bank, item.pc, instr_str });
        }
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

    pub fn printState(dma: *const Dma, writer: anytype) !void {
        try format(writer, "mode={s} transferPending={} startAddr={x:0>4} bytesTransferred={}\n", .{
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

const Timer = struct {
    cycles_elapsed: usize,

    pub fn init() Timer {
        return Timer{
            .cycles_elapsed = 0,
        };
    }

    pub fn printState(timer: *const Timer, writer: anytype) !void {
        try format(writer, "cycles_elapsed={}\n", .{timer.cycles_elapsed});
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

    pub fn pressButton(joypad: *Joypad, button: Button) void {
        _ = joypad.data.fetchOr(@intFromEnum(button), .monotonic);
    }

    pub fn releaseButton(joypad: *Joypad, button: Button) void {
        _ = joypad.data.fetchAnd(~@intFromEnum(button), .monotonic);
    }

    pub fn printState(joypad: *Joypad, writer: anytype) !void {
        const data = joypad.data.load(.monotonic);
        const down: u1 = if (data & @intFromEnum(Button.down) > 0) 1 else 0;
        const up: u1 = if (data & @intFromEnum(Button.up) > 0) 1 else 0;
        const left: u1 = if (data & @intFromEnum(Button.left) > 0) 1 else 0;
        const right: u1 = if (data & @intFromEnum(Button.right) > 0) 1 else 0;
        const start: u1 = if (data & @intFromEnum(Button.start) > 0) 1 else 0;
        const select: u1 = if (data & @intFromEnum(Button.select) > 0) 1 else 0;
        const b: u1 = if (data & @intFromEnum(Button.b) > 0) 1 else 0;
        const a: u1 = if (data & @intFromEnum(Button.a) > 0) 1 else 0;
        try format(writer, "U={} D={} L={} R={} ST={} SE={} B={} A={}\n", .{ down, up, left, right, start, select, b, a });
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

    pub fn printState(ppu: *const Ppu, writer: anytype) !void {
        try format(writer, "dots={d:>6} y={d:0>3} x={d:0>3} wy={d:0>3} windowY={d:0>3} mode={s}\n", .{
            ppu.dots,
            ppu.y,
            ppu.x,
            ppu.wy,
            ppu.windowY,
            switch (ppu.mode) {
                .oam => "oam",
                .drawing => "drawing",
                .hBlank => "hBlank",
                .vBlank => "vBlank",
            },
        });
    }
};

const Cart = struct {
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

    // Internal registers.
    ir: u8,
    current_instr_cycle: u3,
    w: u8,
    z: u8,
    prefix_op: PrefixOp,
    enable_interrupts_next_cycle: bool,

    // For instructions that evaluate a condition,
    // this is set to true if the condition evaluated to true.
    branchCond: bool,
    ime: bool,
    execState: ExecState,
    skipPcIncrement: bool,

    vram: []u8,
    wram: []u8,
    oam: []u8,
    ioRegs: []std.atomic.Value(u8),
    hram: []u8,
    ie: u8,
    cart: Cart,

    ppu: Ppu,
    joypad: Joypad,
    dma: Dma,
    timer: Timer,

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
            .ir = 0,
            .current_instr_cycle = 0,
            .w = 0,
            .z = 0,
            .prefix_op = undefined,
            .enable_interrupts_next_cycle = false,
            .branchCond = false,
            .ime = false,
            .execState = .running,
            .skipPcIncrement = false,
            .vram = vram,
            .wram = wram,
            .oam = oam,
            .ioRegs = ioRegs,
            .hram = hram,
            .ie = 0,
            .cart = try Cart.init(rom, alloc),
            .screen = screen,
            .ppu = Ppu.init(palette),
            .joypad = Joypad.init(),
            .dma = Dma.init(),
            .timer = Timer.init(),
            .scanningOam = false,
            .isDrawing = false,
            .inVBlank = std.atomic.Value(bool).init(false),
            .running = std.atomic.Value(bool).init(true),
            .debug = try Debug.init(alloc),
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
        alloc.free(gb.debug.pendingResultBuf);
        gb.cart.deinit(alloc);
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
            0xff00...0xff7f => gb.ioRegs[addr - 0xff00].load(.monotonic),
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
                    gb.panic("Attempted to write to VRAM while in use (${x} -> {x})\n", .{ val, addr });
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
                gb.ioRegs[addr - 0xff00].store(val, .monotonic);
                switch (addr) {
                    IoReg.DIV => gb.ioRegs[addr - 0xff00].store(0, .monotonic),
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
        const if_ = gb.ioRegs[IoReg.IF - 0xff00].load(.monotonic);
        return (gb.ie & if_ & 0x1f) != 0;
    }

    pub fn panic(gb: *Gb, comptime msg: []const u8, args: anytype) noreturn {
        std.debug.print("\n", .{});
        gb.debug.printExecutionTrace(std.io.getStdOut().writer(), Debug.MAX_TRACE_LENGTH) catch unreachable;
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
    }

    pub fn printCurrentAndNextInstruction(gb: *Gb) !void {
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
