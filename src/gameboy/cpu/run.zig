const std = @import("std");
const advanceGameboy = @import("../timing.zig").advanceGameboy;
const syncTime = @import("../timing.zig").syncTime;
const expect = std.testing.expect;
const as16 = @import("../../util.zig").as16;
const incAs16 = @import("../../util.zig").incAs16;
const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;
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
const runDma = @import("../dma/run.zig").runDma;

pub fn runCpu(gb: *Gb) void {
    if (gb.halted) {
        advanceGameboy(gb, 4);
    }

    const effective_ime = gb.ime;
    if (gb.toggle_ime) {
        gb.ime = !gb.ime;
        gb.toggle_ime = false;
    }

    const interrupts_pending = gb.anyInterruptsPending();

    if (gb.halted and !effective_ime and interrupts_pending) {
        gb.halted = false;

        gb.dma.cycles = 4;
        runDma(gb);
    } else if (effective_ime and interrupts_pending) {
        gb.halted = false;

        gb.dma.cycles = 4;
        runDma(gb);

        cycleStall(gb);
        cycleStall(gb);

        gb.sp -%= 1;
        cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc >> 8));

        gb.sp -%= 1;
        cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc));

        if (gb.isInterruptPending(Interrupt.VBLANK)) {
            gb.pc = 0x0040;
            gb.clearInterrupt(Interrupt.VBLANK);
        } else if (gb.isInterruptPending(Interrupt.STAT)) {
            gb.pc = 0x0048;
            gb.clearInterrupt(Interrupt.STAT);
        } else if (gb.isInterruptPending(Interrupt.TIMER)) {
            gb.pc = 0x0050;
            gb.clearInterrupt(Interrupt.TIMER);
        } else if (gb.isInterruptPending(Interrupt.SERIAL)) {
            gb.pc = 0x0058;
            gb.clearInterrupt(Interrupt.SERIAL);
        } else if (gb.isInterruptPending(Interrupt.JOYPAD)) {
            gb.pc = 0x0060;
            gb.clearInterrupt(Interrupt.JOYPAD);
        }
        cycleStall(gb);

        tryDebugBreak(gb);

        gb.ime = false;
    } else if (!gb.halted) {
        gb.debug.addToExecutionTrace(
            gb.cart.getBank(gb.pc),
            gb.pc,
            decodeInstrAt(gb.pc, gb),
        );

        const opcode = cycleReadPC(gb);

        if (gb.halt_bug) {
            gb.pc -%= 1;
            gb.halt_bug = false;
        }

        executeInstr(gb, opcode);

        tryDebugBreak(gb);
    }

    flushPendingCycles(gb);
}

fn tryDebugBreak(gb: *Gb) void {
    if (shouldDebugBreak(gb)) {
        gb.debug.stdOutMutex.lock();
        std.debug.print("\n", .{});
        gb.printDebugTrace() catch {};
        std.debug.print("\n> ", .{});
        gb.debug.stdOutMutex.unlock();

        gb.debug.setPaused(true);
        gb.debug.stepModeEnabled = true;
    }
}

fn cycleRead(gb: *Gb, src: Src8) u8 {
    if (gb.pending_cycles > 0) {
        advanceGameboy(gb, gb.pending_cycles);
    }
    gb.pending_cycles = 4;

    return src.read(gb);
}

fn cycleReadPC(gb: *Gb) u8 {
    const val = cycleRead(gb, Src8{ .Ind = gb.pc });
    gb.pc +%= 1;
    return val;
}

fn cycleWrite(gb: *Gb, dst: Dst8, val: u8) void {
    advanceGameboy(gb, gb.pending_cycles);
    dst.write(val, gb);
    gb.pending_cycles = 4;
}

// Special case for instructions where 2 bytes are written in only 1 M-cycle.
fn cycleWrite16(gb: *Gb, dst: Dst16, val: u16) void {
    advanceGameboy(gb, gb.pending_cycles);
    dst.write(val, gb);
    gb.pending_cycles = 4;
}

// PC can be written in just 1 M-cycle.
fn cycleWritePC(gb: *Gb, val: u16) void {
    advanceGameboy(gb, gb.pending_cycles);
    gb.pc = val;
    gb.pending_cycles = 4;
}

// Stall for 1 M-cycle.
fn cycleStall(gb: *Gb) void {
    gb.pending_cycles += 4;
}

