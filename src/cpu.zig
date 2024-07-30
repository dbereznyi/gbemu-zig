const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const ExecState = @import("gameboy.zig").ExecState;
const util = @import("util.zig");

pub fn stepCpu(gb: *Gb) usize {
    const opcode = gb.rom[gb.pc];

    const n8 = gb.rom[gb.pc + 1];
    const x: u16 = n8;
    const y: u16 = gb.rom[gb.pc + 2];
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

    gb.branchCond = false;

    switch (opcode) {
        0x00 => {},
        0x01 => ld16(gb, Dst16.BC, Src16{ .Imm = n16 }),
        0x02 => ld8(gb, Dst8.IndBC, Src8.A),
        0x03 => inc16(gb, Dst16.BC),
        0x04 => inc8(gb, Dst8.B),
        0x05 => dec8(gb, Dst8.B),
        0x06 => ld8(gb, Dst8.B, Src8{ .Imm = n8 }),
        0x07 => rlca(gb),
        0x08 => ld16(gb, Dst16{ .Ind = n16 }, Src16.SP),
        0x09 => add16(gb, Dst16.HL, Src16.BC),
        0x0a => ld8(gb, Dst8.A, Src8.IndBC),
        0x0b => dec16(gb, Dst16.BC),
        0x0c => inc8(gb, Dst8.C),
        0x0d => dec8(gb, Dst8.C),
        0x0e => ld8(gb, Dst8.C, Src8{ .Imm = n8 }),
        0x0f => rrca(gb),

        0x10 => stop(gb),
        0x11 => ld16(gb, Dst16.DE, Src16{ .Imm = n16 }),
        0x12 => ld8(gb, Dst8.IndDE, Src8.A),
        0x13 => inc16(gb, Dst16.DE),
        0x14 => inc8(gb, Dst8.D),
        0x15 => dec8(gb, Dst8.D),
        0x16 => ld8(gb, Dst8.D, Src8{ .Imm = n8 }),
        0x17 => rla(gb),
        0x18 => jr(gb, n8),
        0x19 => add16(gb, Dst16.HL, Src16.DE),
        0x1a => ld8(gb, Dst8.A, Src8.IndDE),
        0x1b => dec16(gb, Dst16.DE),
        0x1c => inc8(gb, Dst8.E),
        0x1d => dec8(gb, Dst8.E),
        0x1e => ld8(gb, Dst8.E, Src8{ .Imm = n8 }),
        0x1f => rra(gb),

        0x20 => jrCond(gb, n8, !gb.zero),
        0x21 => ld16(gb, Dst16.HL, Src16{ .Imm = n16 }),
        0x22 => ld8(gb, Dst8.IndHLInc, Src8.A),
        0x23 => inc16(gb, Dst16.HL),
        0x24 => inc8(gb, Dst8.H),
        0x25 => dec8(gb, Dst8.H),
        0x26 => ld8(gb, Dst8.D, Src8{ .Imm = n8 }),
        0x27 => daa(gb),
        0x28 => jrCond(gb, n8, gb.zero),
        0x29 => add16(gb, Dst16.HL, Src16.HL),
        0x2a => ld8(gb, Dst8.A, Src8.IndHLInc),
        0x2b => dec16(gb, Dst16.HL),
        0x2c => inc8(gb, Dst8.L),
        0x2d => dec8(gb, Dst8.L),
        0x2e => ld8(gb, Dst8.L, Src8{ .Imm = n8 }),
        0x2f => cpl(gb),

        0x30 => jrCond(gb, n8, !gb.carry),
        0x31 => ld16(gb, Dst16.SP, Src16{ .Imm = n16 }),
        0x32 => ld8(gb, Dst8.IndHLDec, Src8.A),
        0x33 => inc16(gb, Dst16.SP),
        0x34 => inc8(gb, Dst8.IndHL),
        0x35 => dec8(gb, Dst8.IndHL),
        0x36 => ld8(gb, Dst8.IndHL, Src8{ .Imm = n8 }),
        0x37 => scf(gb),
        0x38 => jrCond(gb, n8, gb.carry),
        0x39 => add16(gb, Dst16.HL, Src16.SP),
        0x3a => ld8(gb, Dst8.A, Src8.IndHLDec),
        0x3b => dec16(gb, Dst16.SP),
        0x3c => inc8(gb, Dst8.A),
        0x3d => dec8(gb, Dst8.A),
        0x3e => ld8(gb, Dst8.A, Src8{ .Imm = n8 }),
        0x3f => ccf(gb),

        0x40...0x47 => ld8(gb, Dst8.B, opcodeReg),
        0x48...0x4f => ld8(gb, Dst8.C, opcodeReg),
        0x50...0x57 => ld8(gb, Dst8.D, opcodeReg),
        0x58...0x5f => ld8(gb, Dst8.E, opcodeReg),
        0x60...0x67 => ld8(gb, Dst8.H, opcodeReg),
        0x68...0x6f => ld8(gb, Dst8.L, opcodeReg),
        0x70...0x75 => ld8(gb, Dst8.IndHL, opcodeReg),
        0x76 => halt(gb),
        0x77 => ld8(gb, Dst8.IndHL, Src8.A),
        0x78...0x7f => ld8(gb, Dst8.A, opcodeReg),

        0x80...0x87 => add(gb, opcodeReg),
        0x88...0x8f => adc(gb, opcodeReg),
        0x90...0x97 => sub(gb, opcodeReg),
        0x98...0x9f => sbc(gb, opcodeReg),
        0xa0...0xa7 => and_(gb, opcodeReg),
        0xa8...0xaf => xor(gb, opcodeReg),
        0xb0...0xb7 => or_(gb, opcodeReg),
        0xb8...0xbf => cp(gb, opcodeReg),

        0xc0 => retCond(gb, !gb.zero),
        0xc1 => pop(gb, Dst16.BC),
        0xc2 => jpCond(gb, n16, !gb.zero),
        0xc3 => jp(gb, n16),
        0xc4 => callCond(gb, n16, !gb.zero),
        0xc5 => push(gb, Src16.BC),
        0xc6 => add(gb, Src8{ .Imm = n8 }),
        0xc7 => rst(gb, 0x00),
        0xc8 => retCond(gb, gb.zero),
        0xc9 => ret(gb),
        0xca => jpCond(gb, n16, gb.zero),
        0xcb => switch (n8) {
            0x00...0x07 => rlc(gb, opcodeRegCb),
            0x08...0x0f => rrc(gb, opcodeRegCb),
            0x10...0x17 => rl(gb, opcodeRegCb),
            0x18...0x1f => rr(gb, opcodeRegCb),
            0x20...0x27 => sla(gb, opcodeRegCb),
            0x28...0x2f => sra(gb, opcodeRegCb),
            0x30...0x37 => swap(gb, opcodeRegCb),
            0x38...0x3f => srl(gb, opcodeRegCb),

            0x40...0x47 => bit(gb, opcodeRegCb, 0),
            0x48...0x4f => bit(gb, opcodeRegCb, 1),
            0x50...0x57 => bit(gb, opcodeRegCb, 2),
            0x58...0x5f => bit(gb, opcodeRegCb, 3),
            0x60...0x67 => bit(gb, opcodeRegCb, 4),
            0x68...0x6f => bit(gb, opcodeRegCb, 5),
            0x70...0x77 => bit(gb, opcodeRegCb, 6),
            0x78...0x7f => bit(gb, opcodeRegCb, 7),

            0x80...0x87 => res(gb, opcodeRegCb, 0),
            0x88...0x8f => res(gb, opcodeRegCb, 1),
            0x90...0x97 => res(gb, opcodeRegCb, 2),
            0x98...0x9f => res(gb, opcodeRegCb, 3),
            0xa0...0xa7 => res(gb, opcodeRegCb, 4),
            0xa8...0xaf => res(gb, opcodeRegCb, 5),
            0xb0...0xb7 => res(gb, opcodeRegCb, 6),
            0xb8...0xbf => res(gb, opcodeRegCb, 7),

            0xc0...0xc7 => set(gb, opcodeRegCb, 0),
            0xc8...0xcf => set(gb, opcodeRegCb, 1),
            0xd0...0xd7 => set(gb, opcodeRegCb, 2),
            0xd8...0xdf => set(gb, opcodeRegCb, 3),
            0xe0...0xe7 => set(gb, opcodeRegCb, 4),
            0xe8...0xef => set(gb, opcodeRegCb, 5),
            0xf0...0xf7 => set(gb, opcodeRegCb, 6),
            0xf8...0xff => set(gb, opcodeRegCb, 7),
        },
        0xcc => callCond(gb, n16, gb.zero),
        0xcd => call(gb, n16),
        0xce => adc(gb, Src8{ .Imm = n8 }),
        0xcf => rst(gb, 0x08),

        0xd0 => retCond(gb, !gb.carry),
        0xd1 => pop(gb, Dst16.DE),
        0xd2 => jpCond(gb, n16, !gb.carry),
        0xd3 => invalidOpcode(opcode),
        0xd4 => callCond(gb, n16, !gb.carry),
        0xd5 => push(gb, Src16.DE),
        0xd6 => sub(gb, Src8{ .Imm = n8 }),
        0xd7 => rst(gb, 0x10),
        0xd8 => retCond(gb, gb.carry),
        0xd9 => reti(gb),
        0xda => jpCond(gb, n16, gb.carry),
        0xdb => invalidOpcode(opcode),
        0xdc => callCond(gb, n16, gb.carry),
        0xdd => invalidOpcode(opcode),
        0xde => sbc(gb, Src8{ .Imm = n8 }),
        0xdf => rst(gb, 0x18),

        0xe0 => ld8(gb, Dst8{ .IndIoReg = n8 }, Src8.A),
        0xe1 => pop(gb, Dst16.HL),
        0xe2 => ld8(gb, Dst8.IndC, Src8.A),
        0xe3 => invalidOpcode(opcode),
        0xe4 => invalidOpcode(opcode),
        0xe5 => push(gb, Src16.HL),
        0xe6 => and_(gb, Src8{ .Imm = n8 }),
        0xe7 => rst(gb, 0x20),
        0xe8 => addSp(gb, n8),
        0xe9 => jpHl(gb),
        0xea => ld8(gb, Dst8{ .Ind = n16 }, Src8.A),
        0xeb => invalidOpcode(opcode),
        0xec => invalidOpcode(opcode),
        0xed => invalidOpcode(opcode),
        0xee => xor(gb, Src8{ .Imm = n8 }),
        0xef => rst(gb, 0x28),

        0xf0 => ld8(gb, Dst8.A, Src8{ .IndIoReg = n8 }),
        0xf1 => pop(gb, Dst16.AF),
        0xf2 => ld8(gb, Dst8.A, Src8.IndC),
        0xf3 => di(gb),
        0xf4 => invalidOpcode(opcode),
        0xf5 => push(gb, Src16.AF),
        0xf6 => or_(gb, Src8{ .Imm = n8 }),
        0xf7 => rst(gb, 0x30),
        0xf8 => ld16(gb, Dst16.HL, Src16{ .SPOffset = gb.rom[gb.pc + 1] }),
        0xf9 => ld16(gb, Dst16.SP, Src16.HL),
        0xfa => ld8(gb, Dst8.A, Src8{ .Ind = n16 }),
        0xfb => ei(gb),
        0xfc => invalidOpcode(opcode),
        0xfd => invalidOpcode(opcode),
        0xfe => cp(gb, Src8{ .Imm = n8 }),
        0xff => rst(gb, 0x38),
    }

    gb.*.pc += instrSize(opcode);

    return instrCycles(opcode, n8, gb.branchCond);
}

