const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const ApuReg = @import("apu/apu.zig").ApuReg;
const MbcReg = @import("cart.zig").MbcReg;

inline fn u16LE(bytes: []const u8) u16 {
    return std.mem.readVarInt(u16, bytes, .little);
}

inline fn u32LE(bytes: []const u8) u32 {
    return std.mem.readVarInt(u32, bytes, .little);
}

inline fn u64LE(bytes: []const u8) u64 {
    return std.mem.readVarInt(u64, bytes, .little);
}

fn readMemoryRegion(data: []const u8, i: *usize) ![]const u8 {
    if (data.len < 8) {
        return error.MemoryRegionHeaderTooShort;
    }
    const size: usize = u32LE(data[i.* .. i.* + 4]);
    i.* += 4;
    const start: usize = u32LE(data[i.* .. i.* + 4]);
    i.* += 4;

    if (start + size > data.len) {
        return error.MemoryRegionSizeTooLarge;
    }

    return data[start .. start + size];
}

pub const Bess = struct {
    const Self = @This();

    data: []const u8,
    name: ?BessName,
    info: ?BessInfo,
    core: BessCore,
    mbc: ?BessMbc,
    rtc: ?BessRtc,

    pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
        if (self.mbc) |mbc| mbc.deinit(alloc);
    }
};

const BessBlockTag = enum {
    name,
    info,
    core,
    mbc,
    rtc,
    end,
    unknown,
};

const BessBlock = union(BessBlockTag) {
    // Only implementing blocks that this emulator actually uses.
    name: BessName,
    info: BessInfo,
    core: BessCore,
    mbc: BessMbc,
    rtc: BessRtc,
    end: void,
    unknown: usize, // Just contains the block length in order to skip it

    pub fn parse(alloc: std.mem.Allocator, data: []const u8, i: *usize) !BessBlock {
        if (data.len < 8) {
            return error.NotEnoughDataForABlock;
        }

        const block_name = data[i.* .. i.* + 4];
        i.* += 4;
        const block_len: usize = u32LE(data[i.* .. i.* + 4]);
        i.* += 4;

        const block_start = i;

        std.debug.print("parsing block {s}, len = {}\n", .{ block_name, block_len });

        if (block_start.* + block_len > data.len) {
            return error.InvalidBlockLength;
        }

        if (std.mem.eql(u8, block_name, "NAME")) {
            return .{ .name = try BessName.init(data, block_start, block_len) };
        }
        if (std.mem.eql(u8, block_name, "INFO")) {
            return .{ .info = try BessInfo.init(data, block_start) };
        }
        if (std.mem.eql(u8, block_name, "CORE")) {
            return .{ .core = try BessCore.init(data, block_start) };
        }
        if (std.mem.eql(u8, block_name, "MBC ")) {
            return .{ .mbc = try BessMbc.init(alloc, data, block_start, block_len) };
        }
        if (std.mem.eql(u8, block_name, "RTC ")) {
            return .{ .rtc = try BessRtc.init(data, block_start) };
        }
        if (std.mem.eql(u8, block_name, "END ")) {
            return .end;
        }

        return .{ .unknown = block_len };
    }
};

const BessName = struct {
    name: []const u8,

    pub fn init(data: []const u8, i: *usize, len: usize) !BessName {
        if (i.* + len > data.len) {
            return error.NameBlockTooSmall;
        }

        i.* += len;

        return .{
            .name = data[i.* .. i.* + len],
        };
    }

    pub fn write(writer: anytype) !void {
        const name = "dbereznyi/gbemu";
        try writer.writeAll("NAME");
        try writer.writeInt(u32, name.len, .little);
        try writer.writeAll(name);
    }
};

const BessInfo = struct {
    title: []const u8,
    checksum: u16,

    pub fn init(data: []const u8, i: *usize) !BessInfo {
        if (data.len - i.* < 18) {
            return error.InfoBlockTooSmall;
        }

        i.* += 18;

        return .{
            .title = data[i.* .. i.* + 16],
            .checksum = u16LE(data[i.* + 16 .. i.* + 16 + 2]),
        };
    }

    pub fn write(writer: anytype, title: []const u8, checksum: u16) !void {
        if (title.len != 16) {
            return error.InfoBlockInvalidTitleLength;
        }

        try writer.writeAll("INFO");
        try writer.writeInt(u32, 18, .little);
        try writer.writeAll(title[0..16]);
        try writer.writeInt(u16, checksum, .little);
    }
};

