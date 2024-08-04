const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const util = @import("../util.zig");

pub const Condition = enum {
    NZ,
    Z,
    NC,
    C,

    pub fn check(cond: Condition, gb: *Gb) bool {
        return switch (cond) {
            .NZ => !gb.zero,
            .Z => gb.zero,
            .NC => !gb.carry,
            .C => gb.carry,
        };
    }

    pub fn toStr(cond: Condition, buf: []u8) ![]u8 {
        return switch (cond) {
            .NZ => try std.fmt.bufPrint(buf, "nz", .{}),
            .Z => try std.fmt.bufPrint(buf, "z", .{}),
            .NC => try std.fmt.bufPrint(buf, "nc", .{}),
            .C => try std.fmt.bufPrint(buf, "c", .{}),
        };
    }
};

const Dst16Tag = enum {
    AF,
    BC,
    DE,
    HL,
    SP,
    Ind,
};

pub const Dst16 = union(Dst16Tag) {
    AF: void,
    BC: void,
    DE: void,
    HL: void,
    SP: void,
    Ind: u16,

    pub fn read(dst: Dst16, gb: *Gb) u16 {
        return switch (dst) {
            Dst16.AF => util.as16(gb.a, Gb.readFlags(gb)),
            Dst16.BC => util.as16(gb.b, gb.c),
            Dst16.DE => util.as16(gb.d, gb.e),
            Dst16.HL => util.as16(gb.h, gb.l),
            Dst16.SP => gb.sp,
            Dst16.Ind => |ind| Gb.read(gb, ind),
        };
    }

    pub fn write(dst: Dst16, val: u16, gb: *Gb) void {
        const valLow: u8 = @truncate(val);
        const valHigh: u8 = @truncate(val >> 8);

        switch (dst) {
            Dst16.AF => {
                gb.*.a = valHigh;
                Gb.writeFlags(gb, valLow);
            },
            Dst16.BC => {
                gb.*.b = valHigh;
                gb.*.c = valLow;
            },
            Dst16.DE => {
                gb.*.d = valHigh;
                gb.*.e = valLow;
            },
            Dst16.HL => {
                gb.*.h = valHigh;
                gb.*.l = valLow;
            },
            Dst16.SP => {
                gb.*.sp = val;
            },
            Dst16.Ind => |ind| {
                Gb.write(gb, ind, valLow);
                Gb.write(gb, ind + 1, valHigh);
            },
        }
    }

    pub fn toStr(dst: Dst16, buf: []u8) ![]u8 {
        return switch (dst) {
            Dst16.AF => try std.fmt.bufPrint(buf, "af", .{}),
            Dst16.BC => try std.fmt.bufPrint(buf, "bc", .{}),
            Dst16.DE => try std.fmt.bufPrint(buf, "de", .{}),
            Dst16.HL => try std.fmt.bufPrint(buf, "hl", .{}),
            Dst16.SP => try std.fmt.bufPrint(buf, "sp", .{}),
            Dst16.Ind => |ind| try std.fmt.bufPrint(buf, "${x:0>4}", .{ind}),
        };
    }

    pub fn size(dst: Dst16) u16 {
        return switch (dst) {
            Dst16.AF => 0,
            Dst16.BC => 0,
            Dst16.DE => 0,
            Dst16.HL => 0,
            Dst16.SP => 0,
            Dst16.Ind => 2,
        };
    }

    pub fn cycles(dst: Dst16) usize {
        return switch (dst) {
            Dst16.AF => 0,
            Dst16.BC => 0,
            Dst16.DE => 0,
            Dst16.HL => 0,
            Dst16.SP => 0,
            Dst16.Ind => 3,
        };
    }
};

const Src16Tag = enum {
    AF,
    BC,
    DE,
    HL,
    SP,
    SPOffset,
    Imm,
};

