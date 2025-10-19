const std = @import("std");

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
    data: []const u8,
    name: ?BessName,
    info: ?BessInfo,
    core: BessCore,
    mbc: ?BessMbc,
    rtc: ?BessRtc,

    pub fn deinit(self: *const Bess, alloc: std.mem.Allocator) void {
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
};

const BessMbc = struct {
    const MbcReg = struct {
        addr: u16,
        val: u8,
    };
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

    std.debug.print("first_block_start = {}\n", .{first_block_start});

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