const BessCore = struct {
    const ExecutionState = enum {
        running,
        halted,
        stopped,
    };

    major: u16,
    minor: u16,
    model: []const u8,
    pc: u16,
    af: u16,
    bc: u16,
    de: u16,
    hl: u16,
    sp: u16,
    ime: u1,
    ie: u8,
    state: ExecutionState,
    mm_regs: []const u8,
    ram: []const u8,
    vram: []const u8,
    mbc_ram: []const u8,
    oam: []const u8,
    hram: []const u8,

    pub fn init(data: []const u8, i: *usize) !BessCore {
        if (data.len - i.* < 0xd0) {
            return error.CoreBlockTooSmall;
        }

        const major = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const minor = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;

        if (major != 1 or minor != 1) {
            return error.UnsupportedVersion;
        }

        const model = data[i.* .. i.* + 4];
        i.* += 4;
        const pc = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const af = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const bc = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const de = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const hl = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const sp = u16LE(data[i.* .. i.* + 2]);
        i.* += 2;
        const ime: u1 = if (data[i.*] == 0) 0 else 1;
        i.* += 1;
        const ie = data[i.*];
        i.* += 1;
        var state: BessCore.ExecutionState = undefined;
        switch (data[i.*]) {
            0 => {
                state = .running;
            },
            1 => {
                state = .halted;
            },
            2 => {
                state = .stopped;
            },
            else => {
                return error.CoreBlockBadExecutionState;
            },
        }
        i.* += 1;

        i.* += 1; // Skip reserved byte

        const mm_regs = data[i.* .. i.* + 128];
        i.* += 128;

        const ram = try readMemoryRegion(data, i);
        const vram = try readMemoryRegion(data, i);
        const mbc_ram = try readMemoryRegion(data, i);
        const oam = try readMemoryRegion(data, i);
        const hram = try readMemoryRegion(data, i);

        return .{
            .major = major,
            .minor = minor,
            .model = model,
            .pc = pc,
            .af = af,
            .bc = bc,
            .de = de,
            .hl = hl,
            .sp = sp,
            .ime = ime,
            .ie = ie,
            .state = state,
            .mm_regs = mm_regs,
            .ram = ram,
            .vram = vram,
            .mbc_ram = mbc_ram,
            .oam = oam,
            .hram = hram,
        };
    }

    pub fn write(
        writer: anytype,
        gb: *Gb,
        ram_start: usize,
        vram_start: usize,
        mbc_ram_start: usize,
        oam_start: usize,
        hram_start: usize,
    ) !void {
        try writer.writeAll("CORE");
        try writer.writeInt(u32, 208, .little);

        try writer.writeInt(u16, 1, .little);
        try writer.writeInt(u16, 1, .little);

        try writer.writeAll("GD  ");

        try writer.writeInt(u16, gb.pc, .little);
        const af = @as(u16, @intCast(gb.a)) << 8 | @as(u16, @intCast(gb.readFlags()));
        try writer.writeInt(u16, af, .little);
        const bc = @as(u16, @intCast(gb.b)) << 8 | @as(u16, gb.c);
        try writer.writeInt(u16, bc, .little);
        const de = @as(u16, @intCast(gb.d)) << 8 | @as(u16, gb.e);
        try writer.writeInt(u16, de, .little);
        const hl = @as(u16, @intCast(gb.h)) << 8 | @as(u16, gb.l);
        try writer.writeInt(u16, hl, .little);
        try writer.writeInt(u16, gb.sp, .little);
        try writer.writeByte(if (gb.ime) 1 else 0);
        try writer.writeByte(gb.ie);
        try writer.writeByte(if (gb.stopped) 2 else if (gb.halted) 1 else 0);
        try writer.writeByte(0);

        try writer.writeByte(gb.io_regs[IoReg.JOYP]); // 0x00
        try writer.writeByte(0); // 0x01
        try writer.writeByte(0); // 0x02
        try writer.writeByte(0); // 0x03
        try writer.writeByte(@truncate(gb.timer.system_counter >> 8)); // 0x04
        try writer.writeByte(gb.io_regs[IoReg.TIMA]); // 0x05
        try writer.writeByte(gb.io_regs[IoReg.TMA]); // 0x06
        try writer.writeByte(gb.io_regs[IoReg.TAC]); // 0x07
        for (0x08..0x0f) |_| {
            try writer.writeByte(0);
        }
        try writer.writeByte(gb.io_regs[IoReg.IF]); // 0x0f
        try writer.writeByte(gb.apu.readReg(ApuReg.NR10)); // 0x10
        try writer.writeByte(gb.apu.readReg(ApuReg.NR11)); // 0x11
        try writer.writeByte(gb.apu.readReg(ApuReg.NR12)); // 0x12
        try writer.writeByte(gb.apu.readReg(ApuReg.NR13)); // 0x13
        try writer.writeByte(gb.apu.readReg(ApuReg.NR14)); // 0x14
        try writer.writeByte(0); // 0x15
        try writer.writeByte(gb.apu.readReg(ApuReg.NR21)); // 0x16
        try writer.writeByte(gb.apu.readReg(ApuReg.NR22)); // 0x17
        try writer.writeByte(gb.apu.readReg(ApuReg.NR23)); // 0x18
        try writer.writeByte(gb.apu.readReg(ApuReg.NR24)); // 0x19
        try writer.writeByte(gb.apu.readReg(ApuReg.NR30)); // 0x1a
        try writer.writeByte(gb.apu.readReg(ApuReg.NR31)); // 0x1b
        try writer.writeByte(gb.apu.readReg(ApuReg.NR32)); // 0x1c
        try writer.writeByte(gb.apu.readReg(ApuReg.NR33)); // 0x1d
        try writer.writeByte(gb.apu.readReg(ApuReg.NR34)); // 0x1e
        try writer.writeByte(0); // 0x1f
        try writer.writeByte(gb.apu.readReg(ApuReg.NR41)); // 0x20
        try writer.writeByte(gb.apu.readReg(ApuReg.NR42)); // 0x21
        try writer.writeByte(gb.apu.readReg(ApuReg.NR43)); // 0x22
        try writer.writeByte(gb.apu.readReg(ApuReg.NR44)); // 0x23
        try writer.writeByte(gb.apu.readReg(ApuReg.NR50)); // 0x24
        try writer.writeByte(gb.apu.readReg(ApuReg.NR51)); // 0x25
        try writer.writeByte(gb.apu.readReg(ApuReg.NR52)); // 0x26
        for (0x27..0x30) |_| {
            try writer.writeByte(0);
        }
        {
            const wav_ram = gb.apu.ch3.wav_ram;
            var i: usize = 0;
            while (i < 32) : (i += 2) {
                const upper: u8 = wav_ram[i];
                const lower: u8 = wav_ram[i + 1];
                try writer.writeByte((upper << 4) | lower);
            }
        }
        try writer.writeByte(gb.io_regs[IoReg.LCDC]); // 0x40
        try writer.writeByte(gb.io_regs[IoReg.STAT]); // 0x41
        try writer.writeByte(gb.io_regs[IoReg.SCY]); // 0x42
        try writer.writeByte(gb.io_regs[IoReg.SCX]); // 0x43
        try writer.writeByte(gb.io_regs[IoReg.LY]); // 0x44
        try writer.writeByte(gb.io_regs[IoReg.LYC]); // 0x45
        try writer.writeByte(gb.io_regs[IoReg.DMA]); // 0x46
        try writer.writeByte(gb.io_regs[IoReg.BGP]); // 0x47
        try writer.writeByte(gb.io_regs[IoReg.OBP0]); // 0x48
        try writer.writeByte(gb.io_regs[IoReg.OBP1]); // 0x49
        try writer.writeByte(gb.io_regs[IoReg.WY]); // 0x4a
        try writer.writeByte(gb.io_regs[IoReg.WX]); // 0x4b
        for (0x4c..0x80) |_| {
            try writer.writeByte(0);
        }

        try writer.writeInt(u32, @truncate(gb.wram.len), .little);
        try writer.writeInt(u32, @truncate(ram_start), .little);
        try writer.writeInt(u32, @truncate(gb.vram.len), .little);
        try writer.writeInt(u32, @truncate(vram_start), .little);
        try writer.writeInt(u32, @truncate(gb.cart.ram.len), .little);
        try writer.writeInt(u32, @truncate(mbc_ram_start), .little);
        try writer.writeInt(u32, @truncate(gb.oam.len), .little);
        try writer.writeInt(u32, @truncate(oam_start), .little);
        try writer.writeInt(u32, @truncate(gb.hram.len), .little);
        try writer.writeInt(u32, @truncate(hram_start), .little);
        // BGP palettes
        try writer.writeInt(u32, 0, .little);
        try writer.writeInt(u32, 0, .little);
        // OBJ palettes
        try writer.writeInt(u32, 0, .little);
        try writer.writeInt(u32, 0, .little);
    }
};

