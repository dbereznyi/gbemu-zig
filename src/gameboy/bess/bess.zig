const std = @import("std");
const MbcReg = @import("../cart.zig").MbcReg;

inline fn u32LE(bytes: []const u8) u32 {
    return std.mem.readVarInt(u32, bytes, .little);
}

fn readMemoryRegion(reader: *std.Io.Reader, data: []const u8) ![]const u8 {
    const size: usize = try reader.takeInt(u32, .little);
    const start: usize = try reader.takeInt(u32, .little);
    if (start + size > data.len) {
        return error.MemoryRegionSizeTooLarge;
    }

    return data[start .. start + size];
}

pub const Bess = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    data: []const u8,
    name: ?BessName,
    info: ?BessInfo,
    core: BessCore,
    mbc: ?BessMbc,
    rtc: ?BessRtc,

    /// Parses BESS-format savestate data. Takes ownership of `data`.
    pub fn init(alloc: std.mem.Allocator, data: []const u8) !Bess {
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

        var reader = std.Io.Reader.fixed(data[first_block_start..]);
        while (reader.bufferedLen() > 0) {
            const block = try BessBlock.parse(&reader, alloc, data);

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
                .alloc = alloc,
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

    pub fn deinit(self: *const Self) void {
        if (self.mbc) |mbc| mbc.deinit(self.alloc);
        self.alloc.free(self.data);
    }

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        if (self.name) |name| try name.print(writer);
        if (self.info) |info| try info.print(writer);
        try self.core.print(writer);
        if (self.mbc) |mbc| try mbc.print(writer);
        if (self.rtc) |rtc| try rtc.print(writer);
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

    pub fn parse(
        reader: *std.Io.Reader,
        alloc: std.mem.Allocator,
        data: []const u8,
    ) !BessBlock {
        const block_name = try reader.take(4);
        const block_len: usize = try reader.takeInt(u32, .little);

        if (std.mem.eql(u8, block_name, "NAME")) {
            return .{ .name = try BessName.init(reader, block_len) };
        }
        if (std.mem.eql(u8, block_name, "INFO")) {
            return .{ .info = try BessInfo.init(reader) };
        }
        if (std.mem.eql(u8, block_name, "CORE")) {
            return .{ .core = try BessCore.init(reader, data) };
        }
        if (std.mem.eql(u8, block_name, "MBC ")) {
            return .{ .mbc = try BessMbc.init(reader, alloc, block_len) };
        }
        if (std.mem.eql(u8, block_name, "RTC ")) {
            return .{ .rtc = try BessRtc.init(reader) };
        }
        if (std.mem.eql(u8, block_name, "END ")) {
            return .end;
        }

        return .{ .unknown = block_len };
    }
};

const BessName = struct {
    const Self = @This();

    name: []const u8,

    pub fn init(reader: *std.Io.Reader, len: usize) !BessName {
        return .{
            .name = try reader.take(len),
        };
    }

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("NAME\n", .{});
        try writer.print("  name: {s}\n", .{self.name});
    }
};

const BessInfo = struct {
    const Self = @This();

    title: []const u8,
    checksum: u16,

    pub fn init(reader: *std.Io.Reader) !BessInfo {
        const title = try reader.take(16);
        const checksum = try reader.takeInt(u16, .little);

        return .{
            .title = title,
            .checksum = checksum,
        };
    }

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("INFO\n", .{});
        try writer.print("  title: {s}\n", .{self.title});
        try writer.print("  checksum: ${x:0>2}\n", .{self.checksum});
    }
};