pub const Src16 = union(Src16Tag) {
    AF: void,
    BC: void,
    DE: void,
    HL: void,
    SP: void,
    SPOffset: u8,
    Imm: u16,

    pub fn read(src: Src16, gb: *const Gb) u16 {
        return switch (src) {
            Src16.AF => util.as16(gb.a, Gb.readFlags(gb)),
            Src16.BC => util.as16(gb.b, gb.c),
            Src16.DE => util.as16(gb.d, gb.e),
            Src16.HL => util.as16(gb.h, gb.l),
            Src16.SP => gb.sp,
            Src16.SPOffset => |offset| gb.sp + @as(u16, offset),
            Src16.Imm => |imm| imm,
        };
    }

    pub fn toStr(src: Src16, buf: []u8) ![]u8 {
        return switch (src) {
            Src16.AF => try std.fmt.bufPrint(buf, "af", .{}),
            Src16.BC => try std.fmt.bufPrint(buf, "bc", .{}),
            Src16.DE => try std.fmt.bufPrint(buf, "de", .{}),
            Src16.HL => try std.fmt.bufPrint(buf, "hl", .{}),
            Src16.SP => try std.fmt.bufPrint(buf, "sp", .{}),
            Src16.SPOffset => |offset| try std.fmt.bufPrint(buf, "sp + ${x:0>2}", .{offset}),
            Src16.Imm => |imm| try std.fmt.bufPrint(buf, "${x:0>2}", .{imm}),
        };
    }

    pub fn size(src: Src16) u16 {
        return switch (src) {
            Src16.AF => 0,
            Src16.BC => 0,
            Src16.DE => 0,
            Src16.HL => 0,
            Src16.SP => 0,
            Src16.SPOffset => 1,
            Src16.Imm => 2,
        };
    }

    pub fn cycles(src: Src16) usize {
        return switch (src) {
            Src16.AF => 0,
            Src16.BC => 0,
            Src16.DE => 0,
            Src16.HL => 0,
            Src16.SP => 0,
            Src16.SPOffset => 1,
            Src16.Imm => 2,
        };
    }
};

const Dst8Tag = enum {
    A,
    B,
    C,
    D,
    E,
    H,
    L,
    Ind,
    IndIoReg,
    IndC,
    IndBC,
    IndDE,
    IndHL,
    IndHLInc,
    IndHLDec,
};