fn flushPendingCycles(gb: *Gb) void {
    if (gb.pending_cycles > 0) {
        advanceGameboy(gb, gb.pending_cycles);
    }
    gb.pending_cycles = 0;
}

const IncDec = enum { inc, dec };

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
        0x09 => addHLReg16(gb, .BC),
        0x0a => ldAInd(gb, .IndBC),
        0x0b => incDec16(gb, .BC, .dec),
        0x0c => incDecReg8(gb, .C, .inc),
        0x0d => incDecReg8(gb, .C, .dec),
        0x0e => ldRegImm(gb, .C),
        0x0f => rrca(gb),

        0x10 => stop(gb),
        0x11 => ldReg16Imm16(gb, .DE),
        0x12 => ldIndA(gb, .IndDE),
        0x13 => incDec16(gb, .DE, .inc),
        0x14 => incDecReg8(gb, .D, .inc),
        0x15 => incDecReg8(gb, .D, .dec),
        0x16 => ldRegImm(gb, .D),
        0x17 => rla(gb),
        0x18 => jr(gb),
        0x19 => addHLReg16(gb, .DE),
        0x1a => ldAInd(gb, .IndDE),
        0x1b => incDec16(gb, .DE, .dec),
        0x1c => incDecReg8(gb, .E, .inc),
        0x1d => incDecReg8(gb, .E, .dec),
        0x1e => ldRegImm(gb, .E),
        0x1f => rra(gb),

        0x20 => jrCond(gb, .NZ),
        0x21 => ldReg16Imm16(gb, .HL),
        0x22 => ldIndA(gb, .IndHLInc),
        0x23 => incDec16(gb, .HL, .inc),
        0x24 => incDecReg8(gb, .H, .inc),
        0x25 => incDecReg8(gb, .H, .dec),
        0x26 => ldRegImm(gb, .H),
        0x27 => daa(gb),
        0x28 => jrCond(gb, .Z),
        0x29 => addHLReg16(gb, .HL),
        0x2a => ldAInd(gb, .IndHLInc),
        0x2b => incDec16(gb, .HL, .dec),
        0x2c => incDecReg8(gb, .L, .inc),
        0x2d => incDecReg8(gb, .L, .dec),
        0x2e => ldRegImm(gb, .L),
        0x2f => cpl(gb),

        0x30 => jrCond(gb, .NC),
        0x31 => ldReg16Imm16(gb, .SP),
        0x32 => ldIndA(gb, .IndHLDec),
        0x33 => incDec16(gb, .SP, .inc),
        0x34 => incDecIndHL(gb, .inc),
        0x35 => incDecIndHL(gb, .dec),
        0x36 => ldIndHLImm(gb),
        0x37 => scf(gb),
        0x38 => jrCond(gb, .C),
        0x39 => addHLReg16(gb, .SP),
        0x3a => ldAInd(gb, .IndHLDec),
        0x3b => incDec16(gb, .SP, .dec),
        0x3c => incDecReg8(gb, .A, .inc),
        0x3d => incDecReg8(gb, .A, .dec),
        0x3e => ldRegImm(gb, .A),
        0x3f => ccf(gb),

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
        0x77 => ldIndReg(gb, .A),
        0x78 => ldRegReg(gb, .A, .B),
        0x79 => ldRegReg(gb, .A, .C),
        0x7a => ldRegReg(gb, .A, .D),
        0x7b => ldRegReg(gb, .A, .E),
        0x7c => ldRegReg(gb, .A, .H),
        0x7d => ldRegReg(gb, .A, .L),
        0x7e => ldRegInd(gb, .A),
        0x7f => ldRegReg(gb, .A, .A),

        0x80 => aluOpReg(gb, .add, .B),
        0x81 => aluOpReg(gb, .add, .C),
        0x82 => aluOpReg(gb, .add, .D),
        0x83 => aluOpReg(gb, .add, .E),
        0x84 => aluOpReg(gb, .add, .H),
        0x85 => aluOpReg(gb, .add, .L),
        0x86 => aluOpIndHL(gb, .add),
        0x87 => aluOpReg(gb, .add, .A),
        0x88 => aluOpReg(gb, .adc, .B),
        0x89 => aluOpReg(gb, .adc, .C),
        0x8a => aluOpReg(gb, .adc, .D),
        0x8b => aluOpReg(gb, .adc, .E),
        0x8c => aluOpReg(gb, .adc, .H),
        0x8d => aluOpReg(gb, .adc, .L),
        0x8e => aluOpIndHL(gb, .adc),
        0x8f => aluOpReg(gb, .adc, .A),

        0x90 => aluOpReg(gb, .sub, .B),
        0x91 => aluOpReg(gb, .sub, .C),
        0x92 => aluOpReg(gb, .sub, .D),
        0x93 => aluOpReg(gb, .sub, .E),
        0x94 => aluOpReg(gb, .sub, .H),
        0x95 => aluOpReg(gb, .sub, .L),
        0x96 => aluOpIndHL(gb, .sub),
        0x97 => aluOpReg(gb, .sub, .A),
        0x98 => aluOpReg(gb, .sbc, .B),
        0x99 => aluOpReg(gb, .sbc, .C),
        0x9a => aluOpReg(gb, .sbc, .D),
        0x9b => aluOpReg(gb, .sbc, .E),
        0x9c => aluOpReg(gb, .sbc, .H),
        0x9d => aluOpReg(gb, .sbc, .L),
        0x9e => aluOpIndHL(gb, .sbc),
        0x9f => aluOpReg(gb, .sbc, .A),

        0xa0 => aluOpReg(gb, .and_, .B),
        0xa1 => aluOpReg(gb, .and_, .C),
        0xa2 => aluOpReg(gb, .and_, .D),
        0xa3 => aluOpReg(gb, .and_, .E),
        0xa4 => aluOpReg(gb, .and_, .H),
        0xa5 => aluOpReg(gb, .and_, .L),
        0xa6 => aluOpIndHL(gb, .and_),
        0xa7 => aluOpReg(gb, .and_, .A),
        0xa8 => aluOpReg(gb, .xor, .B),
        0xa9 => aluOpReg(gb, .xor, .C),
        0xaa => aluOpReg(gb, .xor, .D),
        0xab => aluOpReg(gb, .xor, .E),
        0xac => aluOpReg(gb, .xor, .H),
        0xad => aluOpReg(gb, .xor, .L),
        0xae => aluOpIndHL(gb, .xor),
        0xaf => aluOpReg(gb, .xor, .A),

        0xb0 => aluOpReg(gb, .or_, .B),
        0xb1 => aluOpReg(gb, .or_, .C),
        0xb2 => aluOpReg(gb, .or_, .D),
        0xb3 => aluOpReg(gb, .or_, .E),
        0xb4 => aluOpReg(gb, .or_, .H),
        0xb5 => aluOpReg(gb, .or_, .L),
        0xb6 => aluOpIndHL(gb, .or_),
        0xb7 => aluOpReg(gb, .or_, .A),
        0xb8 => aluOpReg(gb, .cp, .B),
        0xb9 => aluOpReg(gb, .cp, .C),
        0xba => aluOpReg(gb, .cp, .D),
        0xbb => aluOpReg(gb, .cp, .E),
        0xbc => aluOpReg(gb, .cp, .H),
        0xbd => aluOpReg(gb, .cp, .L),
        0xbe => aluOpIndHL(gb, .cp),
        0xbf => aluOpReg(gb, .cp, .A),

        0xc0 => retCond(gb, .NZ),
        0xc1 => pop(gb, .BC),
        0xc2 => jpCond(gb, .NZ),
        0xc3 => jp(gb),
        0xc4 => callCond(gb, .NZ),
        0xc5 => push(gb, .BC),
        0xc6 => aluOpImm(gb, .add),
        0xc7 => rst(gb, 0x00),
        0xc8 => retCond(gb, .Z),
        0xc9 => ret(gb),
        0xca => jpCond(gb, .Z),
        0xcb => prefix(gb),
        0xcc => callCond(gb, .Z),
        0xcd => call(gb),
        0xce => aluOpImm(gb, .adc),
        0xcf => rst(gb, 0x08),

        0xd0 => retCond(gb, .NC),
        0xd1 => pop(gb, .DE),
        0xd2 => jpCond(gb, .NC),
        0xd3 => invalidOpcode(gb, opcode),
        0xd4 => callCond(gb, .NC),
        0xd5 => push(gb, .DE),
        0xd6 => aluOpImm(gb, .sub),
        0xd7 => rst(gb, 0x10),
        0xd8 => retCond(gb, .C),
        0xd9 => reti(gb),
        0xda => jpCond(gb, .C),
        0xdb => invalidOpcode(gb, opcode),
        0xdc => callCond(gb, .C),
        0xdd => invalidOpcode(gb, opcode),
        0xde => aluOpImm(gb, .sbc),
        0xdf => rst(gb, 0x18),

        0xe0 => ldIndIoA(gb),
        0xe1 => pop(gb, .HL),
        0xe2 => ldIoCA(gb),
        0xe3 => invalidOpcode(gb, opcode),
        0xe4 => invalidOpcode(gb, opcode),
        0xe5 => push(gb, .HL),
        0xe6 => aluOpImm(gb, .and_),
        0xe7 => rst(gb, 0x20),
        0xe8 => addSPe8(gb),
        0xe9 => jpHL(gb),
        0xea => ldInd16A(gb),
        0xeb => invalidOpcode(gb, opcode),
        0xec => invalidOpcode(gb, opcode),
        0xed => invalidOpcode(gb, opcode),
        0xee => aluOpImm(gb, .xor),
        0xef => rst(gb, 0x28),

        0xf0 => ldAIndIo(gb),
        0xf1 => pop(gb, .AF),
        0xf2 => ldAIoC(gb),
        0xf3 => di(gb),
        0xf4 => invalidOpcode(gb, opcode),
        0xf5 => push(gb, .AF),
        0xf6 => aluOpImm(gb, .or_),
        0xf7 => rst(gb, 0x30),
        0xf8 => ldHLSPe8(gb),
        0xf9 => ldSPHL(gb),
        0xfa => ldAInd16(gb),
        0xfb => ei(gb),
        0xfc => invalidOpcode(gb, opcode),
        0xfd => invalidOpcode(gb, opcode),
        0xfe => aluOpImm(gb, .cp),
        0xff => rst(gb, 0x38),
    }
}

