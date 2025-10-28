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
