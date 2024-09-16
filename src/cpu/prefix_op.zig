const Dst8 = @import("operand.zig").Dst8;

const PrefixOpTag = enum {
    rlc,
    rrc,
    rl,
    rr,
    sla,
    sra,
    swap,
    srl,
    bit,
    res,
    set,
};

pub const PrefixOp = union(PrefixOpTag) {
    rlc: void,
    rrc: void,
    rl: void,
    rr: void,
    sla: void,
    sra: void,
    swap: void,
    srl: void,
    bit: u3,
    res: u3,
    set: u3,

    pub fn execute(
        op: PrefixOp,
        input: u8,
        zero: *bool,
        negative: *bool,
        half_carry: *bool,
        carry: *bool,
    ) u8 {
        // Compute result.
        const result = switch (op) {
            .rlc => rotateLeft(input, carry),
            .rrc => rotateRight(input, carry),
            .rl => rotateLeftThroughCarry(input, carry),
            .rr => rotateRightThroughCarry(input, carry),
            .sla => shiftLeft(input, carry),
            .sra => shiftRightArithmetically(input, carry),
            .swap => swap(input, carry),
            .srl => shiftRightLogically(input, carry),
            .bit => |bit_index| checkBit(input, bit_index),
            .res => |bit_index| resetBit(input, bit_index),
            .set => |bit_index| setBit(input, bit_index),
        };

        // Set flags.
        switch (op) {
            .res, .set => {},
            else => {
                zero.* = result == 0;
                negative.* = false;
                half_carry.* = op == .bit;
            },
        }

        return result;
    }
};

fn rotateLeft(input: u8, carry: *bool) u8 {
    const bit_7 = (input & 0b1000_0000) >> 7;
    carry.* = bit_7 == 1;
    return (input << 1) | bit_7;
}

fn rotateRight(input: u8, carry: *bool) u8 {
    const bit_0 = (input & 0b0000_0001) << 7;
    carry.* = bit_0 > 0;
    return (input >> 1) | bit_0;
}

fn rotateLeftThroughCarry(input: u8, carry: *bool) u8 {
    const bit_7 = (input & 0b1000_0000) >> 7;
    const carry_bit: u8 = if (carry.*) 1 else 0;
    carry.* = bit_7 == 1;
    return (input << 1) | carry_bit;
}

fn rotateRightThroughCarry(input: u8, carry: *bool) u8 {
    const bit_0 = (input & 0b0000_0001) << 7;
    const carry_bit = @as(u8, if (carry.*) 1 else 0) << 7;
    carry.* = bit_0 > 0;
    return (input >> 1) | carry_bit;
}

fn shiftLeft(input: u8, carry: *bool) u8 {
    const bit_7 = (input & 0b1000_0000) >> 7;
    carry.* = bit_7 == 1;
    return input << 1;
}

fn shiftRightArithmetically(input: u8, carry: *bool) u8 {
    const bit_7 = input & 0b1000_0000;
    const bit_0 = input & 0b0000_0001;
    carry.* = bit_0 == 1;
    return (input >> 1) | bit_7;
}

fn swap(input: u8, carry: *bool) u8 {
    const low = input & 0b0000_1111;
    const high = input & 0b1111_0000;
    carry.* = false;
    return (low << 4) | (high >> 4);
}

fn shiftRightLogically(input: u8, carry: *bool) u8 {
    const bit_0 = input & 0b0000_0001;
    carry.* = bit_0 == 1;
    return input >> 1;
}

fn checkBit(input: u8, bit_index: u3) u8 {
    return (input >> bit_index) & 0b0000_0001;
}

fn resetBit(input: u8, bit_index: u3) u8 {
    const mask = ~(@as(u8, 1) << bit_index);
    return input & mask;
}

fn setBit(input: u8, bit_index: u3) u8 {
    const mask = @as(u8, 1) << bit_index;
    return input | mask;
}