fn invalidOpcode(gb: *Gb, opcode: u8) void {
    gb.panic("Invalid opcode: ${x:0>2}\n", .{opcode});
}

fn ldRegReg(gb: *Gb, comptime dst: Dst8, comptime src: Src8) void {
    dst.write(src.read(gb), gb);
}

fn ldRegInd(gb: *Gb, comptime dst: Dst8) void {
    const val = cycleRead(gb, Src8.IndHL);
    dst.write(val, gb);
}

fn ldIndReg(gb: *Gb, comptime src: Src8) void {
    cycleWrite(gb, Dst8.IndHL, src.read(gb));
}

fn halt(gb: *Gb) void {
    _ = cycleRead(gb, Src8{ .Ind = gb.pc });
    gb.pending_cycles = 0;

    if (gb.anyInterruptsPending()) {
        gb.halted = false;

        if (gb.ime) {
            gb.pc -%= 1;
        } else {
            gb.halt_bug = true;
        }
    } else {
        gb.halted = true;
    }
}

fn ldReg16Imm16(gb: *Gb, comptime dst: Dst16) void {
    const low = cycleReadPC(gb);
    const high = cycleReadPC(gb);

    cycleWrite16(gb, dst, as16(high, low));
}

fn ldIndA(gb: *Gb, dst: Dst8) void {
    cycleWrite(gb, dst, gb.a);
}