fn invalidOpcode(opcode: u8) void {
    std.debug.print("invalid opcode: {}\n", .{opcode});
    std.process.exit(1);
}

fn instrSize(opcode: u8) u16 {
    const size: u16 = switch (opcode) {
        0x00 => 1,
        0x01 => 3,
        0x02 => 1,
        0x03 => 1,
        0x04 => 1,
        0x05 => 1,
        0x06 => 2,
        0x07 => 1,
        0x08 => 3,
        0x09 => 1,
        0x0a => 1,
        0x0b => 1,
        0x0c => 1,
        0x0d => 1,
        0x0e => 2,
        0x0f => 1,
        0x10 => 2,
        0x11 => 3,
        0x12 => 1,
        0x13 => 1,
        0x14 => 1,
        0x15 => 1,
        0x16 => 2,
        0x17 => 1,
        0x18 => 2,
        0x19 => 1,
        0x1a => 1,
        0x1b => 1,
        0x1c => 1,
        0x1d => 1,
        0x1e => 2,
        0x1f => 1,
        0x20 => 2,
        0x21 => 3,
        0x22 => 1,
        0x23 => 1,
        0x24 => 1,
        0x25 => 1,
        0x26 => 2,
        0x27 => 1,
        0x28 => 2,
        0x29 => 1,
        0x2a => 1,
        0x2b => 1,
        0x2c => 1,
        0x2d => 1,
        0x2e => 2,
        0x2f => 1,
        0x30 => 2,
        0x31 => 3,
        0x32 => 1,
        0x33 => 1,
        0x34 => 1,
        0x35 => 1,
        0x36 => 2,
        0x37 => 1,
        0x38 => 2,
        0x39 => 1,
        0x3a => 1,
        0x3b => 1,
        0x3c => 1,
        0x3d => 1,
        0x3e => 2,
        0x3f => 1,
        0x40 => 1,
        0x41 => 1,
        0x42 => 1,
        0x43 => 1,
        0x44 => 1,
        0x45 => 1,
        0x46 => 1,
        0x47 => 1,
        0x48 => 1,
        0x49 => 1,
        0x4a => 1,
        0x4b => 1,
        0x4c => 1,
        0x4d => 1,
        0x4e => 1,
        0x4f => 1,
        0x50 => 1,
        0x51 => 1,
        0x52 => 1,
        0x53 => 1,
        0x54 => 1,
        0x55 => 1,
        0x56 => 1,
        0x57 => 1,
        0x58 => 1,
        0x59 => 1,
        0x5a => 1,
        0x5b => 1,
        0x5c => 1,
        0x5d => 1,
        0x5e => 1,
        0x5f => 1,
        0x60 => 1,
        0x61 => 1,
        0x62 => 1,
        0x63 => 1,
        0x64 => 1,
        0x65 => 1,
        0x66 => 1,
        0x67 => 1,
        0x68 => 1,
        0x69 => 1,
        0x6a => 1,
        0x6b => 1,
        0x6c => 1,
        0x6d => 1,
        0x6e => 1,
        0x6f => 1,
        0x70 => 1,
        0x71 => 1,
        0x72 => 1,
        0x73 => 1,
        0x74 => 1,
        0x75 => 1,
        0x76 => 1,
        0x77 => 1,
        0x78 => 1,
        0x79 => 1,
        0x7a => 1,
        0x7b => 1,
        0x7c => 1,
        0x7d => 1,
        0x7e => 1,
        0x7f => 1,
        0x80 => 1,
        0x81 => 1,
        0x82 => 1,
        0x83 => 1,
        0x84 => 1,
        0x85 => 1,
        0x86 => 1,
        0x87 => 1,
        0x88 => 1,
        0x89 => 1,
        0x8a => 1,
        0x8b => 1,
        0x8c => 1,
        0x8d => 1,
        0x8e => 1,
        0x8f => 1,
        0x90 => 1,
        0x91 => 1,
        0x92 => 1,
        0x93 => 1,
        0x94 => 1,
        0x95 => 1,
        0x96 => 1,
        0x97 => 1,
        0x98 => 1,
        0x99 => 1,
        0x9a => 1,
        0x9b => 1,
        0x9c => 1,
        0x9d => 1,
        0x9e => 1,
        0x9f => 1,
        0xa0 => 1,
        0xa1 => 1,
        0xa2 => 1,
        0xa3 => 1,
        0xa4 => 1,
        0xa5 => 1,
        0xa6 => 1,
        0xa7 => 1,
        0xa8 => 1,
        0xa9 => 1,
        0xaa => 1,
        0xab => 1,
        0xac => 1,
        0xad => 1,
        0xae => 1,
        0xaf => 1,
        0xb0 => 1,
        0xb1 => 1,
        0xb2 => 1,
        0xb3 => 1,
        0xb4 => 1,
        0xb5 => 1,
        0xb6 => 1,
        0xb7 => 1,
        0xb8 => 1,
        0xb9 => 1,
        0xba => 1,
        0xbb => 1,
        0xbc => 1,
        0xbd => 1,
        0xbe => 1,
        0xbf => 1,
        0xc0 => 1,
        0xc1 => 1,
        0xc2 => 3,
        0xc3 => 3,
        0xc4 => 3,
        0xc5 => 1,
        0xc6 => 2,
        0xc7 => 1,
        0xc8 => 1,
        0xc9 => 1,
        0xca => 3,
        0xcb => 2,
        0xcc => 3,
        0xcd => 3,
        0xce => 2,
        0xcf => 1,
        0xd0 => 1,
        0xd1 => 1,
        0xd2 => 3,
        0xd4 => 3,
        0xd5 => 1,
        0xd6 => 2,
        0xd7 => 1,
        0xd8 => 1,
        0xd9 => 1,
        0xda => 3,
        0xdc => 3,
        0xde => 2,
        0xdf => 1,
        0xe0 => 2,
        0xe1 => 1,
        0xe2 => 1,
        0xe5 => 1,
        0xe6 => 2,
        0xe7 => 1,
        0xe8 => 2,
        0xe9 => 1,
        0xea => 3,
        0xee => 2,
        0xef => 1,
        0xf0 => 2,
        0xf1 => 1,
        0xf2 => 1,
        0xf3 => 1,
        0xf5 => 1,
        0xf6 => 2,
        0xf7 => 1,
        0xf8 => 2,
        0xf9 => 1,
        0xfa => 3,
        0xfb => 1,
        0xfe => 2,
        0xff => 1,
        else => {
            std.debug.print("opcode {} is invalid: size could not be computed", .{opcode});
            std.process.exit(1);
        },
    };

    return size;
}