pub const Dst8 = union(Dst8Tag) {
    A: void,
    B: void,
    C: void,
    D: void,
    E: void,
    H: void,
    L: void,
    Ind: u16,
    IndIoReg: u8,
    IndC: void,
    IndBC: void,
    IndDE: void,
    IndHL: void,
    IndHLInc: void,
    IndHLDec: void,

    pub fn read(dst: Dst8, gb: *Gb) u8 {
        const val = switch (dst) {
            Dst8.A => gb.a,
            Dst8.B => gb.b,
            Dst8.C => gb.c,
            Dst8.D => gb.d,
            Dst8.E => gb.e,
            Dst8.H => gb.h,
            Dst8.L => gb.l,
            Dst8.Ind => |ind| Gb.read(gb, ind),
            Dst8.IndIoReg => |ind| Gb.read(gb, 0xff00 + @as(u16, ind)),
            Dst8.IndC => Gb.read(gb, 0xff00 + @as(u16, gb.c)),
            Dst8.IndBC => Gb.read(gb, util.as16(gb.b, gb.c)),
            Dst8.IndDE => Gb.read(gb, util.as16(gb.d, gb.e)),
            Dst8.IndHL => Gb.read(gb, util.as16(gb.h, gb.l)),
            Dst8.IndHLInc => blk: {
                const x = Gb.read(gb, util.as16(gb.h, gb.l));

                const hl = util.as16(gb.h, gb.l);
                const hlInc = hl +% 1;
                gb.h = @truncate(hlInc >> 8);
                gb.l = @truncate(hlInc);

                break :blk x;
            },
            Dst8.IndHLDec => blk: {
                const x = Gb.read(gb, util.as16(gb.h, gb.l));
                decHL(gb);
                break :blk x;
            },
        };

        return val;
    }

    pub fn write(dst: Dst8, val: u8, gb: *Gb) void {
        switch (dst) {
            Dst8.A => gb.*.a = val,
            Dst8.B => gb.*.b = val,
            Dst8.C => gb.*.c = val,
            Dst8.D => gb.*.d = val,
            Dst8.E => gb.*.e = val,
            Dst8.H => gb.*.h = val,
            Dst8.L => gb.*.l = val,
            Dst8.Ind => |ind| Gb.write(gb, ind, val),
            Dst8.IndIoReg => |ind| Gb.write(gb, 0xff00 + @as(u16, ind), val),
            Dst8.IndC => Gb.write(gb, 0xff00 + @as(u16, gb.c), val),
            Dst8.IndBC => Gb.write(gb, util.as16(gb.b, gb.c), val),
            Dst8.IndDE => Gb.write(gb, util.as16(gb.d, gb.e), val),
            Dst8.IndHL => Gb.write(gb, util.as16(gb.h, gb.l), val),
            Dst8.IndHLInc => {
                Gb.write(gb, util.as16(gb.h, gb.l), val);
                incHL(gb);
            },
            Dst8.IndHLDec => {
                Gb.write(gb, util.as16(gb.h, gb.l), val);
                decHL(gb);
            },
        }
    }

    pub fn toStr(dst: Dst8, buf: []u8) ![]u8 {
        return switch (dst) {
            Dst8.A => try std.fmt.bufPrint(buf, "a", .{}),
            Dst8.B => try std.fmt.bufPrint(buf, "b", .{}),
            Dst8.C => try std.fmt.bufPrint(buf, "c", .{}),
            Dst8.D => try std.fmt.bufPrint(buf, "d", .{}),
            Dst8.E => try std.fmt.bufPrint(buf, "e", .{}),
            Dst8.H => try std.fmt.bufPrint(buf, "h", .{}),
            Dst8.L => try std.fmt.bufPrint(buf, "l", .{}),
            Dst8.Ind => |ind| try std.fmt.bufPrint(buf, "[${x:0>4}]", .{ind}),
            Dst8.IndIoReg => |ind| try std.fmt.bufPrint(buf, "[${x:0>2}]", .{ind}),
            Dst8.IndC => try std.fmt.bufPrint(buf, "[c]", .{}),
            Dst8.IndBC => try std.fmt.bufPrint(buf, "[bc]", .{}),
            Dst8.IndDE => try std.fmt.bufPrint(buf, "[de]", .{}),
            Dst8.IndHL => try std.fmt.bufPrint(buf, "[hl]", .{}),
            Dst8.IndHLInc => try std.fmt.bufPrint(buf, "[hli]", .{}),
            Dst8.IndHLDec => try std.fmt.bufPrint(buf, "[hld]", .{}),
        };
    }

    pub fn size(dst: Dst8) u16 {
        return switch (dst) {
            Dst8.A => 0,
            Dst8.B => 0,
            Dst8.C => 0,
            Dst8.D => 0,
            Dst8.E => 0,
            Dst8.H => 0,
            Dst8.L => 0,
            Dst8.Ind => 2,
            Dst8.IndIoReg => 1,
            Dst8.IndC => 0,
            Dst8.IndBC => 0,
            Dst8.IndDE => 0,
            Dst8.IndHL => 0,
            Dst8.IndHLInc => 0,
            Dst8.IndHLDec => 0,
        };
    }

    pub fn cycles(dst: Dst8) usize {
        return switch (dst) {
            Dst8.A => 0,
            Dst8.B => 0,
            Dst8.C => 0,
            Dst8.D => 0,
            Dst8.E => 0,
            Dst8.H => 0,
            Dst8.L => 0,
            Dst8.Ind => 2,
            Dst8.IndIoReg => 2,
            Dst8.IndC => 1,
            Dst8.IndBC => 1,
            Dst8.IndDE => 1,
            Dst8.IndHL => 1,
            Dst8.IndHLInc => 1,
            Dst8.IndHLDec => 1,
        };
    }
};

const Src8Tag = enum {
    A,
    B,
    C,
    D,
    E,
    H,
    L,
    Ind,
    IndIoReg,
    IndC,
    IndBC,
    IndDE,
    IndHL,
    IndHLInc,
    IndHLDec,
    Imm,
};