const BessMbc = struct {
    regs: []MbcReg,

    pub fn init(alloc: std.mem.Allocator, data: []const u8, i: *usize, len: usize) !BessMbc {
        if (data.len - i.* < len) {
            return error.MbcBlockTooSmall;
        }
        if (len % 3 != 0) {
            return error.MbcBlockLengthNotDivisibleBy3;
        }

        const start = i.*;

        const regs = try alloc.alloc(MbcReg, len / 3);
        var regs_ix: usize = 0;
        while (i.* < start + len) {
            const addr = u16LE(data[i.* .. i.* + 2]);
            i.* += 2;
            const val = data[i.*];
            i.* += 1;

            regs[regs_ix] = .{
                .addr = addr,
                .val = val,
            };
            regs_ix += 1;
        }

        return .{
            .regs = regs,
        };
    }

    pub fn deinit(self: *const BessMbc, alloc: std.mem.Allocator) void {
        alloc.free(self.regs);
    }

    pub fn write(writer: anytype, gb: *Gb) !void {
        try writer.writeAll("MBC ");

        var buf: [16]MbcReg = undefined;
        const regs = gb.cart.getMbcRegisters(&buf);
        try writer.writeInt(u32, @truncate(regs.len * 3), .little);

        for (regs) |reg| {
            try writer.writeInt(u16, reg.addr, .little);
            try writer.writeByte(reg.val);
        }
    }
};