fn incDec16(gb: *Gb, comptime dst: Dst16, comptime mode: IncDec) void {
    const result = if (mode == .inc) dst.read(gb) +% 1 else dst.read(gb) -% 1;
    cycleWrite16(gb, dst, result);
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
    const z = cycleReadPC(gb);
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
    const low = cycleReadPC(gb);
    const high = cycleReadPC(gb);
    const addr = as16(high, low);
    cycleWrite(gb, Dst8{ .Ind = addr +% 0 }, @truncate(gb.sp));
    cycleWrite(gb, Dst8{ .Ind = addr +% 1 }, @truncate(gb.sp >> 8));
}

fn addHLReg16(gb: *Gb, comptime src: Src16) void {
    var zero_dummy: bool = undefined;

    AluOp.execute(
        .add,
        &gb.l,
        src.readLower(gb),
        &zero_dummy,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    cycleStall(gb);

    AluOp.execute(
        .adc,
        &gb.h,
        src.readUpper(gb),
        &zero_dummy,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
}

fn ldAIndIo(gb: *Gb) void {
    const offset = cycleReadPC(gb);
    const val = cycleRead(gb, Src8{ .Ind = 0xff00 | @as(u16, offset) });
    gb.a = val;
}

fn ldAInd(gb: *Gb, comptime src: Src8) void {
    const val = cycleRead(gb, src);
    gb.a = val;
}

fn rotateRight(gb: *Gb, comptime dst: Dst8) bool {
    const bit_0 = (dst.read(gb) & 0b0000_0001) << 7;
    dst.write((dst.read(gb) >> 1) | bit_0, gb);
    return bit_0 > 0;
}

fn rrca(gb: *Gb) void {
    const carry = rotateRight(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;
}

fn stop(gb: *Gb) void {
    // TODO implement properly
    gb.stopped = true;
}

fn rotateLeftThroughCarry(gb: *Gb, comptime dst: Dst8) bool {
    const bit_7 = (dst.read(gb) & 0b1000_0000) >> 7;
    const carry: u8 = if (gb.carry) 1 else 0;
    dst.write((dst.read(gb) << 1) | carry, gb);
    return bit_7 == 1;
}

fn rla(gb: *Gb) void {
    const carry = rotateLeftThroughCarry(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;
}

fn calcJrDestAddr(pc: u16, offset: u8, dest_upper: *u8, dest_lower: *u8) void {
    const offset_negative = offset & 0b1000_0000 > 0;

    const result = @addWithOverflow(offset, @as(u8, @truncate(pc)));
    dest_lower.* = result[0];
    const adj: u8 = blk: {
        if (result[1] == 1 and !offset_negative) {
            break :blk 1;
        }
        if (result[1] == 0 and offset_negative) {
            break :blk @bitCast(@as(i8, -1));
        }
        break :blk 0;
    };
    dest_upper.* = @as(u8, @truncate(pc >> 8)) +% adj;
}

test "calcJrDestAddr" {
    const TestCase = struct {
        pc: u16,
        offset: i8,
        result: u16,
    };
    const cases = [_]TestCase{
        .{ .pc = 0x4000, .offset = 12, .result = 0x400c },
        .{ .pc = 0x45a0, .offset = -3, .result = 0x459d },
        .{ .pc = 0x2002, .offset = -127, .result = 0x1f83 },
    };

    for (cases) |case| {
        var result_upper: u8 = 0x00;
        var result_lower: u8 = 0x00;
        calcJrDestAddr(case.pc, @bitCast(case.offset), &result_upper, &result_lower);
        try expect(result_upper == @as(u8, @truncate(case.result >> 8)));
        try expect(result_lower == @as(u8, @truncate(case.result)));
    }
}

fn jr(gb: *Gb) void {
    const offset = cycleReadPC(gb);

    var dest_upper: u8 = undefined;
    var dest_lower: u8 = undefined;
    calcJrDestAddr(gb.pc, offset, &dest_upper, &dest_lower);
    cycleStall(gb);

    gb.pc = as16(dest_upper, dest_lower);
}

fn rotateRightThroughCarry(gb: *Gb, comptime dst: Dst8) bool {
    const bit_0 = (dst.read(gb) & 0b0000_0001) << 7;
    const carry = @as(u8, if (gb.carry) 1 else 0) << 7;
    dst.write((dst.read(gb) >> 1) | carry, gb);
    return bit_0 > 0;
}

fn rra(gb: *Gb) void {
    const carry = rotateRightThroughCarry(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;
}

fn jrCond(gb: *Gb, comptime cond: Cond) void {
    const offset = cycleReadPC(gb);

    if (cond.check(gb)) {
        var low: u8 = undefined;
        var high: u8 = undefined;
        calcJrDestAddr(gb.pc, offset, &high, &low);
        cycleStall(gb);

        gb.pc = as16(high, low);
    }
}

fn daa(gb: *Gb) void {
    if (gb.negative) {
        if (gb.carry) {
            gb.a -%= 0x60;
        }
        if (gb.halfCarry) {
            gb.a -%= 0x06;
        }
    } else {
        if (gb.carry or gb.a > 0x99) {
            gb.a +%= 0x60;
            gb.carry = true;
        }
        if (gb.halfCarry or (gb.a & 0x0f) > 0x09) {
            gb.a +%= 0x06;
        }
    }

    gb.zero = gb.a == 0;
    gb.halfCarry = false;
}

fn cpl(gb: *Gb) void {
    gb.a = ~gb.a;

    gb.negative = true;
    gb.halfCarry = true;
}

fn incDecIndHL(gb: *Gb, comptime mode: IncDec) void {
    var val = cycleRead(gb, Src8.IndHL);

    const carry_prev = gb.carry;
    AluOp.execute(
        if (mode == .inc) .add else .sub,
        &val,
        1,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    gb.carry = carry_prev;
    cycleWrite(gb, Dst8.IndHL, val);
}

fn ldIndHLImm(gb: *Gb) void {
    const val = cycleReadPC(gb);
    cycleWrite(gb, Dst8.IndHL, val);
}

fn scf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = true;
}

fn ccf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = !gb.carry;
}

fn aluOpReg(gb: *Gb, comptime op: AluOp, comptime src: Src8) void {
    op.execute(
        &gb.a,
        src.read(gb),
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
}

fn aluOpIndHL(gb: *Gb, comptime op: AluOp) void {
    const val = cycleRead(gb, Src8.IndHL);

    op.execute(
        &gb.a,
        val,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
}

fn retCond(gb: *Gb, comptime cond: Cond) void {
    cycleStall(gb); // CPU checks condition on this cycle.

    if (cond.check(gb)) {
        const addr_low = cycleRead(gb, Src8{ .Ind = gb.sp });
        gb.sp +%= 1;

        const addr_high = cycleRead(gb, Src8{ .Ind = gb.sp });
        gb.sp +%= 1;

        cycleWritePC(gb, as16(addr_high, addr_low));
    }
}

fn pop(gb: *Gb, comptime dst: Dst16) void {
    const low = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;

    const high = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;

    dst.write(as16(high, low), gb);
}

fn jpCond(gb: *Gb, comptime cond: Cond) void {
    const addr_low = cycleReadPC(gb);
    const addr_high = cycleReadPC(gb);
    if (cond.check(gb)) {
        cycleWritePC(gb, as16(addr_high, addr_low));
    }
}

fn jp(gb: *Gb) void {
    const addr_low = cycleReadPC(gb);
    const addr_high = cycleReadPC(gb);
    cycleWritePC(gb, as16(addr_high, addr_low));
}

fn jpHL(gb: *Gb) void {
    gb.pc = as16(gb.h, gb.l);
}

fn callCond(gb: *Gb, comptime cond: Cond) void {
    const addr_low = cycleReadPC(gb);
    const addr_high = cycleReadPC(gb);

    if (cond.check(gb)) {
        gb.sp -%= 1;
        cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc >> 8));

        gb.sp -%= 1;
        cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc));

        cycleWritePC(gb, as16(addr_high, addr_low));
    }
}

fn push(gb: *Gb, comptime src: Src16) void {
    gb.sp -%= 1;
    cycleStall(gb); // For ???

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, src.readUpper(gb));
    gb.sp -%= 1;

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, src.readLower(gb));
}

