const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Instr = @import("instruction.zig").Instr;
const Condition = @import("operand.zig").Condition;
const Src8 = @import("operand.zig").Src8;
const Dst8 = @import("operand.zig").Dst8;
const Src16 = @import("operand.zig").Src16;
const Dst16 = @import("operand.zig").Dst16;
const util = @import("../util.zig");

pub fn decodeInstrAt(pc: u16, gb: *Gb) Instr {
    const opcode = gb.read(pc);

    const n8 = gb.read(pc + 1);
    const x: u16 = n8;
    const y: u16 = gb.read(pc + 2);
    const n16 = (y << 8) | x;

    const opcodeReg: Src8 = switch (@as(u3, @truncate(opcode & 0b0000_0111))) {
        0 => Src8.B,
        1 => Src8.C,
        2 => Src8.D,
        3 => Src8.E,
        4 => Src8.H,
        5 => Src8.L,
        6 => Src8.IndHL,
        7 => Src8.A,
    };

    const opcodeRegCb: Dst8 = switch (@as(u3, @truncate(n8 & 0b0000_0111))) {
        0 => Dst8.B,
        1 => Dst8.C,
        2 => Dst8.D,
        3 => Dst8.E,
        4 => Dst8.H,
        5 => Dst8.L,
        6 => Dst8.IndHL,
        7 => Dst8.A,
    };

    return switch (opcode) {
        0x00 => .NOP,
        0x01 => Instr{ .LD_16 = .{ .dst = .BC, .src = Src16{ .Imm = n16 } } },
        0x02 => Instr{ .LD_8 = .{ .dst = .IndBC, .src = .A } },
        0x03 => Instr{ .INC_16 = Dst16.BC },
        0x04 => Instr{ .INC_8 = Dst8.B },
        0x05 => Instr{ .DEC_8 = Dst8.B },
        0x06 => Instr{ .LD_8 = .{ .dst = .B, .src = Src8{ .Imm = n8 } } },
        0x07 => .RLCA,
        0x08 => Instr{ .LD_16 = .{ .dst = Dst16{ .Ind = n16 }, .src = .SP } },
        0x09 => Instr{ .ADD_16 = .{ .dst = .HL, .src = .BC } },
        0x0a => Instr{ .LD_8 = .{ .dst = .A, .src = .IndBC } },
        0x0b => Instr{ .DEC_16 = .BC },
        0x0c => Instr{ .INC_8 = .C },
        0x0d => Instr{ .DEC_8 = .C },
        0x0e => Instr{ .LD_8 = .{ .dst = .C, .src = Src8{ .Imm = n8 } } },
        0x0f => .RRCA,

        0x10 => .STOP,
        0x11 => Instr{ .LD_16 = .{ .dst = .DE, .src = Src16{ .Imm = n16 } } },
        0x12 => Instr{ .LD_8 = .{ .dst = .IndDE, .src = .A } },
        0x13 => Instr{ .INC_16 = Dst16.DE },
        0x14 => Instr{ .INC_8 = Dst8.D },
        0x15 => Instr{ .DEC_8 = Dst8.D },
        0x16 => Instr{ .LD_8 = .{ .dst = .D, .src = Src8{ .Imm = n8 } } },
        0x17 => .RLA,
        0x18 => Instr{ .JR = n8 },
        0x19 => Instr{ .ADD_16 = .{ .dst = .HL, .src = .DE } },
        0x1a => Instr{ .LD_8 = .{ .dst = .A, .src = .IndDE } },
        0x1b => Instr{ .DEC_16 = .DE },
        0x1c => Instr{ .INC_8 = .E },
        0x1d => Instr{ .DEC_8 = .E },
        0x1e => Instr{ .LD_8 = .{ .dst = .E, .src = Src8{ .Imm = n8 } } },
        0x1f => .RRA,

        0x20 => Instr{ .JR_COND = .{ .offset = n8, .cond = .NZ } },
        0x21 => Instr{ .LD_16 = .{ .dst = .HL, .src = Src16{ .Imm = n16 } } },
        0x22 => Instr{ .LD_8 = .{ .dst = .IndHLInc, .src = .A } },
        0x23 => Instr{ .INC_16 = .HL },
        0x24 => Instr{ .INC_8 = .H },
        0x25 => Instr{ .DEC_8 = .H },
        0x26 => Instr{ .LD_8 = .{ .dst = .D, .src = Src8{ .Imm = n8 } } },
        0x27 => .DAA,
        0x28 => Instr{ .JR_COND = .{ .offset = n8, .cond = .Z } },
        0x29 => Instr{ .ADD_16 = .{ .dst = .HL, .src = .HL } },
        0x2a => Instr{ .LD_8 = .{ .dst = .A, .src = .IndHLInc } },
        0x2b => Instr{ .DEC_16 = .HL },
        0x2c => Instr{ .INC_8 = .L },
        0x2d => Instr{ .DEC_8 = .L },
        0x2e => Instr{ .LD_8 = .{ .dst = .L, .src = Src8{ .Imm = n8 } } },
        0x2f => .CPL,

        0x30 => Instr{ .JR_COND = .{ .offset = n8, .cond = .NC } },
        0x31 => Instr{ .LD_16 = .{ .dst = .SP, .src = Src16{ .Imm = n16 } } },
        0x32 => Instr{ .LD_8 = .{ .dst = .IndHLDec, .src = .A } },
        0x33 => Instr{ .INC_16 = .SP },
        0x34 => Instr{ .INC_8 = .IndHL },
        0x35 => Instr{ .DEC_8 = .IndHL },
        0x36 => Instr{ .LD_8 = .{ .dst = .IndHL, .src = Src8{ .Imm = n8 } } },
        0x37 => .SCF,
        0x38 => Instr{ .JR_COND = .{ .offset = n8, .cond = .C } },
        0x39 => Instr{ .ADD_16 = .{ .dst = .HL, .src = .SP } },
        0x3a => Instr{ .LD_8 = .{ .dst = .A, .src = .IndHLDec } },
        0x3b => Instr{ .DEC_16 = .SP },
        0x3c => Instr{ .INC_8 = .A },
        0x3d => Instr{ .DEC_8 = .A },
        0x3e => Instr{ .LD_8 = .{ .dst = .A, .src = Src8{ .Imm = n8 } } },
        0x3f => .CCF,

        0x40...0x47 => Instr{ .LD_8 = .{ .dst = .B, .src = opcodeReg } },
        0x48...0x4f => Instr{ .LD_8 = .{ .dst = .C, .src = opcodeReg } },
        0x50...0x57 => Instr{ .LD_8 = .{ .dst = .D, .src = opcodeReg } },
        0x58...0x5f => Instr{ .LD_8 = .{ .dst = .E, .src = opcodeReg } },
        0x60...0x67 => Instr{ .LD_8 = .{ .dst = .H, .src = opcodeReg } },
        0x68...0x6f => Instr{ .LD_8 = .{ .dst = .L, .src = opcodeReg } },
        0x70...0x75 => Instr{ .LD_8 = .{ .dst = .IndHL, .src = opcodeReg } },
        0x76 => .HALT,
        0x77 => Instr{ .LD_8 = .{ .dst = .IndHL, .src = .A } },
        0x78...0x7f => Instr{ .LD_8 = .{ .dst = .A, .src = opcodeReg } },

        0x80...0x87 => Instr{ .ADD = opcodeReg },
        0x88...0x8f => Instr{ .ADC = opcodeReg },
        0x90...0x97 => Instr{ .SUB = opcodeReg },
        0x98...0x9f => Instr{ .SBC = opcodeReg },
        0xa0...0xa7 => Instr{ .AND = opcodeReg },
        0xa8...0xaf => Instr{ .XOR = opcodeReg },
        0xb0...0xb7 => Instr{ .OR = opcodeReg },
        0xb8...0xbf => Instr{ .CP = opcodeReg },

        0xc0 => Instr{ .RET_COND = .NZ },
        0xc1 => Instr{ .POP = .BC },
        0xc2 => Instr{ .JP_COND = .{ .addr = n16, .cond = .NZ } },
        0xc3 => Instr{ .JP = n16 },
        0xc4 => Instr{ .CALL_COND = .{ .addr = n16, .cond = .NZ } },
        0xc5 => Instr{ .PUSH = .BC },
        0xc6 => Instr{ .ADD = Src8{ .Imm = n8 } },
        0xc7 => Instr{ .RST = 0x00 },
        0xc8 => Instr{ .RET_COND = .Z },
        0xc9 => .RET,
        0xca => Instr{ .JP_COND = .{ .addr = n16, .cond = .Z } },
        0xcb => switch (n8) {
            0x00...0x07 => Instr{ .RLC = opcodeRegCb },
            0x08...0x0f => Instr{ .RRC = opcodeRegCb },
            0x10...0x17 => Instr{ .RL = opcodeRegCb },
            0x18...0x1f => Instr{ .RR = opcodeRegCb },
            0x20...0x27 => Instr{ .SLA = opcodeRegCb },
            0x28...0x2f => Instr{ .SRA = opcodeRegCb },
            0x30...0x37 => Instr{ .SWAP = opcodeRegCb },
            0x38...0x3f => Instr{ .SRL = opcodeRegCb },

            0x40...0x47 => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 0 } },
            0x48...0x4f => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 1 } },
            0x50...0x57 => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 2 } },
            0x58...0x5f => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 3 } },
            0x60...0x67 => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 4 } },
            0x68...0x6f => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 5 } },
            0x70...0x77 => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 6 } },
            0x78...0x7f => Instr{ .BIT = .{ .dst = opcodeRegCb, .bit = 7 } },

            0x80...0x87 => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 0 } },
            0x88...0x8f => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 1 } },
            0x90...0x97 => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 2 } },
            0x98...0x9f => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 3 } },
            0xa0...0xa7 => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 4 } },
            0xa8...0xaf => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 5 } },
            0xb0...0xb7 => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 6 } },
            0xb8...0xbf => Instr{ .RES = .{ .dst = opcodeRegCb, .bit = 7 } },

            0xc0...0xc7 => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 0 } },
            0xc8...0xcf => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 1 } },
            0xd0...0xd7 => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 2 } },
            0xd8...0xdf => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 3 } },
            0xe0...0xe7 => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 4 } },
            0xe8...0xef => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 5 } },
            0xf0...0xf7 => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 6 } },
            0xf8...0xff => Instr{ .SET = .{ .dst = opcodeRegCb, .bit = 7 } },
        },
        0xcc => Instr{ .CALL_COND = .{ .addr = n16, .cond = .Z } },
        0xcd => Instr{ .CALL = n16 },
        0xce => Instr{ .ADC = Src8{ .Imm = n8 } },
        0xcf => Instr{ .RST = 0x08 },

        0xd0 => Instr{ .RET_COND = .NC },
        0xd1 => Instr{ .POP = .DE },
        0xd2 => Instr{ .JP_COND = .{ .addr = n16, .cond = .NC } },
        0xd3 => Instr{ .INVALID = opcode },
        0xd4 => Instr{ .CALL_COND = .{ .addr = n16, .cond = .NC } },
        0xd5 => Instr{ .PUSH = .DE },
        0xd6 => Instr{ .SUB = Src8{ .Imm = n8 } },
        0xd7 => Instr{ .RST = 0x10 },
        0xd8 => Instr{ .RET_COND = .C },
        0xd9 => .RETI,
        0xda => Instr{ .JP_COND = .{ .addr = n16, .cond = .C } },
        0xdb => Instr{ .INVALID = opcode },
        0xdc => Instr{ .CALL_COND = .{ .addr = n16, .cond = .C } },
        0xdd => Instr{ .INVALID = opcode },
        0xde => Instr{ .SBC = Src8{ .Imm = n8 } },
        0xdf => Instr{ .RST = 0x18 },

        0xe0 => Instr{ .LD_8 = .{ .dst = Dst8{ .IndIoReg = n8 }, .src = .A } },
        0xe1 => Instr{ .POP = .HL },
        0xe2 => Instr{ .LD_8 = .{ .dst = .IndC, .src = .A } },
        0xe3 => Instr{ .INVALID = opcode },
        0xe4 => Instr{ .INVALID = opcode },
        0xe5 => Instr{ .PUSH = .HL },
        0xe6 => Instr{ .AND = Src8{ .Imm = n8 } },
        0xe7 => Instr{ .RST = 0x20 },
        0xe8 => Instr{ .ADD_SP = n8 },
        0xe9 => .JP_HL,
        0xea => Instr{ .LD_8 = .{ .dst = Dst8{ .Ind = n16 }, .src = .A } },
        0xeb => Instr{ .INVALID = opcode },
        0xec => Instr{ .INVALID = opcode },
        0xed => Instr{ .INVALID = opcode },
        0xee => Instr{ .XOR = Src8{ .Imm = n8 } },
        0xef => Instr{ .RST = 0x28 },

        0xf0 => Instr{ .LD_8 = .{ .dst = .A, .src = Src8{ .IndIoReg = n8 } } },
        0xf1 => Instr{ .POP = .AF },
        0xf2 => Instr{ .LD_8 = .{ .dst = .A, .src = .IndC } },
        0xf3 => .DI,
        0xf4 => Instr{ .INVALID = opcode },
        0xf5 => Instr{ .PUSH = .AF },
        0xf6 => Instr{ .OR = Src8{ .Imm = n8 } },
        0xf7 => Instr{ .RST = 0x30 },
        0xf8 => Instr{ .LD_16 = .{ .dst = .HL, .src = Src16{ .SPOffset = n8 } } },
        0xf9 => Instr{ .LD_16 = .{ .dst = .SP, .src = .HL } },
        0xfa => Instr{ .LD_8 = .{ .dst = .A, .src = Src8{ .Ind = n16 } } },
        0xfb => .EI,
        0xfc => Instr{ .INVALID = opcode },
        0xfd => Instr{ .INVALID = opcode },
        0xfe => Instr{ .CP = Src8{ .Imm = n8 } },
        0xff => Instr{ .RST = 0x38 },
    };
}