fn instrCycles(opcode: u8, opcodeCb: u8, cond: bool) usize {
    const cycles: usize = switch (opcode) {
        0x00 => 1,
        0x01 => 3,
        0x02 => 2,
        0x03 => 2,
        0x04 => 1,
        0x05 => 1,
        0x06 => 2,
        0x07 => 1,
        0x08 => 5,
        0x09 => 2,
        0x0a => 2,
        0x0b => 2,
        0x0c => 1,
        0x0d => 1,
        0x0e => 2,
        0x0f => 1,
        0x10 => 1,
        0x11 => 3,
        0x12 => 2,
        0x13 => 2,
        0x14 => 1,
        0x15 => 1,
        0x16 => 2,
        0x17 => 1,
        0x18 => 3,
        0x19 => 2,
        0x1a => 2,
        0x1b => 2,
        0x1c => 1,
        0x1d => 1,
        0x1e => 2,
        0x1f => 1,
        0x20 => if (cond) 3 else 2,
        0x21 => 3,
        0x22 => 2,
        0x23 => 2,
        0x24 => 1,
        0x25 => 1,
        0x26 => 2,
        0x27 => 1,
        0x28 => if (cond) 3 else 2,
        0x29 => 2,
        0x2a => 2,
        0x2b => 2,
        0x2c => 1,
        0x2d => 1,
        0x2e => 2,
        0x2f => 1,
        0x30 => if (cond) 3 else 2,
        0x31 => 3,
        0x32 => 2,
        0x33 => 2,
        0x34 => 3,
        0x35 => 3,
        0x36 => 3,
        0x37 => 1,
        0x38 => if (cond) 3 else 2,
        0x39 => 2,
        0x3a => 2,
        0x3b => 2,
        0x3c => 1,
        0x3d => 1,
        0x3e => 2,
        0x3f => 1,
        0x40 => 1,
        0x41 => 1,
        0x42 => 1,
        0x43 => 1,
        0x44 => 1,
        0x45 => 1,
        0x46 => 2,
        0x47 => 1,
        0x48 => 1,
        0x49 => 1,
        0x4a => 1,
        0x4b => 1,
        0x4c => 1,
        0x4d => 1,
        0x4e => 2,
        0x4f => 1,
        0x50 => 1,
        0x51 => 1,
        0x52 => 1,
        0x53 => 1,
        0x54 => 1,
        0x55 => 1,
        0x56 => 2,
        0x57 => 1,
        0x58 => 1,
        0x59 => 1,
        0x5a => 1,
        0x5b => 1,
        0x5c => 1,
        0x5d => 1,
        0x5e => 2,
        0x5f => 1,
        0x60 => 1,
        0x61 => 1,
        0x62 => 1,
        0x63 => 1,
        0x64 => 1,
        0x65 => 1,
        0x66 => 2,
        0x67 => 1,
        0x68 => 1,
        0x69 => 1,
        0x6a => 1,
        0x6b => 1,
        0x6c => 1,
        0x6d => 1,
        0x6e => 2,
        0x6f => 1,
        0x70 => 2,
        0x71 => 2,
        0x72 => 2,
        0x73 => 2,
        0x74 => 2,
        0x75 => 2,
        0x76 => 1,
        0x77 => 2,
        0x78 => 1,
        0x79 => 1,
        0x7a => 1,
        0x7b => 1,
        0x7c => 1,
        0x7d => 1,
        0x7e => 2,
        0x7f => 1,
        0x80 => 1,
        0x81 => 1,
        0x82 => 1,
        0x83 => 1,
        0x84 => 1,
        0x85 => 1,
        0x86 => 2,
        0x87 => 1,
        0x88 => 1,
        0x89 => 1,
        0x8a => 1,
        0x8b => 1,
        0x8c => 1,
        0x8d => 1,
        0x8e => 2,
        0x8f => 1,
        0x90 => 1,
        0x91 => 1,
        0x92 => 1,
        0x93 => 1,
        0x94 => 1,
        0x95 => 1,
        0x96 => 2,
        0x97 => 1,
        0x98 => 1,
        0x99 => 1,
        0x9a => 1,
        0x9b => 1,
        0x9c => 1,
        0x9d => 1,
        0x9e => 2,
        0x9f => 1,
        0xa0 => 1,
        0xa1 => 1,
        0xa2 => 1,
        0xa3 => 1,
        0xa4 => 1,
        0xa5 => 1,
        0xa6 => 2,
        0xa7 => 1,
        0xa8 => 1,
        0xa9 => 1,
        0xaa => 1,
        0xab => 1,
        0xac => 1,
        0xad => 1,
        0xae => 2,
        0xaf => 1,
        0xb0 => 1,
        0xb1 => 1,
        0xb2 => 1,
        0xb3 => 1,
        0xb4 => 1,
        0xb5 => 1,
        0xb6 => 2,
        0xb7 => 1,
        0xb8 => 1,
        0xb9 => 1,
        0xba => 1,
        0xbb => 1,
        0xbc => 1,
        0xbd => 1,
        0xbe => 2,
        0xbf => 1,
        0xc0 => if (cond) 5 else 2,
        0xc1 => 3,
        0xc2 => if (cond) 4 else 3,
        0xc3 => 4,
        0xc4 => if (cond) 6 else 3,
        0xc5 => 4,
        0xc6 => 2,
        0xc7 => 4,
        0xc8 => if (cond) 5 else 2,
        0xc9 => 4,
        0xca => if (cond) 4 else 3,
        0xcb => switch (opcodeCb) {
            0x00...0x05 => 2,
            0x06 => 4,
            0x07...0x0d => 2,
            0x0e => 4,
            0x0f => 2,
            0x10...0x15 => 2,
            0x16 => 4,
            0x17...0x1d => 2,
            0x1e => 4,
            0x1f => 2,
            0x20...0x25 => 2,
            0x26 => 4,
            0x27...0x2d => 2,
            0x2e => 4,
            0x2f => 2,
            0x30...0x35 => 2,
            0x36 => 4,
            0x37...0x3d => 2,
            0x3e => 4,
            0x3f => 2,
            0x40...0x45 => 2,
            0x46 => 4,
            0x47...0x4d => 2,
            0x4e => 4,
            0x4f => 2,
            0x50...0x55 => 2,
            0x56 => 4,
            0x57...0x5d => 2,
            0x5e => 4,
            0x5f => 2,
            0x60...0x65 => 2,
            0x66 => 4,
            0x67...0x6d => 2,
            0x6e => 4,
            0x6f => 2,
            0x70...0x75 => 2,
            0x76 => 4,
            0x77...0x7d => 2,
            0x7e => 4,
            0x7f => 2,
            0x80...0x85 => 2,
            0x86 => 4,
            0x87...0x8d => 2,
            0x8e => 4,
            0x8f => 2,
            0x90...0x95 => 2,
            0x96 => 4,
            0x97...0x9d => 2,
            0x9e => 4,
            0x9f => 2,
            0xa0...0xa5 => 2,
            0xa6 => 4,
            0xa7...0xad => 2,
            0xae => 4,
            0xaf => 2,
            0xb0...0xb5 => 2,
            0xb6 => 4,
            0xb7...0xbd => 2,
            0xbe => 4,
            0xbf => 2,
            0xc0...0xc5 => 2,
            0xc6 => 4,
            0xc7...0xcd => 2,
            0xce => 4,
            0xcf => 2,
            0xd0...0xd5 => 2,
            0xd6 => 4,
            0xd7...0xdd => 2,
            0xde => 4,
            0xdf => 2,
            0xe0...0xe5 => 2,
            0xe6 => 4,
            0xe7...0xed => 2,
            0xee => 4,
            0xef => 2,
            0xf0...0xf5 => 2,
            0xf6 => 4,
            0xf7...0xfd => 2,
            0xfe => 4,
            0xff => 2,
        },
        0xcc => if (cond) 6 else 3,
        0xcd => 6,
        0xce => 2,
        0xcf => 4,
        0xd0 => if (cond) 5 else 2,
        0xd1 => 3,
        0xd2 => if (cond) 4 else 3,
        0xd4 => if (cond) 6 else 3,
        0xd5 => 4,
        0xd6 => 2,
        0xd7 => 4,
        0xd8 => if (cond) 5 else 2,
        0xd9 => 4,
        0xda => if (cond) 4 else 3,
        0xdc => if (cond) 6 else 3,
        0xde => 2,
        0xdf => 4,
        0xe0 => 3,
        0xe1 => 3,
        0xe2 => 2,
        0xe5 => 4,
        0xe6 => 2,
        0xe7 => 4,
        0xe8 => 4,
        0xe9 => 1,
        0xea => 4,
        0xee => 2,
        0xef => 4,
        0xf0 => 3,
        0xf1 => 3,
        0xf2 => 2,
        0xf3 => 1,
        0xf5 => 4,
        0xf6 => 2,
        0xf7 => 4,
        0xf8 => 3,
        0xf9 => 2,
        0xfa => 4,
        0xfb => 1,
        0xfe => 2,
        0xff => 4,
        else => {
            std.debug.print("opcode {} is invalid: cycles could not be computed", .{opcode});
            std.process.exit(1);
        },
    };

    return cycles;
}