const BessRtc = struct {
    seconds: u8,
    minutes: u8,
    hours: u8,
    days: u8,
    overflow: u8,
    latched_seconds: u8,
    latched_minutes: u8,
    latched_hours: u8,
    latched_days: u8,
    latched_overflow: u8,
    unix_timestamp: u64,

    pub fn init(data: []const u8, i: *usize) !BessRtc {
        if (data.len - i.* < 0x30) {
            return error.RtcBlockTooSmall;
        }

        const seconds = data[i.*];
        i.* += 1;
        const minutes = data[i.*];
        i.* += 1;
        const hours = data[i.*];
        i.* += 1;
        const days = data[i.*];
        i.* += 1;
        const overflow = data[i.*];
        i.* += 1;
        const latched_seconds = data[i.*];
        i.* += 1;
        const latched_minutes = data[i.*];
        i.* += 1;
        const latched_hours = data[i.*];
        i.* += 1;
        const latched_days = data[i.*];
        i.* += 1;
        const latched_overflow = data[i.*];
        i.* += 1;
        const unix_timestamp = u64LE(data[i.* .. i.* + 8]);
        i.* += 8;

        return .{
            .seconds = seconds,
            .minutes = minutes,
            .hours = hours,
            .days = days,
            .overflow = overflow,
            .latched_seconds = latched_seconds,
            .latched_minutes = latched_minutes,
            .latched_hours = latched_hours,
            .latched_days = latched_days,
            .latched_overflow = latched_overflow,
            .unix_timestamp = unix_timestamp,
        };
    }
};

const BessEnd = struct {
    pub fn write(writer: anytype) !void {
        try writer.writeAll("END ");
        try writer.writeInt(u32, 0, .little);
    }
};