const BessCore = struct {
    const Self = @This();

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

    pub fn init(reader: *std.Io.Reader, data: []const u8) !BessCore {
        const major = try reader.takeInt(u16, .little);
        const minor = try reader.takeInt(u16, .little);
        if (major != 1 or minor != 1) {
            return error.UnsupportedVersion;
        }

        const model = try reader.take(4);
        const pc = try reader.takeInt(u16, .little);
        const af = try reader.takeInt(u16, .little);
        const bc = try reader.takeInt(u16, .little);
        const de = try reader.takeInt(u16, .little);
        const hl = try reader.takeInt(u16, .little);
        const sp = try reader.takeInt(u16, .little);
        const ime: u1 = if (try reader.takeByte() == 0) 0 else 1;
        const ie = try reader.takeByte();
        var state: BessCore.ExecutionState = undefined;
        switch (try reader.takeByte()) {
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

        reader.toss(1); // Skip reserved byte

        const mm_regs = try reader.take(128);

        const ram = try readMemoryRegion(reader, data);
        const vram = try readMemoryRegion(reader, data);
        const mbc_ram = try readMemoryRegion(reader, data);
        const oam = try readMemoryRegion(reader, data);
        const hram = try readMemoryRegion(reader, data);

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

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("CORE\n", .{});
        try writer.print("  major: {} minor: {}\n", .{ self.major, self.minor });
        try writer.print("  model: {s}\n", .{self.model});
        try writer.print("  PC: ${x:0>4} SP: ${x:0>4}\n", .{ self.pc, self.sp });
        try writer.print("  AF: ${x:0>4} BC: ${x:0>4}\n", .{ self.af, self.bc });
        try writer.print("  DE: ${x:0>4} HL: ${x:0>4}\n", .{ self.de, self.hl });
        try writer.print("  IME: {} IE: ${x:0>2}\n", .{ self.ime, self.ie });
        try writer.print("  state: {}\n", .{self.state});
        try writer.print("  wram size: {} vram size: {} sram size: {}\n", .{ self.ram.len, self.vram.len, self.mbc_ram.len });
        try writer.print("  oam size: {} hram size: {}\n", .{ self.oam.len, self.hram.len });
    }
};

const BessMbc = struct {
    const Self = @This();

    regs: []MbcReg,

    pub fn init(reader: *std.Io.Reader, alloc: std.mem.Allocator, len: usize) !BessMbc {
        const regs = try alloc.alloc(MbcReg, len / 3);
        var regs_ix: usize = 0;
        while (regs_ix < len / 3) {
            const addr = try reader.takeInt(u16, .little);
            const val = try reader.takeByte();

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

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("MBC\n", .{});
        for (self.regs) |reg| {
            try writer.print("  ${x:0>4}: ${x:0>2}\n", .{ reg.addr, reg.val });
        }
    }
};

const BessRtc = struct {
    const Self = @This();

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

    pub fn init(reader: *std.Io.Reader) !BessRtc {
        const seconds = try reader.takeByte();
        const minutes = try reader.takeByte();
        const hours = try reader.takeByte();
        const days = try reader.takeByte();
        const overflow = try reader.takeByte();
        const latched_seconds = try reader.takeByte();
        const latched_minutes = try reader.takeByte();
        const latched_hours = try reader.takeByte();
        const latched_days = try reader.takeByte();
        const latched_overflow = try reader.takeByte();
        const unix_timestamp = try reader.takeInt(u64, .little);

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

    pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("RTC\n", .{});
        try writer.print("  Seconds : ${x:0>2} Seconds  (latched): ${x:0>2}\n", .{ self.seconds, self.latched_seconds });
        try writer.print("  Minutes : ${x:0>2} Minutes  (latched): ${x:0>2}\n", .{ self.minutes, self.latched_minutes });
        try writer.print("  Hours   : ${x:0>2} Hours    (latched): ${x:0>2}\n", .{ self.hours, self.latched_hours });
        try writer.print("  Days    : ${x:0>2} Days     (latched): ${x:0>2}\n", .{ self.days, self.latched_days });
        try writer.print("  Overflow: ${x:0>2} Overflow (latched): ${x:0>2}\n", .{ self.overflow, self.latched_overflow });
        try writer.print("  Unix timestamp: {}\n", .{self.unix_timestamp});
    }
};
