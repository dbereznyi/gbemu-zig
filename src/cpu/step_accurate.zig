const std = @import("std");
const expect = std.testing.expect;
const as16 = @import("../util.zig").as16;
const incAs16 = @import("../util.zig").incAs16;
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

pub fn stepCpuAccurate(gb: *Gb) void {
    switch (gb.execState) {
        .running => stepCurrentInstr(gb),
        .halted => {
            if (gb.anyInterruptsPending()) {
                gb.ir = 0; // NOP
                gb.execState = .running;
            }
        },
        .handling_interrupt => {
            switch (gb.current_instr_cycle) {
                0 => gb.pc -%= 1,
                1 => gb.sp -%= 1,
                2 => {
                    gb.write(gb.sp, @truncate(gb.pc >> 8));
                    gb.sp -%= 1;
                },
                3 => {
                    gb.write(gb.sp, @truncate(gb.pc));

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

                    gb.ime = false;
                },
                else => {
                    gb.execState = .running;
                    fetchOpcode(gb, .normal);
                    return;
                },
            }
            gb.current_instr_cycle += 1;
        },
        else => {},
    }
}
fn stepCurrentInstr(gb: *Gb) void {
    switch (gb.ir) {
        0x00 => fetchOpcode(gb, .normal),
        0x01 => stepLdReg16Imm16(gb, .BC),
        0x02 => stepLdIndA(gb, .IndBC),
        0x03 => stepIncDec16(gb, .BC, .inc),
        0x04 => stepIncDecReg8(gb, .B, .inc),
        0x05 => stepIncDecReg8(gb, .B, .dec),
        0x06 => stepLdRegImm(gb, .B),
        0x07 => stepRlca(gb),
        0x08 => stepLdImm16SP(gb),
        0x09 => stepAddHLReg16(gb, .BC),
        0x0a => stepLdAInd(gb, .IndBC),
        0x0b => stepIncDec16(gb, .BC, .dec),
        0x0c => stepIncDecReg8(gb, .C, .inc),
        0x0d => stepIncDecReg8(gb, .C, .dec),
        0x0e => stepLdRegImm(gb, .C),
        0x0f => stepRrca(gb),

        0x10 => stepStop(gb),
        0x11 => stepLdReg16Imm16(gb, .DE),
        0x12 => stepLdIndA(gb, .IndDE),
        0x13 => stepIncDec16(gb, .DE, .inc),
        0x14 => stepIncDecReg8(gb, .D, .inc),
        0x15 => stepIncDecReg8(gb, .D, .dec),
        0x16 => stepLdRegImm(gb, .D),
        0x17 => stepRla(gb),
        0x18 => stepJr(gb),
        0x19 => stepAddHLReg16(gb, .DE),
        0x1a => stepLdAInd(gb, .IndDE),
        0x1b => stepIncDec16(gb, .DE, .dec),
        0x1c => stepIncDecReg8(gb, .E, .inc),
        0x1d => stepIncDecReg8(gb, .E, .dec),
        0x1e => stepLdRegImm(gb, .E),
        0x1f => stepRra(gb),

        0x20 => stepJrCond(gb, .NZ),
        0x21 => stepLdReg16Imm16(gb, .HL),
        0x22 => stepLdIndA(gb, .IndHLInc),
        0x23 => stepIncDec16(gb, .HL, .inc),
        0x24 => stepIncDecReg8(gb, .H, .inc),
        0x25 => stepIncDecReg8(gb, .H, .dec),
        0x26 => stepLdRegImm(gb, .H),
        0x27 => stepDaa(gb),
        0x28 => stepJrCond(gb, .Z),
        0x29 => stepAddHLReg16(gb, .HL),
        0x2a => stepLdAInd(gb, .IndHLInc),
        0x2b => stepIncDec16(gb, .HL, .dec),
        0x2c => stepIncDecReg8(gb, .L, .inc),
        0x2d => stepIncDecReg8(gb, .L, .dec),
        0x2e => stepLdRegImm(gb, .L),
        0x2f => stepCpl(gb),

        0x30 => stepJrCond(gb, .NC),
        0x31 => stepLdReg16Imm16(gb, .SP),
        0x32 => stepLdIndA(gb, .IndHLDec),
        0x33 => stepIncDec16(gb, .SP, .inc),
        0x34 => stepIncDecIndHL(gb, .inc),
        0x35 => stepIncDecIndHL(gb, .dec),
        0x36 => stepLdIndHLImm(gb),
        0x37 => stepScf(gb),
        0x38 => stepJrCond(gb, .C),
        0x39 => stepAddHLReg16(gb, .SP),
        0x3a => stepLdAInd(gb, .IndHLDec),
        0x3b => stepIncDec16(gb, .SP, .dec),
        0x3c => stepIncDecReg8(gb, .A, .inc),
        0x3d => stepIncDecReg8(gb, .A, .dec),
        0x3e => stepLdRegImm(gb, .A),
        0x3f => stepCcf(gb),

        // ld r, r
        0x40...0x7f => {
            const src_encoding = @as(u3, @truncate(gb.ir));
            const src = Src8.decode(src_encoding);
            const dst_encoding = @as(u3, @truncate(gb.ir >> 3));
            const dst = Dst8.decode(dst_encoding);

            if (src == .IndHL and dst == .IndHL) {
                stepHalt(gb);
            } else if (src == .IndHL) {
                stepLdRegInd(gb, dst, src);
            } else if (dst == .IndHL) {
                stepLdIndReg(gb, dst, src);
            } else {
                stepLdRegReg(gb, dst, src);
            }
        },

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

fn invalidOpcode(gb: *Gb) void {
    gb.panic("Invalid opcode: ${x:0>2}\n", .{gb.ir});
}

fn handleDebugCmd(gb: *Gb) !void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    try executeDebugCmd(debugCmd, gb);
    gb.debug.acknowledgeCommand();
}

const FetchMode = enum {
    normal,
    halt,
};

fn fetchOpcode(gb: *Gb, comptime mode: FetchMode) void {
    handleDebugCmd(gb) catch {};
    if (shouldDebugBreak(gb)) {
        gb.debug.stdOutMutex.lock();
        std.debug.print("\n", .{});
        gb.printCurrentAndNextInstruction() catch {};
        std.debug.print("\n> ", .{});
        gb.debug.stdOutMutex.unlock();

        gb.debug.setPaused(true);
        gb.debug.stepModeEnabled = true;
    }

    gb.debug.addToExecutionTrace(gb.cart.getBank(gb.pc), gb.pc, decodeInstrAt(gb.pc, gb));

    gb.ir = gb.read(gb.pc);
    if (mode != .halt) {
        gb.pc +%= 1;
    }
    gb.current_instr_cycle = 0;

    if (gb.ime and gb.anyInterruptsPending()) {
        gb.pc -%= 1;
        gb.current_instr_cycle = 1;
        gb.execState = .handling_interrupt;
    }
}

fn stepHalt(gb: *Gb) void {
    if (gb.ime or (!gb.ime and !gb.anyInterruptsPending())) {
        gb.execState = .halted;
    }

    fetchOpcode(gb, .halt);
}

fn stepStop(gb: *Gb) void {
    //gb.panic("TODO: implement STOP instruction\n", .{});
    fetchOpcode(gb, .normal);
}

fn stepLdAInd(gb: *Gb, comptime src: Src8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = src.read(gb);
        },
        else => {
            gb.a = gb.z;

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdAInd16(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            gb.z = gb.read(as16(gb.w, gb.z));
        },
        else => {
            gb.a = gb.z;

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdInd16A(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            gb.write(as16(gb.w, gb.z), gb.a);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdIndIoA(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.write(0xff00 | @as(u16, gb.z), gb.a);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdAIndIo(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.z = gb.read(0xff00 | @as(u16, gb.z));
        },
        else => {
            gb.a = gb.z;

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdIoCA(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.write(0xff00 | @as(u16, gb.c), gb.a);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdAIoC(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(0xff00 | @as(u16, gb.c));
        },
        else => {
            gb.a = gb.z;

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdRegInd(gb: *Gb, dst: Dst8, src: Src8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = src.read(gb);
        },
        else => {
            dst.write(gb.z, gb);
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdIndA(gb: *Gb, dst: Dst8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            dst.write(gb.a, gb);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdIndReg(gb: *Gb, dst: Dst8, src: Src8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            dst.write(src.read(gb), gb);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdIndHLImm(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.write(as16(gb.h, gb.l), gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdRegReg(gb: *Gb, dst: Dst8, src: Src8) void {
    dst.write(src.read(gb), gb);
    fetchOpcode(gb, .normal);
}

fn stepAluOp(gb: *Gb, op: AluOp, src: Src8) void {
    if (src == .IndHL) {
        switch (gb.current_instr_cycle) {
            0 => {
                gb.z = src.read(gb);
            },
            else => {
                op.execute(
                    &gb.a,
                    gb.z,
                    &gb.zero,
                    &gb.negative,
                    &gb.halfCarry,
                    &gb.carry,
                );

                fetchOpcode(gb, .normal);
                return;
            },
        }
        gb.current_instr_cycle += 1;
    } else {
        op.execute(
            &gb.a,
            src.read(gb),
            &gb.zero,
            &gb.negative,
            &gb.halfCarry,
            &gb.carry,
        );

        fetchOpcode(gb, .normal);
    }
}

fn stepAluOpImm(gb: *Gb, comptime op: AluOp) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        else => {
            op.execute(
                &gb.a,
                gb.z,
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdReg16Imm16(gb: *Gb, comptime dst: Dst16) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        else => {
            dst.write(as16(gb.w, gb.z), gb);

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdImm16SP(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            const wz = as16(gb.w, gb.z);
            gb.write(wz, @truncate(gb.sp & 0x00ff));

            incAs16(gb.w, gb.z, &gb.w, &gb.z);
        },
        3 => {
            const wz = as16(gb.w, gb.z);
            gb.write(wz, @truncate(gb.sp >> 8));
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

const IncDec = enum { inc, dec };

fn stepIncDec16(gb: *Gb, comptime dst: Dst16, comptime mode: IncDec) void {
    switch (gb.current_instr_cycle) {
        0 => {
            const result = if (mode == .inc) dst.read(gb) +% 1 else dst.read(gb) -% 1;
            dst.write(result, gb);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepAddHLReg16(gb: *Gb, comptime src: Src16) void {
    switch (gb.current_instr_cycle) {
        0 => {
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
        },
        else => {
            var zero_dummy: bool = undefined;
            AluOp.execute(
                .adc,
                &gb.h,
                src.readUpper(gb),
                &zero_dummy,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepIncDecReg8(gb: *Gb, comptime dst: Dst8, comptime mode: IncDec) void {
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

    fetchOpcode(gb, .normal);
}

fn stepIncDecIndHL(gb: *Gb, comptime mode: IncDec) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(as16(gb.h, gb.l));
        },
        1 => {
            const carry_prev = gb.carry;
            AluOp.execute(
                if (mode == .inc) .add else .sub,
                &gb.z,
                1,
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );
            gb.carry = carry_prev;

            gb.write(as16(gb.h, gb.l), gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdRegImm(gb: *Gb, comptime dst: Dst8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        else => {
            dst.write(gb.z, gb);

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepJp(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepJpHL(gb: *Gb) void {
    gb.pc = as16(gb.h, gb.l);

    fetchOpcode(gb, .normal);
}

fn stepJpCond(gb: *Gb, comptime cond: Cond) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            if (cond.check(gb)) {
                gb.pc = as16(gb.w, gb.z);
            } else {
                fetchOpcode(gb, .normal);
                return;
            }
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
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

fn stepJr(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            calcJrDestAddr(gb.pc, gb.z, &gb.w, &gb.z);
        },
        else => {
            gb.pc = as16(gb.w, gb.z);
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepJrCond(gb: *Gb, comptime cond: Cond) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            if (cond.check(gb)) {
                calcJrDestAddr(gb.pc, gb.z, &gb.w, &gb.z);
            } else {
                fetchOpcode(gb, .normal);
                return;
            }
        },
        else => {
            gb.pc = as16(gb.w, gb.z);
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepCall(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            gb.sp -%= 1;
        },
        3 => {
            gb.write(gb.sp, @truncate(gb.pc >> 8));
            gb.sp -%= 1;
        },
        4 => {
            gb.write(gb.sp, @truncate(gb.pc));
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepCallCond(gb: *Gb, comptime cond: Cond) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        2 => {
            if (cond.check(gb)) {
                gb.sp -%= 1;
            } else {
                fetchOpcode(gb, .normal);
                return;
            }
        },
        3 => {
            // Omitting condition check, since we exit early when false.
            gb.write(gb.sp, @truncate(gb.pc >> 8));
            gb.sp -%= 1;
        },
        4 => {
            gb.write(gb.sp, @truncate(gb.pc));
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRet(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        2 => {
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepReti(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        2 => {
            gb.pc = as16(gb.w, gb.z);
            gb.ime = true;
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRetCond(gb: *Gb, comptime cond: Cond) void {
    switch (gb.current_instr_cycle) {
        0 => {
            if (cond.check(gb)) {
                gb.z = gb.read(gb.sp);
                gb.sp +%= 1;
            }
        },
        1 => {
            if (cond.check(gb)) {
                gb.w = gb.read(gb.sp);
                gb.sp +%= 1;
            } else {
                fetchOpcode(gb, .normal);
                return;
            }
        },
        2 => {
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRst(gb: *Gb, comptime target: u8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.sp -%= 1;
        },
        1 => {
            gb.write(gb.sp, @truncate(gb.pc >> 8));
            gb.sp -%= 1;
        },
        2 => {
            gb.write(gb.sp, @truncate(gb.pc));
            gb.pc = target;
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepPop(gb: *Gb, comptime dst: Dst16) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        1 => {
            gb.w = gb.read(gb.sp);
            gb.sp +%= 1;
        },
        else => {
            dst.write(as16(gb.w, gb.z), gb);

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepPush(gb: *Gb, comptime src: Src16) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.sp -%= 1;
        },
        1 => {
            gb.write(gb.sp, src.readUpper(gb));
            gb.sp -%= 1;
        },
        2 => {
            gb.write(gb.sp, src.readLower(gb));
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn rotateLeft(gb: *Gb, comptime dst: Dst8) bool {
    const bit_7 = (dst.read(gb) & 0b1000_0000) >> 7;
    dst.write((dst.read(gb) << 1) | bit_7, gb);
    return bit_7 == 1;
}

fn stepRlca(gb: *Gb) void {
    const carry = rotateLeft(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;

    fetchOpcode(gb, .normal);
}

fn rotateLeftThroughCarry(gb: *Gb, comptime dst: Dst8) bool {
    const bit_7 = (dst.read(gb) & 0b1000_0000) >> 7;
    const carry: u8 = if (gb.carry) 1 else 0;
    dst.write((dst.read(gb) << 1) | carry, gb);
    return bit_7 == 1;
}

fn stepRla(gb: *Gb) void {
    const carry = rotateLeftThroughCarry(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;

    fetchOpcode(gb, .normal);
}

fn rotateRight(gb: *Gb, comptime dst: Dst8) bool {
    const bit_0 = (dst.read(gb) & 0b0000_0001) << 7;
    dst.write((dst.read(gb) >> 1) | bit_0, gb);
    return bit_0 > 0;
}

fn stepRrca(gb: *Gb) void {
    const carry = rotateRight(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;

    fetchOpcode(gb, .normal);
}

fn rotateRightThroughCarry(gb: *Gb, comptime dst: Dst8) bool {
    const bit_0 = (dst.read(gb) & 0b0000_0001) << 7;
    const carry = @as(u8, if (gb.carry) 1 else 0) << 7;
    dst.write((dst.read(gb) >> 1) | carry, gb);
    return bit_0 > 0;
}

fn stepRra(gb: *Gb) void {
    const carry = rotateRightThroughCarry(gb, Dst8.A);

    gb.zero = false;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = carry;

    fetchOpcode(gb, .normal);
}

fn stepDaa(gb: *Gb) void {
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

    fetchOpcode(gb, .normal);
}

fn stepScf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = true;

    fetchOpcode(gb, .normal);
}

fn stepCcf(gb: *Gb) void {
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = !gb.carry;

    fetchOpcode(gb, .normal);
}

fn stepCpl(gb: *Gb) void {
    gb.a = ~gb.a;

    gb.negative = true;
    gb.halfCarry = true;

    fetchOpcode(gb, .normal);
}

fn stepPrefix(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            const dst: Dst8 = switch (@as(u3, @truncate(gb.z))) {
                0 => .B,
                1 => .C,
                2 => .D,
                3 => .E,
                4 => .H,
                5 => .L,
                6 => .IndHL,
                7 => .A,
            };
            const bit_index: u3 = @as(u3, @truncate(gb.z >> 3));
            gb.prefix_op = switch (gb.z) {
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

            if (dst != .IndHL) {
                const result = PrefixOp.execute(
                    gb.prefix_op,
                    dst.read(gb),
                    &gb.zero,
                    &gb.negative,
                    &gb.halfCarry,
                    &gb.carry,
                );
                if (gb.prefix_op != .bit) {
                    dst.write(result, gb);
                }

                fetchOpcode(gb, .normal);
                return;
            } else {
                gb.z = gb.read(as16(gb.h, gb.l));
            }
        },
        2 => {
            const result = PrefixOp.execute(
                gb.prefix_op,
                gb.z,
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );

            if (gb.prefix_op != .bit) {
                gb.write(as16(gb.h, gb.l), result);
            } else {
                fetchOpcode(gb, .normal);
                return;
            }
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepDi(gb: *Gb) void {
    gb.cycles_until_ei = 0;
    gb.ime = false;

    fetchOpcode(gb, .normal);
}

fn stepEi(gb: *Gb) void {
    gb.cycles_until_ei = 2;

    fetchOpcode(gb, .normal);
}

fn stepAddSPe8(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.w = gb.z; // storing copy of z to use on next cycle
            AluOp.execute(
                .add,
                &gb.z,
                @truncate(gb.sp),
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );
            gb.zero = false;
            gb.negative = false;
        },
        2 => {
            const adj: u8 = if (gb.w & 0b1000_0000 > 1) 0xff else 0x00;
            gb.w = @truncate(gb.sp >> 8);
            var half_carry_dummy: bool = undefined;
            var carry_dummy: bool = gb.carry;
            AluOp.execute(
                .adc,
                &gb.w,
                adj,
                &gb.zero,
                &gb.negative,
                &half_carry_dummy,
                &carry_dummy,
            );
            gb.zero = false;
            gb.negative = false;
        },
        else => {
            gb.sp = as16(gb.w, gb.z);

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdHLSPe8(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            gb.l = @truncate(gb.sp);
            AluOp.execute(
                .add,
                &gb.l,
                gb.z,
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );
            gb.zero = false;
            gb.negative = false;
        },
        else => {
            const adj: u8 = if (gb.z & 0b1000_0000 > 1) 0xff else 0x00;
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

            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdSPHL(gb: *Gb) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.sp = as16(gb.h, gb.l);
        },
        else => {
            fetchOpcode(gb, .normal);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}
