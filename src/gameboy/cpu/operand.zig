const std = @import("std");
const util = @import("../../util.zig");
const Gb = @import("../gameboy.zig").Gb;

pub const Cond = enum {
    NZ,
    Z,
    NC,
    C,

    pub fn decode(val: u2) Cond {
        return switch (val) {
            0 => .NZ,
            1 => .Z,
            2 => .NC,
            3 => .C,
        };
    }

    pub fn check(cond: Cond, gb: *Gb) bool {
        return switch (cond) {
            .NZ => !gb.zero,
            .Z => gb.zero,
            .NC => !gb.carry,
            .C => gb.carry,
        };
    }

    pub fn toStr(cond: Cond, buf: []u8) ![]u8 {
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

    pub fn decode(val: u2) Dst16 {
        return switch (val) {
            0 => Dst16.BC,
            1 => Dst16.DE,
            2 => Dst16.HL,
            3 => Dst16.SP,
        };
    }

    pub fn read(dst: Dst16, gb: *Gb) u16 {
        return switch (dst) {
            .AF => util.as16(gb.a, gb.readFlags()),
            .BC => util.as16(gb.b, gb.c),
            .DE => util.as16(gb.d, gb.e),
            .HL => util.as16(gb.h, gb.l),
            .SP => gb.sp,
            .Ind => |ind| gb.read(ind),
        };
    }

    pub fn write(dst: Dst16, val: u16, gb: *Gb) void {
        const valLow: u8 = @truncate(val);
        const valHigh: u8 = @truncate(val >> 8);

        switch (dst) {
            .AF => {
                gb.a = valHigh;
                gb.writeFlags(valLow);
            },
            .BC => {
                gb.b = valHigh;
                gb.c = valLow;
            },
            .DE => {
                gb.d = valHigh;
                gb.e = valLow;
            },
            .HL => {
                gb.h = valHigh;
                gb.l = valLow;
            },
            .SP => {
                gb.sp = val;
            },
            .Ind => |ind| {
                gb.write(ind, valLow);
                gb.write(ind + 1, valHigh);
            },
        }
    }

    pub fn toStr(dst: Dst16, buf: []u8) ![]u8 {
        return switch (dst) {
            .AF => try std.fmt.bufPrint(buf, "af", .{}),
            .BC => try std.fmt.bufPrint(buf, "bc", .{}),
            .DE => try std.fmt.bufPrint(buf, "de", .{}),
            .HL => try std.fmt.bufPrint(buf, "hl", .{}),
            .SP => try std.fmt.bufPrint(buf, "sp", .{}),
            .Ind => |ind| try std.fmt.bufPrint(buf, "${x:0>4}", .{ind}),
        };
    }

    pub fn size(dst: Dst16) u16 {
        return switch (dst) {
            .AF => 0,
            .BC => 0,
            .DE => 0,
            .HL => 0,
            .SP => 0,
            .Ind => 2,
        };
    }

    pub fn cycles(dst: Dst16) usize {
        return switch (dst) {
            .AF => 0,
            .BC => 0,
            .DE => 0,
            .HL => 0,
            .SP => 0,
            .Ind => 3,
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

    pub fn decode(val: u2) Src16 {
        return switch (val) {
            0 => Src16.BC,
            1 => Src16.DE,
            2 => Src16.HL,
            3 => Src16.SP,
        };
    }

    pub fn read(src: Src16, gb: *const Gb) u16 {
        return switch (src) {
            Src16.AF => util.as16(gb.a, Gb.readFlags(gb)),
            Src16.BC => util.as16(gb.b, gb.c),
            Src16.DE => util.as16(gb.d, gb.e),
            Src16.HL => util.as16(gb.h, gb.l),
            Src16.SP => gb.sp,
            Src16.SPOffset => |offset| gb.sp +% @as(u16, offset),
            Src16.Imm => |imm| imm,
        };
    }

    pub fn readUpper(src: Src16, gb: *const Gb) u8 {
        return switch (src) {
            Src16.AF => gb.a,
            Src16.BC => gb.b,
            Src16.DE => gb.d,
            Src16.HL => gb.h,
            Src16.SP => @truncate(gb.sp >> 8),
            Src16.SPOffset => |offset| @truncate((gb.sp +% @as(u16, offset)) >> 8),
            Src16.Imm => |imm| @truncate(imm >> 8),
        };
    }

    pub fn readLower(src: Src16, gb: *const Gb) u8 {
        return switch (src) {
            Src16.AF => gb.readFlags(),
            Src16.BC => gb.c,
            Src16.DE => gb.e,
            Src16.HL => gb.l,
            Src16.SP => @truncate(gb.sp),
            Src16.SPOffset => |offset| @truncate(gb.sp +% @as(u16, offset)),
            Src16.Imm => |imm| @truncate(imm),
        };
    }

    pub fn toStr(src: Src16, buf: []u8) ![]u8 {
        return switch (src) {
            Src16.AF => try std.fmt.bufPrint(buf, "af", .{}),
            Src16.BC => try std.fmt.bufPrint(buf, "bc", .{}),
            Src16.DE => try std.fmt.bufPrint(buf, "de", .{}),
            Src16.HL => try std.fmt.bufPrint(buf, "hl", .{}),
            Src16.SP => try std.fmt.bufPrint(buf, "sp", .{}),
            Src16.SPOffset => |offset| blk: {
                const positive = offset & 0b1000_0000 == 0;
                const operator = if (positive) "+" else "-";
                const value = if (positive) offset else @as(u7, @truncate(~offset + 1));
                break :blk try std.fmt.bufPrint(buf, "sp {s} {}", .{ operator, value });
            },
            Src16.Imm => |imm| try std.fmt.bufPrint(buf, "${x:0>4}", .{imm}),
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

    pub fn decode(val: u3) Dst8 {
        return switch (val) {
            0 => Dst8.B,
            1 => Dst8.C,
            2 => Dst8.D,
            3 => Dst8.E,
            4 => Dst8.H,
            5 => Dst8.L,
            6 => Dst8.IndHL,
            7 => Dst8.A,
        };
    }

    pub fn decodeIndLoad(val: u2) Dst8 {
        return switch (val) {
            0 => Dst8.IndBC,
            1 => Dst8.IndDE,
            2 => Dst8.IndHLInc,
            3 => Dst8.IndHLDec,
        };
    }

    pub fn read(dst: Dst8, gb: *Gb) u8 {
        return switch (dst) {
            Dst8.A => gb.a,
            Dst8.B => gb.b,
            Dst8.C => gb.c,
            Dst8.D => gb.d,
            Dst8.E => gb.e,
            Dst8.H => gb.h,
            Dst8.L => gb.l,
            Dst8.Ind => |ind| gb.read(ind),
            Dst8.IndIoReg => |ind| gb.read(0xff00 + @as(u16, ind)),
            Dst8.IndC => gb.read(0xff00 + @as(u16, gb.c)),
            Dst8.IndBC => gb.read(util.as16(gb.b, gb.c)),
            Dst8.IndDE => gb.read(util.as16(gb.d, gb.e)),
            Dst8.IndHL => gb.read(util.as16(gb.h, gb.l)),
            Dst8.IndHLInc => blk: {
                const x = gb.read(util.as16(gb.h, gb.l));
                incHL(gb);
                break :blk x;
            },
            Dst8.IndHLDec => blk: {
                const x = gb.read(util.as16(gb.h, gb.l));
                decHL(gb);
                break :blk x;
            },
        };
    }

    pub fn write(dst: Dst8, val: u8, gb: *Gb) void {
        switch (dst) {
            Dst8.A => gb.a = val,
            Dst8.B => gb.b = val,
            Dst8.C => gb.c = val,
            Dst8.D => gb.d = val,
            Dst8.E => gb.e = val,
            Dst8.H => gb.h = val,
            Dst8.L => gb.l = val,
            Dst8.Ind => |ind| gb.write(ind, val),
            Dst8.IndIoReg => |ind| gb.write(0xff00 + @as(u16, ind), val),
            Dst8.IndC => gb.write(0xff00 + @as(u16, gb.c), val),
            Dst8.IndBC => gb.write(util.as16(gb.b, gb.c), val),
            Dst8.IndDE => gb.write(util.as16(gb.d, gb.e), val),
            Dst8.IndHL => gb.write(util.as16(gb.h, gb.l), val),
            Dst8.IndHLInc => {
                gb.write(util.as16(gb.h, gb.l), val);
                incHL(gb);
            },
            Dst8.IndHLDec => {
                gb.write(util.as16(gb.h, gb.l), val);
                decHL(gb);
            },
        }
    }

    pub fn getPtr(comptime dst: Dst8, gb: *Gb) *u8 {
        return switch (dst) {
            .A => &gb.a,
            .B => &gb.b,
            .C => &gb.c,
            .D => &gb.d,
            .E => &gb.e,
            .H => &gb.h,
            .L => &gb.l,
            else => @compileError("getPtr() called with invalid Dst8"),
        };
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

    pub fn decode(val: u3) Src8 {
        return switch (val) {
            0 => Src8.B,
            1 => Src8.C,
            2 => Src8.D,
            3 => Src8.E,
            4 => Src8.H,
            5 => Src8.L,
            6 => Src8.IndHL,
            7 => Src8.A,
        };
    }

    pub fn read(src: Src8, gb: *Gb) u8 {
        return switch (src) {
            Src8.A => gb.a,
            Src8.B => gb.b,
            Src8.C => gb.c,
            Src8.D => gb.d,
            Src8.E => gb.e,
            Src8.H => gb.h,
            Src8.L => gb.l,
            Src8.Ind => |ind| gb.read(ind),
            Src8.IndIoReg => |ind| gb.read(0xff00 + @as(u16, ind)),
            Src8.IndC => gb.read(0xff00 + @as(u16, gb.c)),
            Src8.IndBC => gb.read(util.as16(gb.b, gb.c)),
            Src8.IndDE => gb.read(util.as16(gb.d, gb.e)),
            Src8.IndHL => gb.read(util.as16(gb.h, gb.l)),
            Src8.IndHLInc => blk: {
                const x = gb.read(util.as16(gb.h, gb.l));
                incHL(gb);
                break :blk x;
            },
            Src8.IndHLDec => blk: {
                const x = gb.read(util.as16(gb.h, gb.l));
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