fn aluOpImm(gb: *Gb, comptime op: AluOp) void {
    const val = cycleReadPC(gb);

    op.execute(
        &gb.a,
        val,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
}

fn rst(gb: *Gb, comptime target: u8) void {
    gb.sp -%= 1;
    cycleStall(gb); // For ???

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc >> 8));
    gb.sp -%= 1;

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc));
    gb.sp -%= 1;

    gb.pc = target;
}

fn ret(gb: *Gb) void {
    const low = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;
    const high = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;

    cycleWritePC(gb, as16(high, low));
}

fn reti(gb: *Gb) void {
    const low = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;
    const high = cycleRead(gb, Src8{ .Ind = gb.sp });
    gb.sp +%= 1;

    cycleWritePC(gb, as16(high, low));
    gb.ime = true;
}

fn prefix(gb: *Gb) void {
    const opcode = cycleReadPC(gb);

    const dst: Dst8 = switch (@as(u3, @truncate(opcode))) {
        0 => .B,
        1 => .C,
        2 => .D,
        3 => .E,
        4 => .H,
        5 => .L,
        6 => .IndHL,
        7 => .A,
    };
    const bit_index: u3 = @as(u3, @truncate(opcode >> 3));
    const prefix_op: PrefixOp = switch (opcode) {
        0x00...0x07 => .rlc,
        0x08...0x0f => .rrc,
        0x10...0x17 => .rl,
        0x18...0x1f => .rr,
        0x20...0x27 => .sla,
        0x28...0x2f => .sra,
        0x30...0x37 => .swap,
        0x38...0x3f => .srl,
        0x40...0x7f => .{ .bit = bit_index },
        0x80...0xbf => .{ .res = bit_index },
        0xc0...0xff => .{ .set = bit_index },
    };

    const val = if (dst == .IndHL) cycleRead(gb, Src8.IndHL) else dst.read(gb);

    const result = PrefixOp.execute(
        prefix_op,
        val,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    if (prefix_op != .bit) {
        if (dst == .IndHL) cycleWrite(gb, Dst8.IndHL, result) else dst.write(result, gb);
    }
}

fn call(gb: *Gb) void {
    const low = cycleReadPC(gb);
    const high = cycleReadPC(gb);

    gb.sp -%= 1;
    cycleStall(gb); // For ???

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc >> 8));
    gb.sp -%= 1;

    cycleWrite(gb, Dst8{ .Ind = gb.sp }, @truncate(gb.pc));

    gb.pc = as16(high, low);
}

