const std = @import("std");
const stepGameboy = @import("../step.zig").stepGameboy;
const expect = std.testing.expect;
const as16 = @import("../../util.zig").as16;
const incAs16 = @import("../../util.zig").incAs16;
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const Cond = @import("operand.zig").Cond;
const Src8 = @import("operand.zig").Src8;
const Src16 = @import("operand.zig").Src16;
const Dst8 = @import("operand.zig").Dst8;
const Dst16 = @import("operand.zig").Dst16;
const AluOp = @import("alu_op.zig").AluOp;
const PrefixOp = @import("prefix_op.zig").PrefixOp;
const shouldDebugBreak = @import("../debug/shouldDebugBreak.zig").shouldDebugBreak;
const runDebugger = @import("../debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("../debug/executeCmd.zig").executeCmd;
const decodeInstrAt = @import("decode.zig").decodeInstrAt;

pub fn runCpu(gb: *Gb) void {
    if (gb.state == .running) {
        const opcode = read8PC(gb);

        executeInstr(gb, opcode);
    }

    flushPendingCycles(gb);
}

fn read8(gb: *Gb, src: Src8) u8 {
    if (gb.pending_cycles > 0) {
        stepGameboy(gb, gb.pending_cycles);
    }
    gb.pending_cycles = 4;

    return src.read(gb);
}

fn read8PC(gb: *Gb) u8 {
    const val = read8(gb, Src8{ .Ind = gb.pc });
    gb.pc +%= 1;
    return val;
}

fn write8(gb: *Gb, dst: Dst8, val: u8) void {
    stepGameboy(gb, gb.pending_cycles);
    dst.write(val, gb);
    gb.pending_cycles = 4;
}

// Special case for instructions where 2 bytes are written in only 1 M-cycle.
fn write16(gb: *Gb, dst: Dst16, val: u16) void {
    stepGameboy(gb, gb.pending_cycles);
    dst.write(val, gb);
    gb.pending_cycles = 4;
}

fn flushPendingCycles(gb: *Gb) void {
    if (gb.pending_cycles > 0) {
        stepGameboy(gb, gb.pending_cycles);
    }
    gb.pending_cycles = 0;
}

fn executeInstr(gb: *Gb, opcode: u8) void {
    switch (opcode) {
        0x00 => {},
        0x01 => ldReg16Imm16(gb, .BC),
        0x02 => ldIndA(gb, .IndBC),
        0x03 => incDec16(gb, .BC, .inc),
        0x04 => incDecReg8(gb, .B, .inc),
        0x05 => incDecReg8(gb, .B, .dec),
        0x06 => ldRegImm(gb, .B),
        0x07 => rlca(gb),
        0x08 => ldImm16SP(gb),
        0x09 => stepAddHLReg16(gb, .BC),
        0x0a => stepLdAInd(gb, .IndBC),
        0x0b => incDec16(gb, .BC, .dec),
        0x0c => incDecReg8(gb, .C, .inc),
        0x0d => incDecReg8(gb, .C, .dec),
        0x0e => ldRegImm(gb, .C),
        0x0f => stepRrca(gb),

        0x10 => stepStop(gb),
        0x11 => ldReg16Imm16(gb, .DE),
        0x12 => ldIndA(gb, .IndDE),
        0x13 => incDec16(gb, .DE, .inc),
        0x14 => incDecReg8(gb, .D, .inc),
        0x15 => incDecReg8(gb, .D, .dec),
        0x16 => ldRegImm(gb, .D),
        0x17 => stepRla(gb),
        0x18 => stepJr(gb),
        0x19 => stepAddHLReg16(gb, .DE),
        0x1a => stepLdAInd(gb, .IndDE),
        0x1b => incDec16(gb, .DE, .dec),
        0x1c => incDecReg8(gb, .E, .inc),
        0x1d => incDecReg8(gb, .E, .dec),
        0x1e => ldRegImm(gb, .E),
        0x1f => stepRra(gb),

        0x20 => stepJrCond(gb, .NZ),
        0x21 => ldReg16Imm16(gb, .HL),
        0x22 => ldIndA(gb, .IndHLInc),
        0x23 => incDec16(gb, .HL, .inc),
        0x24 => incDecReg8(gb, .H, .inc),
        0x25 => incDecReg8(gb, .H, .dec),
        0x26 => ldRegImm(gb, .H),
        0x27 => stepDaa(gb),
        0x28 => stepJrCond(gb, .Z),
        0x29 => stepAddHLReg16(gb, .HL),
        0x2a => stepLdAInd(gb, .IndHLInc),
        0x2b => incDec16(gb, .HL, .dec),
        0x2c => incDecReg8(gb, .L, .inc),
        0x2d => incDecReg8(gb, .L, .dec),
        0x2e => ldRegImm(gb, .L),
        0x2f => stepCpl(gb),

        0x30 => stepJrCond(gb, .NC),
        0x31 => ldReg16Imm16(gb, .SP),
        0x32 => ldIndA(gb, .IndHLDec),
        0x33 => incDec16(gb, .SP, .inc),
        0x34 => stepIncDecIndHL(gb, .inc),
        0x35 => stepIncDecIndHL(gb, .dec),
        0x36 => stepLdIndHLImm(gb),
        0x37 => stepScf(gb),
        0x38 => stepJrCond(gb, .C),
        0x39 => stepAddHLReg16(gb, .SP),
        0x3a => stepLdAInd(gb, .IndHLDec),
        0x3b => incDec16(gb, .SP, .dec),
        0x3c => incDecReg8(gb, .A, .inc),
        0x3d => incDecReg8(gb, .A, .dec),
        0x3e => ldRegImm(gb, .A),
        0x3f => stepCcf(gb),

        0x40 => ldRegReg(gb, .B, .B),
        0x41 => ldRegReg(gb, .B, .C),
        0x42 => ldRegReg(gb, .B, .D),
        0x43 => ldRegReg(gb, .B, .E),
        0x44 => ldRegReg(gb, .B, .H),
        0x45 => ldRegReg(gb, .B, .L),
        0x46 => ldRegInd(gb, .B),
        0x47 => ldRegReg(gb, .B, .A),
        0x48 => ldRegReg(gb, .C, .B),
        0x49 => ldRegReg(gb, .C, .C),
        0x4a => ldRegReg(gb, .C, .D),
        0x4b => ldRegReg(gb, .C, .E),
        0x4c => ldRegReg(gb, .C, .H),
        0x4d => ldRegReg(gb, .C, .L),
        0x4e => ldRegInd(gb, .C),
        0x4f => ldRegReg(gb, .C, .A),

        0x50 => ldRegReg(gb, .D, .B),
        0x51 => ldRegReg(gb, .D, .C),
        0x52 => ldRegReg(gb, .D, .D),
        0x53 => ldRegReg(gb, .D, .E),
        0x54 => ldRegReg(gb, .D, .H),
        0x55 => ldRegReg(gb, .D, .L),
        0x56 => ldRegInd(gb, .D),
        0x57 => ldRegReg(gb, .D, .A),
        0x58 => ldRegReg(gb, .E, .B),
        0x59 => ldRegReg(gb, .E, .C),
        0x5a => ldRegReg(gb, .E, .D),
        0x5b => ldRegReg(gb, .E, .E),
        0x5c => ldRegReg(gb, .E, .H),
        0x5d => ldRegReg(gb, .E, .L),
        0x5e => ldRegInd(gb, .E),
        0x5f => ldRegReg(gb, .E, .A),

        0x60 => ldRegReg(gb, .H, .B),
        0x61 => ldRegReg(gb, .H, .C),
        0x62 => ldRegReg(gb, .H, .D),
        0x63 => ldRegReg(gb, .H, .E),
        0x64 => ldRegReg(gb, .H, .H),
        0x65 => ldRegReg(gb, .H, .L),
        0x66 => ldRegInd(gb, .H),
        0x67 => ldRegReg(gb, .H, .A),
        0x68 => ldRegReg(gb, .L, .B),
        0x69 => ldRegReg(gb, .L, .C),
        0x6a => ldRegReg(gb, .L, .D),
        0x6b => ldRegReg(gb, .L, .E),
        0x6c => ldRegReg(gb, .L, .H),
        0x6d => ldRegReg(gb, .L, .L),
        0x6e => ldRegInd(gb, .L),
        0x6f => ldRegReg(gb, .L, .A),

        0x70 => ldIndReg(gb, .B),
        0x71 => ldIndReg(gb, .C),
        0x72 => ldIndReg(gb, .D),
        0x73 => ldIndReg(gb, .E),
        0x74 => ldIndReg(gb, .H),
        0x75 => ldIndReg(gb, .L),
        0x76 => halt(gb),
        0x77 => ldRegReg(gb, .H, .A),
        0x78 => ldRegReg(gb, .A, .B),
        0x79 => ldRegReg(gb, .A, .C),
        0x7a => ldRegReg(gb, .A, .D),
        0x7b => ldRegReg(gb, .A, .E),
        0x7c => ldRegReg(gb, .A, .H),
        0x7d => ldRegReg(gb, .A, .L),
        0x7e => ldRegInd(gb, .A),
        0x7f => ldRegReg(gb, .A, .A),

        // 8-bit arithmetic
        0x80...0xbf => {
            const src_encoding = @as(u3, @truncate(gb.ir));
            const src = Src8.decode(src_encoding);
            const op = AluOp.decode(@as(u3, @truncate(gb.ir >> 3)));
            stepAluOp(gb, op, src);
        },

        0xc0 => stepRetCond(gb, .NZ),
        0xc1 => stepPop(gb, .BC),
        0xc2 => stepJpCond(gb, .NZ),
        0xc3 => stepJp(gb),
        0xc4 => stepCallCond(gb, .NZ),
        0xc5 => stepPush(gb, .BC),
        0xc6 => stepAluOpImm(gb, .add),
        0xc7 => stepRst(gb, 0x00),
        0xc8 => stepRetCond(gb, .Z),
        0xc9 => stepRet(gb),
        0xca => stepJpCond(gb, .Z),
        0xcb => stepPrefix(gb),
        0xcc => stepCallCond(gb, .Z),
        0xcd => stepCall(gb),
        0xce => stepAluOpImm(gb, .adc),
        0xcf => stepRst(gb, 0x08),

        0xd0 => stepRetCond(gb, .NC),
        0xd1 => stepPop(gb, .DE),
        0xd2 => stepJpCond(gb, .NC),
        0xd3 => invalidOpcode(gb),
        0xd4 => stepCallCond(gb, .NC),
        0xd5 => stepPush(gb, .DE),
        0xd6 => stepAluOpImm(gb, .sub),
        0xd7 => stepRst(gb, 0x10),
        0xd8 => stepRetCond(gb, .C),
        0xd9 => stepReti(gb),
        0xda => stepJpCond(gb, .C),
        0xdb => invalidOpcode(gb),
        0xdc => stepCallCond(gb, .C),
        0xdd => invalidOpcode(gb),
        0xde => stepAluOpImm(gb, .sbc),
        0xdf => stepRst(gb, 0x18),

        0xe0 => stepLdIndIoA(gb),
        0xe1 => stepPop(gb, .HL),
        0xe2 => stepLdIoCA(gb),
        0xe3 => invalidOpcode(gb),
        0xe4 => invalidOpcode(gb),
        0xe5 => stepPush(gb, .HL),
        0xe6 => stepAluOpImm(gb, .and_),
        0xe7 => stepRst(gb, 0x20),
        0xe8 => stepAddSPe8(gb),
        0xe9 => stepJpHL(gb),
        0xea => stepLdInd16A(gb),
        0xeb => invalidOpcode(gb),
        0xec => invalidOpcode(gb),
        0xed => invalidOpcode(gb),
        0xee => stepAluOpImm(gb, .xor),
        0xef => stepRst(gb, 0x28),

        0xf0 => stepLdAIndIo(gb),
        0xf1 => stepPop(gb, .AF),
        0xf2 => stepLdAIoC(gb),
        0xf3 => stepDi(gb),
        0xf4 => invalidOpcode(gb),
        0xf5 => stepPush(gb, .AF),
        0xf6 => stepAluOpImm(gb, .or_),
        0xf7 => stepRst(gb, 0x30),
        0xf8 => stepLdHLSPe8(gb),
        0xf9 => stepLdSPHL(gb),
        0xfa => stepLdAInd16(gb),
        0xfb => stepEi(gb),
        0xfc => invalidOpcode(gb),
        0xfd => invalidOpcode(gb),
        0xfe => stepAluOpImm(gb, .cp),
        0xff => stepRst(gb, 0x38),
    }
}

fn hl(gb: *Gb) u16 {
    return util.as16(gb.h, gb.l);
}

fn invalidOpcode(gb: *Gb) void {
    gb.panic("Invalid opcode: ${x:0>2}\n", .{gb.ir});
}

fn handleDebugCmd(gb: *Gb) !void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    try executeDebugCmd(debugCmd, gb);
    gb.debug.acknowledgeCommand();
}