pub const Src8 = union(Src8Tag) {
    A: void,
    B: void,
    C: void,
    D: void,
    E: void,
    H: void,
    L: void,
    Ind: u16,
    IndIoReg: u8,
    IndC: void,
    IndBC: void,
    IndDE: void,
    IndHL: void,
    IndHLInc: void,
    IndHLDec: void,
    Imm: u8,

    pub fn read(src: Src8, gb: *Gb) u8 {
        return switch (src) {
            Src8.A => gb.a,
            Src8.B => gb.b,
            Src8.C => gb.c,
            Src8.D => gb.d,
            Src8.E => gb.e,
            Src8.H => gb.h,
            Src8.L => gb.l,
            Src8.Ind => |ind| Gb.read(gb, ind),
            Src8.IndIoReg => |ind| Gb.read(gb, 0xff00 + @as(u16, ind)),
            Src8.IndC => Gb.read(gb, 0xff00 + @as(u16, gb.c)),
            Src8.IndBC => Gb.read(gb, util.as16(gb.b, gb.c)),
            Src8.IndDE => Gb.read(gb, util.as16(gb.d, gb.e)),
            Src8.IndHL => Gb.read(gb, util.as16(gb.h, gb.l)),
            Src8.IndHLInc => blk: {
                const x = Gb.read(gb, util.as16(gb.h, gb.l));
                incHL(gb);
                break :blk x;
            },
            Src8.IndHLDec => blk: {
                const x = Gb.read(gb, util.as16(gb.h, gb.l));
                decHL(gb);
                break :blk x;
            },
            Src8.Imm => |imm| imm,
        };
    }

    pub fn toStr(src: Src8, buf: []u8) ![]u8 {
        return switch (src) {
            Src8.A => try std.fmt.bufPrint(buf, "a", .{}),
            Src8.B => try std.fmt.bufPrint(buf, "b", .{}),
            Src8.C => try std.fmt.bufPrint(buf, "c", .{}),
            Src8.D => try std.fmt.bufPrint(buf, "d", .{}),
            Src8.E => try std.fmt.bufPrint(buf, "e", .{}),
            Src8.H => try std.fmt.bufPrint(buf, "h", .{}),
            Src8.L => try std.fmt.bufPrint(buf, "l", .{}),
            Src8.Ind => |ind| try std.fmt.bufPrint(buf, "[${x:0>4}]", .{ind}),
            Src8.IndIoReg => |ind| try std.fmt.bufPrint(buf, "[${x:0>2}]", .{ind}),
            Src8.IndC => try std.fmt.bufPrint(buf, "[c]", .{}),
            Src8.IndBC => try std.fmt.bufPrint(buf, "[bc]", .{}),
            Src8.IndDE => try std.fmt.bufPrint(buf, "[de]", .{}),
            Src8.IndHL => try std.fmt.bufPrint(buf, "[hl]", .{}),
            Src8.IndHLInc => try std.fmt.bufPrint(buf, "[hli]", .{}),
            Src8.IndHLDec => try std.fmt.bufPrint(buf, "[hld]", .{}),
            Src8.Imm => |imm| try std.fmt.bufPrint(buf, "${x:0>2}", .{imm}),
        };
    }

    pub fn size(src: Src8) u16 {
        return switch (src) {
            Src8.A => 0,
            Src8.B => 0,
            Src8.C => 0,
            Src8.D => 0,
            Src8.E => 0,
            Src8.H => 0,
            Src8.L => 0,
            Src8.Ind => 2,
            Src8.IndIoReg => 1,
            Src8.IndC => 0,
            Src8.IndBC => 0,
            Src8.IndDE => 0,
            Src8.IndHL => 0,
            Src8.IndHLInc => 0,
            Src8.IndHLDec => 0,
            Src8.Imm => 1,
        };
    }

    pub fn cycles(src: Src8) usize {
        return switch (src) {
            Src8.A => 0,
            Src8.B => 0,
            Src8.C => 0,
            Src8.D => 0,
            Src8.E => 0,
            Src8.H => 0,
            Src8.L => 0,
            Src8.Ind => 2,
            Src8.IndIoReg => 2,
            Src8.IndC => 1,
            Src8.IndBC => 1,
            Src8.IndDE => 1,
            Src8.IndHL => 1,
            Src8.IndHLInc => 1,
            Src8.IndHLDec => 1,
            Src8.Imm => 1,
        };
    }
};

fn incHL(gb: *Gb) void {
    const hl = util.as16(gb.h, gb.l);
    const hlInc = hl +% 1;
    gb.h = @truncate(hlInc >> 8);
    gb.l = @truncate(hlInc);
}

fn decHL(gb: *Gb) void {
    const hl = util.as16(gb.h, gb.l);
    const hlDec = hl -% 1;
    gb.h = @truncate(hlDec >> 8);
    gb.l = @truncate(hlDec);
}