const Dst16Tag = enum {
    AF,
    BC,
    DE,
    HL,
    SP,
    Ind,
};

const Dst16 = union(Dst16Tag) {
    AF: void,
    BC: void,
    DE: void,
    HL: void,
    SP: void,
    Ind: u16,
};

fn readDst16(gb: *Gb, dst: Dst16) u16 {
    return switch (dst) {
        Dst16.AF => util.as16(gb.a, Gb.readFlags(gb)),
        Dst16.BC => util.as16(gb.b, gb.c),
        Dst16.DE => util.as16(gb.d, gb.e),
        Dst16.HL => util.as16(gb.h, gb.l),
        Dst16.SP => gb.sp,
        Dst16.Ind => |ind| Gb.read(gb, ind),
    };
}

fn writeDst16(gb: *Gb, dst: Dst16, val: u16) void {
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

const Src16Tag = enum {
    AF,
    BC,
    DE,
    HL,
    SP,
    SPOffset,
    Imm,
};

const Src16 = union(Src16Tag) {
    AF: void,
    BC: void,
    DE: void,
    HL: void,
    SP: void,
    SPOffset: u8,
    Imm: u16,
};

fn readSrc16(gb: *const Gb, src: Src16) u16 {
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

fn ld16(gb: *Gb, dst: Dst16, src: Src16) void {
    const val = readSrc16(gb, src);
    writeDst16(gb, dst, val);
}

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

const Dst8 = union(Dst8Tag) {
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
};

fn readDst8(gb: *Gb, dst: Dst8) u8 {
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
            incHL(gb);
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

fn writeDst8(gb: *Gb, dst: Dst8, val: u8) void {
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

const Src8 = union(Src8Tag) {
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
};

fn readSrc8(gb: *Gb, src: Src8) u8 {
    const val = switch (src) {
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

    return val;
}

fn incHL(gb: *Gb) void {
    const hl = util.as16(gb.h, gb.l);
    const hlInc = hl + 1;
    gb.h = @truncate(hlInc >> 8);
    gb.l = @truncate(hlInc);
}

fn decHL(gb: *Gb) void {
    const hl = util.as16(gb.h, gb.l);
    const hlDec = hl - 1;
    gb.h = @truncate(hlDec >> 8);
    gb.l = @truncate(hlDec);
}

fn ld8(gb: *Gb, dst: Dst8, src: Src8) void {
    const val = readSrc8(gb, src);
    writeDst8(gb, dst, val);
}

fn checkHalfCarry(x: u8, y: u8) bool {
    const sum4Bit = (x & 0x0f) + (y & 0x0f);
    return sum4Bit > 0x0f;
}

fn checkCarry(x: u8, y: u8) bool {
    const sum = @as(u16, x) + @as(u16, y);
    return sum > 0xff;
}

fn add(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const y = gb.a;
    const sum = x + y;
    gb.a = sum;

    gb.zero = sum == 0;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(x, y);
    gb.carry = checkCarry(x, y);
}

fn checkHalfCarry16(x: u16, y: u16) bool {
    const sum12Bit = (x & 0x0fff) + (y & 0x0fff);
    return sum12Bit > 0x0fff;
}

fn checkCarry16(x: u16, y: u16) bool {
    const sum = @as(u32, x) + @as(u32, y);
    return sum > 0xffff;
}

fn add16(gb: *Gb, dst: Dst16, src: Src16) void {
    const x = readSrc16(gb, src);
    const y = readDst16(gb, dst);
    const sum = x + y;
    writeDst16(gb, dst, sum);

    gb.negative = false;
    gb.halfCarry = checkHalfCarry16(x, y);
    gb.carry = checkCarry16(x, y);
}

fn adc(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const y = gb.a;
    const carry: u8 = if (gb.carry) 1 else 0;
    const sum = x + y + carry;
    gb.a = sum;

    gb.zero = sum == 0;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(x, y + carry);
    gb.carry = checkCarry(x, y + carry);
}

fn sub(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const diff = gb.a - x;
    gb.a = diff;

    gb.zero = diff == 0;
    gb.negative = true;
    gb.halfCarry = checkHalfCarry(gb.a, (x ^ 0xff) + 1);
    gb.carry = checkCarry(gb.a, (x ^ 0xff) + 1);
}

fn sbc(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const carry: u8 = if (gb.carry) 1 else 0;
    const diff = gb.a - x - carry;
    gb.a = diff;

    gb.zero = diff == 0;
    gb.negative = true;
    gb.halfCarry = checkHalfCarry(gb.a, ((x + carry) ^ 0xff) + 1);
    gb.carry = checkCarry(gb.a, ((x + carry) ^ 0xff) + 1);
}

fn and_(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const result = gb.a & x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = true;
    gb.carry = false;
}

fn xor(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const result = gb.a ^ x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn or_(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const result = gb.a | x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn cp(gb: *Gb, src: Src8) void {
    const x = readSrc8(gb, src);
    const result = gb.a - x;

    gb.zero = result == 0;
    gb.negative = true;
    gb.halfCarry = checkHalfCarry(gb.a, (x ^ 0xff) + 1);
    gb.carry = checkCarry(gb.a, (x ^ 0xff) + 1);
}

fn inc8(gb: *Gb, dst: Dst8) void {
    const initialValue = readDst8(gb, dst);
    const result = initialValue + 1;
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(initialValue, 1);
}

fn dec8(gb: *Gb, dst: Dst8) void {
    const initialValue = readDst8(gb, dst);
    const result = initialValue - 1;
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = true;
    gb.halfCarry = checkHalfCarry(initialValue, 0xff);
}

fn inc16(gb: *Gb, dst: Dst16) void {
    const initialValue = readDst16(gb, dst);
    const result = initialValue + 1;
    writeDst16(gb, dst, result);
}

fn dec16(gb: *Gb, dst: Dst16) void {
    const initialValue = readDst16(gb, dst);
    const result = initialValue - 1;
    writeDst16(gb, dst, result);
}

fn calcJrDestAddr(pc: u16, offset: u8) u16 {
    const offsetI8: i8 = @bitCast(offset);
    const pcI16: i16 = @intCast(pc);
    // subtract 2 bytes to account for PC getting incremented by the size of JR (2 bytes)
    return @intCast(pcI16 + offsetI8 - 2);
}

test "calcJrDestAddr" {
    const offset: u8 = 156; // -100 as i8
    const pc: u16 = 1500;
    const expected: u16 = 1400; // 1500 - 100 = 1400

    const result = calcJrDestAddr(pc, offset) + 2; // inc by 2 to simulate PC increment
    try std.testing.expect(result == expected);
}

fn jr(gb: *Gb, offset: u8) void {
    gb.pc = calcJrDestAddr(gb.pc, offset);
}

fn jrCond(gb: *Gb, offset: u8, cond: bool) void {
    if (cond) {
        gb.pc = calcJrDestAddr(gb.pc, offset);
        gb.branchCond = true;
    }
}

fn calcJpDestAddr(address: u16) u16 {
    // subtract 3 bytes to account for PC getting incremented by the size of JP (3 bytes)
    return address - 3;
}

fn jp(gb: *Gb, address: u16) void {
    gb.pc = calcJpDestAddr(address);
}

fn jpCond(gb: *Gb, address: u16, cond: bool) void {
    if (cond) {
        gb.pc = calcJpDestAddr(address);
        gb.branchCond = true;
    }
}

fn jpHl(gb: *Gb) void {
    const destAddr = readSrc16(gb, Src16.HL);
    gb.pc = calcJpDestAddr(destAddr);
}

fn pop16(gb: *Gb) u16 {
    const low = Gb.read(gb, gb.sp);
    gb.sp += 1;
    const high = Gb.read(gb, gb.sp);
    gb.sp += 1;
    return util.as16(low, high);
}

fn calcRetDestAddr(address: u16) u16 {
    // subtract 1 byte to account for PC getting incremented by the size of RET (1 byte)
    return address - 1;
}

fn ret(gb: *Gb) void {
    gb.pc = calcRetDestAddr(pop16(gb));
}

fn retCond(gb: *Gb, cond: bool) void {
    if (cond) {
        gb.pc = calcRetDestAddr(pop16(gb));
        gb.branchCond = true;
    }
}

fn reti(gb: *Gb) void {
    gb.pc = calcRetDestAddr(pop16(gb));
    gb.ime = true;
}

fn push16(gb: *Gb, value: u16) void {
    const high: u8 = @truncate(value >> 8);
    const low: u8 = @truncate(value);
    Gb.write(gb, gb.sp, high);
    Gb.write(gb, gb.sp, low);
}

fn call(gb: *Gb, address: u16) void {
    push16(gb, gb.pc + 3);
    gb.pc = address;
}

fn callCond(gb: *Gb, address: u16, cond: bool) void {
    if (cond) {
        push16(gb, gb.pc + 3);
        gb.pc = address;
        gb.branchCond = true;
    }
}

fn rst(gb: *Gb, address: u8) void {
    push16(gb, gb.pc + 1);
    // subtract 1 byte to account for PC getting incremented by the size of RST (1 byte)
    gb.pc = address - 1;
}

fn pop(gb: *Gb, dst: Dst16) void {
    const value = pop16(gb);
    writeDst16(gb, dst, value);
}

fn push(gb: *Gb, src: Src16) void {
    const value = readSrc16(gb, src);
    push16(gb, value);
}

fn di(gb: *Gb) void {
    gb.ime = false;
}

fn ei(gb: *Gb) void {
    gb.ime = true;
}

fn halt(gb: *Gb) void {
    if (gb.ime) {
        gb.execState = ExecState.halted;
    } else {
        const interruptPending = (Gb.read(gb, IoReg.IE) & Gb.read(gb, IoReg.IF)) > 0;
        if (!interruptPending) {
            gb.execState = ExecState.haltedSkipInterrupt;
        } else {
            // TODO simulate halting bug
        }
    }
}

fn stop(gb: *Gb) void {
    gb.execState = ExecState.stopped;
}

fn addSp(gb: *Gb, value: u8) void {
    const valueI8: i8 = @bitCast(value);
    const spI16: i16 = @intCast(gb.sp);

    const initialSp = gb.sp;
    gb.sp = @intCast(spI16 + valueI8);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(@truncate(initialSp), value);
    gb.carry = checkCarry(@truncate(initialSp), value);
}

fn rlca(gb: *Gb) void {
    const bit7 = gb.a & 0b1000_0000;
    gb.a = (gb.a << 1) | (bit7 >> 7);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn rlc(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const bit7 = value & 0b1000_0000;
    const result = (value << 1) | (bit7 >> 7);
    writeDst8(gb, dst, result);

    gb.zero = readDst8(gb, dst) == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn rrca(gb: *Gb) void {
    const bit0 = gb.a & 0b0000_0001;
    gb.a = (gb.a >> 1) | (bit0 << 7);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn rrc(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const bit0 = value & 0b0000_0001;
    const result = (value >> 1) | (bit0 << 7);
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn rla(gb: *Gb) void {
    const newBit0: u8 = if (gb.carry) 1 else 0;
    const bit7 = gb.a & 0b1000_0000;
    gb.a = (gb.a << 1) | newBit0;

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn rl(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const newBit0: u8 = if (gb.carry) 1 else 0;
    const bit7 = value & 0b1000_0000;
    const result = (gb.a << 1) | newBit0;
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn rra(gb: *Gb) void {
    const newBit7: u8 = if (gb.carry) 1 else 0;
    const bit0 = gb.a & 0b0000_0001;
    gb.a = (gb.a >> 1) | (newBit7 << 7);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn rr(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const newBit7: u8 = if (gb.carry) 1 else 0;
    const bit0 = value & 0b0000_0001;
    const result = (gb.a >> 1) | (newBit7 << 7);
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn sla(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const bit7 = value & 0b1000_0000;
    const result = value << 1;
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn sra(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const bit7 = value & 0b1000_0000;
    const bit0 = value & 0b0000_0001;
    const result = bit7 | (value >> 1);
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn swap(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const low = value & 0b0000_1111;
    const high = value & 0b1111_0000;
    const result = (low << 4) | (high >> 4);
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn srl(gb: *Gb, dst: Dst8) void {
    const value = readDst8(gb, dst);

    const bit0 = value & 0b0000_0001;
    const result = value >> 1;
    writeDst8(gb, dst, result);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn bit(gb: *Gb, dst: Dst8, n: u3) void {
    const value = readDst8(gb, dst);

    const result = value & (@as(u8, 1) << n);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = true;
}

fn res(gb: *Gb, dst: Dst8, n: u3) void {
    const value = readDst8(gb, dst);

    const mask = ~(@as(u8, 1) << n);
    const result = value & mask;
    writeDst8(gb, dst, result);
}

fn set(gb: *Gb, dst: Dst8, n: u3) void {
    const value = readDst8(gb, dst);

    const mask = (@as(u8, 1) << n);
    const result = value | mask;
    writeDst8(gb, dst, result);
}

fn daa(_: *Gb) void {
    // TODO implement
}

fn cpl(gb: *Gb) void {
    gb.a = ~gb.a;

    gb.negative = true;
    gb.halfCarry = true;
}

fn ccf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = !gb.carry;
}

fn scf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = true;
}