pub fn readBess(alloc: std.mem.Allocator, data: []const u8) !Bess {
    if (data.len < 8) {
        return error.DataTooShort;
    }

    const bess_footer = data[data.len - 4 .. data.len];
    if (!std.mem.eql(u8, bess_footer, "BESS")) {
        return error.BadFooter;
    }
    const first_block_start: usize = u32LE(data[data.len - 8 .. data.len - 4]);
    if (first_block_start > data.len - 8) {
        return error.InvalidFirstBlockOffset;
    }

    var name: ?BessName = null;
    var info: ?BessInfo = null;
    var core: ?BessCore = null;
    var mbc: ?BessMbc = null;
    var rtc: ?BessRtc = null;
    var has_end = false;

    var i = first_block_start;
    while (i < data.len) {
        const block = try BessBlock.parse(alloc, data, &i);

        switch (block) {
            .name => {
                if (core != null) {
                    return error.NameBlockMustComeBeforeCoreBlock;
                }
                if (info != null) {
                    return error.NameBlockMustComeBeforeInfoBlock;
                }
                name = block.name;
            },
            .info => {
                if (core != null) {
                    return error.InfoBlockMustComeBeforeCoreBlock;
                }
                info = block.info;
            },
            .core => core = block.core,
            .mbc => mbc = block.mbc,
            .rtc => rtc = block.rtc,
            .end => {
                has_end = true;
                break;
            },
            .unknown => {},
        }
    }

    if (!has_end) {
        return error.MissingEndBlock;
    }

    if (core) |core_nonnull| {
        return Bess{
            .data = data,
            .name = name,
            .info = info,
            .core = core_nonnull,
            .mbc = mbc,
            .rtc = rtc,
        };
    } else {
        return error.MissingCoreBlock;
    }
}