fn ldIndIoA(gb: *Gb) void {
    const val = cycleReadPC(gb);

    cycleWrite(gb, Dst8{ .Ind = 0xff00 | @as(u16, val) }, gb.a);
}

fn ldIoCA(gb: *Gb) void {
    cycleWrite(gb, Dst8{ .Ind = 0xff00 | @as(u16, gb.c) }, gb.a);
}

fn addSPe8(gb: *Gb) void {
    const val = cycleReadPC(gb);

    var sp_low = val;
    AluOp.execute(
        .add,
        &sp_low,
        @truncate(gb.sp),
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    gb.zero = false;
    gb.negative = false;
    cycleStall(gb);

    const adj: u8 = if (val & 0b1000_0000 > 0) 0xff else 0x00;
    var sp_high: u8 = @truncate(gb.sp >> 8);
    var half_carry_dummy: bool = undefined;
    var carry_dummy: bool = gb.carry;
    AluOp.execute(
        .adc,
        &sp_high,
        adj,
        &gb.zero,
        &gb.negative,
        &half_carry_dummy,
        &carry_dummy,
    );
    gb.zero = false;
    gb.negative = false;
    cycleStall(gb);

    gb.sp = as16(sp_high, sp_low);
    cycleStall(gb);
}

fn ldInd16A(gb: *Gb) void {
    const low = cycleReadPC(gb);
    const high = cycleReadPC(gb);
    cycleWrite(gb, Dst8{ .Ind = as16(high, low) }, gb.a);
}

fn ldAIoC(gb: *Gb) void {
    const val = cycleRead(gb, Src8{ .Ind = 0xff00 | @as(u16, gb.c) });

    gb.a = val;
}

fn di(gb: *Gb) void {
    gb.ime = false;
}

fn ei(gb: *Gb) void {
    if (!gb.ime and !gb.toggle_ime) {
        gb.toggle_ime = true;
    }
}

fn ldHLSPe8(gb: *Gb) void {
    const val = cycleReadPC(gb);

    gb.l = @truncate(gb.sp);
    AluOp.execute(
        .add,
        &gb.l,
        val,
        &gb.zero,
        &gb.negative,
        &gb.halfCarry,
        &gb.carry,
    );
    gb.zero = false;
    gb.negative = false;
    cycleStall(gb);

    const adj: u8 = if (val & 0b1000_0000 > 1) 0xff else 0x00;
    gb.h = @truncate(gb.sp >> 8);
    var half_carry_dummy: bool = undefined;
    var carry_dummy: bool = gb.carry;
    AluOp.execute(
        .adc,
        &gb.h,
        adj,
        &gb.zero,
        &gb.negative,
        &half_carry_dummy,
        &carry_dummy,
    );
    gb.zero = false;
    gb.negative = false;
}

fn ldSPHL(gb: *Gb) void {
    gb.sp = as16(gb.h, gb.l);
    cycleStall(gb);
}

fn ldAInd16(gb: *Gb) void {
    const low = cycleReadPC(gb);
    const high = cycleReadPC(gb);
    const val = cycleRead(gb, Src8{ .Ind = as16(high, low) });
    gb.a = val;
}
