const std = @import("std");
const expect = std.testing.expect;

pub const AluOp = enum {
    add,
    adc,
    sub,
    sbc,
    and_,
    xor,
    or_,
    cp,

    pub fn execute(
        self: AluOp,
        dst: *u8,
        src: u8,
        zero: *bool,
        negative: *bool,
        halfCarry: *bool,
        carry: *bool,
    ) void {
        switch (self) {
            .add => {
                const x = dst.*;
                const y = src;
                const result = x +% y;

                zero.* = result == 0;
                negative.* = false;
                halfCarry.* = checkHalfCarry(x, y);
                carry.* = checkCarry(x, y);

                dst.* = result;
            },
            .adc => {
                const sub_result = @addWithOverflow(src, if (carry.*) @as(u8, 1) else @as(u8, 0));
                const result = @addWithOverflow(dst.*, sub_result[0]);

                zero.* = result[0] == 0;
                negative.* = false;
                halfCarry.* = ((dst.* & 0xf) + (src & 0xf) +% (if (carry.*) @as(u8, 1) else @as(u8, 0))) & 0x10 == 0x10;
                carry.* = result[1] == 1 or sub_result[1] == 1;

                dst.* = result[0];
            },
            .sub => {
                const result = @subWithOverflow(dst.*, src);

                zero.* = result[0] == 0;
                negative.* = true;
                halfCarry.* = ((dst.* & 0xf) -% (src & 0xf)) & 0x10 == 0x10;
                carry.* = result[1] == 1;

                dst.* = result[0];
            },
            .sbc => {
                const sub_result = @addWithOverflow(src, if (carry.*) @as(u8, 1) else @as(u8, 0));
                const result = @subWithOverflow(dst.*, sub_result[0]);

                zero.* = result[0] == 0;
                negative.* = true;
                halfCarry.* = ((dst.* & 0xf) -% (src & 0xf) -% (if (carry.*) @as(u8, 1) else @as(u8, 0))) & 0x10 == 0x10;
                carry.* = result[1] == 1 or sub_result[1] == 1;

                dst.* = result[0];
            },
            .and_ => {
                const x = dst.*;
                const y = src;
                const result = x & y;

                zero.* = result == 0;
                negative.* = false;
                halfCarry.* = true;
                carry.* = false;

                dst.* = result;
            },
            .xor => {
                const x = dst.*;
                const y = src;
                const result = x ^ y;

                zero.* = result == 0;
                negative.* = false;
                halfCarry.* = false;
                carry.* = false;

                dst.* = result;
            },
            .or_ => {
                const x = dst.*;
                const y = src;
                const result = x | y;

                zero.* = result == 0;
                negative.* = false;
                halfCarry.* = false;
                carry.* = false;

                dst.* = result;
            },
            .cp => {
                const result = @subWithOverflow(dst.*, src);

                zero.* = result[0] == 0;
                negative.* = true;
                halfCarry.* = ((dst.* & 0xf) -% (src & 0xf)) & 0x10 == 0x10;
                carry.* = result[1] == 1;
            },
        }
    }

    pub fn decode(val: u3) AluOp {
        return switch (val) {
            0 => .add,
            1 => .adc,
            2 => .sub,
            3 => .sbc,
            4 => .and_,
            5 => .xor,
            6 => .or_,
            7 => .cp,
        };
    }
};

pub fn checkCarry(x: u8, y: u8) bool {
    return @addWithOverflow(x, y)[1] == 1;
}

pub fn checkHalfCarry(x: u8, y: u8) bool {
    return (((x & 0x0f) + (y & 0x0f)) & 0x10) == 0x10;
}

test "cp" {
    // TODO fix this up to do proper edge-case testing

    const TestCase = struct {
        a: u8,
        src: u8,
        z: bool,
        n: bool,
        h: bool,
        c: bool,
    };
    const cases = [_]TestCase{
        .{ .a = 0x3c, .src = 0x2f, .z = false, .n = true, .h = true, .c = false },
        .{ .a = 0x3c, .src = 0x3c, .z = true, .n = true, .h = false, .c = false },
        .{ .a = 0x3c, .src = 0x40, .z = false, .n = true, .h = false, .c = true },
    };

    for (cases) |case| {
        var a: u8 = case.a;
        var z = false;
        var n = false;
        var h = false;
        var c = false;

        AluOp.execute(.cp, &a, case.src, &z, &n, &h, &c);

        std.debug.print("{}\n", .{case});

        try expect(a == case.a);
        try expect(z == case.z);
        try expect(n == case.n);
        try expect(h == case.h);
        try expect(c == case.c);
    }

    const vals = [_]u8{ 0x00, 0x01, 0x0f, 0x10, 0x1f, 0x7f, 0x80, 0xf0, 0xff };

    for (vals) |dst| {
        for (vals) |src| {
            for ([_]bool{ false, true }) |carry| {
                var a = dst;
                var z = false;
                var n = false;
                var h = false;
                var c = carry;

                AluOp.execute(.sbc, &a, src, &z, &n, &h, &c);

                if (true) {
                    const z_: u8 = if (z) 0b1000_0000 else 0;
                    const n_: u8 = if (n) 0b0100_0000 else 0;
                    const h_: u8 = if (h) 0b0010_0000 else 0;
                    const c_: u8 = if (c) 0b0001_0000 else 0;

                    const f = z_ | n_ | h_ | c_;

                    std.debug.print("{x:0>2},{x:0>2}\n", .{ a, f });
                }
            }
        }
    }
}