fn ldRegReg(gb: *Gb, comptime dst: Dst8, comptime src: Src8) void {
    dst.write(src.read(gb), gb);
}

fn ldRegInd(gb: *Gb, comptime dst: Dst8) void {
    const val = read(hl(gb));
    dst.write(val, gb);
}

fn ldIndReg(gb: *Gb, comptime src: Src8) void {
    write8(gb, hl(gb), src.read(gb));
}

fn halt(gb: *Gb) void {
    if (gb.ime or (!gb.ime and !gb.anyInterruptsPending())) {
        gb.state = .halted;
    }
}

fn ldReg16Imm16(gb: *Gb, comptime dst: Dst16) void {
    const z = read8PC(gb);
    const w = read8PC(gb);

    write16(gb, dst, as16(w, z));
}

fn ldIndA(gb: *Gb, dst: Dst8) void {
    write8(gb, dst, gb.a);
}

fn incDec16(gb: *Gb, comptime dst: Dst16, comptime mode: IncDec) void {
    const result = if (mode == .inc) dst.read(gb) +% 1 else dst.read(gb) -% 1;
    write16(gb, dst, result);
}

fn incDecReg8(gb: *Gb, comptime dst: Dst8, comptime mode: IncDec) void {
    const carry_prev = gb.carry;
    AluOp.execute(
        if (mode == .inc) .add else .sub,
        dst.getPtr(gb),
        1,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    gb.carry = carry_prev;
}

fn ldRegImm(gb: *Gb, comptime dst: Dst8) void {
    const z = read8PC(gb);
    dst.write(z, gb);
}

fn rotateLeft(gb: *Gb, comptime dst: Dst8) bool {
    const bit_7 = (dst.read(gb) & 0b1000_0000) >> 7;
    dst.write((dst.read(gb) << 1) | bit_7, gb);
    return bit_7 == 1;
}

fn rlca(gb: *Gb) void {
    const carry = rotateLeft(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;
}

fn ldImm16SP(gb: *Gb) void {
    const z = read8PC(gb);
    const w = read8PC(gb);
    const wz = as16(w, z);
    write8(gb, Dst8{ .Ind = wz +% 0 }, @truncate(gb.sp & 0x00ff));
    write8(gb, Dst8{ .Ind = wz +% 1 }, @truncate(gb.sp >> 8));
}