pub fn loadBess(gb: *Gb, bess: Bess) void {
    gb.reset();

    const core = bess.core;

    gb.pc = core.pc;
    gb.sp = core.sp;
    gb.a = @truncate(core.af >> 8);
    gb.zero = core.af & 0b1000_0000 != 0;
    gb.negative = core.af & 0b0100_0000 != 0;
    gb.halfCarry = core.af & 0b0010_0000 != 0;
    gb.carry = core.af & 0b0001_0000 != 0;
    gb.b = @truncate(core.bc >> 8);
    gb.c = @truncate(core.bc);
    gb.d = @truncate(core.de >> 8);
    gb.e = @truncate(core.de);
    gb.h = @truncate(core.hl >> 8);
    gb.l = @truncate(core.hl);
    gb.ime = core.ime == 1;
    gb.ie = core.ie;
    gb.halted = core.state == .halted;
    gb.stopped = core.state == .stopped;

    gb.io_regs[IoReg.JOYP] = core.mm_regs[IoReg.JOYP];
    gb.timer.system_counter = @as(u16, @intCast(core.mm_regs[IoReg.DIV])) << 8;
    gb.io_regs[IoReg.TIMA] = core.mm_regs[IoReg.TIMA];
    gb.io_regs[IoReg.TMA] = core.mm_regs[IoReg.TMA];
    gb.io_regs[IoReg.TAC] = core.mm_regs[IoReg.TAC];
    gb.io_regs[IoReg.IF] = core.mm_regs[IoReg.IF];
    gb.apu.writeReg(ApuReg.NR52, core.mm_regs[IoReg.NR52]);
    gb.apu.writeReg(ApuReg.NR51, core.mm_regs[IoReg.NR51]);
    gb.apu.writeReg(ApuReg.NR50, core.mm_regs[IoReg.NR50]);

    gb.apu.writeReg(ApuReg.NR10, core.mm_regs[IoReg.NR10]);
    gb.apu.writeReg(ApuReg.NR11, core.mm_regs[IoReg.NR11]);
    gb.apu.writeReg(ApuReg.NR12, core.mm_regs[IoReg.NR12]);
    gb.apu.writeReg(ApuReg.NR13, core.mm_regs[IoReg.NR13]);
    gb.apu.writeReg(ApuReg.NR14, core.mm_regs[IoReg.NR14]);

    gb.apu.writeReg(ApuReg.NR21, core.mm_regs[IoReg.NR21]);
    gb.apu.writeReg(ApuReg.NR22, core.mm_regs[IoReg.NR22]);
    gb.apu.writeReg(ApuReg.NR23, core.mm_regs[IoReg.NR23]);
    gb.apu.writeReg(ApuReg.NR24, core.mm_regs[IoReg.NR24]);

    gb.apu.writeReg(ApuReg.NR30, core.mm_regs[IoReg.NR30]);
    gb.apu.writeReg(ApuReg.NR31, core.mm_regs[IoReg.NR31]);
    gb.apu.writeReg(ApuReg.NR32, core.mm_regs[IoReg.NR32]);
    gb.apu.writeReg(ApuReg.NR33, core.mm_regs[IoReg.NR33]);
    gb.apu.writeReg(ApuReg.NR34, core.mm_regs[IoReg.NR34]);

    gb.apu.writeReg(ApuReg.NR41, core.mm_regs[IoReg.NR41]);
    gb.apu.writeReg(ApuReg.NR42, core.mm_regs[IoReg.NR42]);
    gb.apu.writeReg(ApuReg.NR43, core.mm_regs[IoReg.NR43]);
    gb.apu.writeReg(ApuReg.NR44, core.mm_regs[IoReg.NR44]);

    for (0x30..0x40) |i| {
        gb.apu.writeWavRam(i - 0x30, core.mm_regs[i]);
    }

    gb.io_regs[IoReg.LCDC] = core.mm_regs[IoReg.LCDC];
    gb.io_regs[IoReg.STAT] = core.mm_regs[IoReg.STAT];
    gb.io_regs[IoReg.SCY] = core.mm_regs[IoReg.SCY];
    gb.io_regs[IoReg.SCX] = core.mm_regs[IoReg.SCX];
    // gb.io_regs[IoReg.LY] = core.mm_regs[IoReg.LY];
    // gb.io_regs[IoReg.LYC] = core.mm_regs[IoReg.LYC];
    gb.io_regs[IoReg.DMA] = core.mm_regs[IoReg.DMA];
    gb.io_regs[IoReg.OBP0] = core.mm_regs[IoReg.OBP0];
    gb.io_regs[IoReg.OBP1] = core.mm_regs[IoReg.OBP1];
    gb.io_regs[IoReg.WY] = core.mm_regs[IoReg.WY];
    gb.io_regs[IoReg.WX] = core.mm_regs[IoReg.WX];

    copyMemoryRegion(gb.wram, core.ram);
    copyMemoryRegion(gb.vram, core.vram);
    copyMemoryRegion(gb.cart.ram, core.mbc_ram);
    copyMemoryRegion(gb.oam, core.oam);
    copyMemoryRegion(gb.hram, core.hram);

    if (bess.mbc) |mbc| {
        for (mbc.regs) |reg| {
            gb.write(reg.addr, reg.val);
        }
    }
}

// Handles copying memory regions of possibly differing sizes.
// When the destination is larger than the source, the remaining space is set to 0s.
fn copyMemoryRegion(dst: []u8, src: []const u8) void {
    const copy_end = @min(dst.len, src.len);
    @memcpy(dst[0..copy_end], src[0..copy_end]);
    if (dst.len > src.len) {
        @memset(dst[copy_end..dst.len], 0);
    }
}

pub fn writeBess(gb: *Gb, writer: anytype) !void {
    var i: usize = 0;

    const ram_start = i;
    try writer.writeAll(gb.wram);
    i += gb.wram.len;

    const vram_start = i;
    try writer.writeAll(gb.vram);
    i += gb.vram.len;

    const mbc_ram_start = i;
    try writer.writeAll(gb.cart.ram);
    i += gb.cart.ram.len;

    const oam_start = i;
    try writer.writeAll(gb.oam);
    i += gb.oam.len;

    const hram_start = i;
    try writer.writeAll(gb.hram);
    i += gb.hram.len;

    const first_block_start = i;
    try BessName.write(writer);
    try BessInfo.write(writer, gb.cart.rom_title, gb.cart.global_checksum);
    try BessCore.write(
        writer,
        gb,
        ram_start,
        vram_start,
        mbc_ram_start,
        oam_start,
        hram_start,
    );
    try BessMbc.write(writer, gb);
    try BessEnd.write(writer);

    try writer.writeInt(u32, @truncate(first_block_start), .little);
    try writer.writeAll("BESS");
}
