const std = @import("std");
const expect = std.testing.expect;
const as16 = @import("../util.zig").as16;
const incAs16 = @import("../util.zig").incAs16;
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const executeCurrentInstruction = @import("execute.zig").executeCurrentInstruction;
const Cond = @import("operand.zig").Cond;
const Src8 = @import("operand.zig").Src8;
const Src16 = @import("operand.zig").Src16;
const Dst8 = @import("operand.zig").Dst8;
const Dst16 = @import("operand.zig").Dst16;

pub fn stepCpu(gb: *Gb) u64 {
    const interruptPending = gb.ime and gb.anyInterruptsPending();

    switch (gb.execState) {
        .running => {
            if (interruptPending) {
                handleInterrupt(gb);
                return 5;
            }
            return executeCurrentInstruction(gb);
        },
        .halted => {
            if (interruptPending) {
                handleInterrupt(gb);
                gb.execState = .running;
                return 5;
            }
            return 1;
        },
        .haltedDiscardInterrupt => {
            if (interruptPending) {
                discardInterrupt(gb);
                gb.execState = .running;
                return 5; // TODO probably not accurate
            }
            return 1;
        },
        .stopped => {
            // TODO handle properly
            std.log.info("STOP was executed\n", .{});
            return 1;
        },
    }
}

fn handleInterrupt(gb: *Gb) void {
    if (gb.isInterruptPending(Interrupt.VBLANK)) {
        gb.push16(gb.pc);
        gb.pc = 0x0040;
        gb.clearInterrupt(Interrupt.VBLANK);
        gb.ime = false;
    } else if (gb.isInterruptPending(Interrupt.STAT)) {
        gb.push16(gb.pc);
        gb.pc = 0x0048;
        gb.clearInterrupt(Interrupt.STAT);
        gb.ime = false;
    } else if (gb.isInterruptPending(Interrupt.TIMER)) {
        gb.push16(gb.pc);
        gb.pc = 0x0050;
        gb.clearInterrupt(Interrupt.TIMER);
        gb.ime = false;
    } else if (gb.isInterruptPending(Interrupt.SERIAL)) {
        gb.push16(gb.pc);
        gb.pc = 0x0058;
        gb.clearInterrupt(Interrupt.SERIAL);
        gb.ime = false;
    } else if (gb.isInterruptPending(Interrupt.JOYPAD)) {
        gb.push16(gb.pc);
        gb.pc = 0x0060;
        gb.clearInterrupt(Interrupt.JOYPAD);
        gb.ime = false;
    }
}

fn discardInterrupt(gb: *Gb) void {
    if (gb.isInterruptPending(Interrupt.VBLANK)) {
        gb.clearInterrupt(Interrupt.VBLANK);
    } else if (gb.isInterruptPending(Interrupt.STAT)) {
        gb.clearInterrupt(Interrupt.STAT);
    } else if (gb.isInterruptPending(Interrupt.TIMER)) {
        gb.clearInterrupt(Interrupt.TIMER);
    } else if (gb.isInterruptPending(Interrupt.SERIAL)) {
        gb.clearInterrupt(Interrupt.SERIAL);
    } else if (gb.isInterruptPending(Interrupt.JOYPAD)) {
        gb.clearInterrupt(Interrupt.JOYPAD);
    }
}

pub fn stepCpuAccurate(gb: *Gb) void {
    switch (gb.execState) {
        .running => {
            // Execute a single cycle of the current instruction.
            stepCurrentInstr(gb);
        },
        else => {},
    }
}

const AluOp = enum {
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
                halfCarry.* = checkHalfCarry8(x, y);
                carry.* = checkCarry8(x, y);

                dst.* = result;
            },
            .adc => {
                const x = dst.*;
                const y = src +% if (carry.*) @as(u8, 1) else @as(u8, 0);
                const result = x +% y;

                zero.* = result == 0;
                negative.* = false;
                halfCarry.* = checkHalfCarry8(x, y);
                carry.* = checkCarry8(x, y);

                dst.* = result;
            },
            .sub => {
                const x = dst.*;
                const y = ~src +% 1;
                const result = x +% y;

                zero.* = result == 0;
                negative.* = true;
                halfCarry.* = checkHalfCarry8(x, y);
                carry.* = checkCarry8(x, y);

                dst.* = result;
            },
            .sbc => {
                const x = dst.*;
                const y = ~(src +% if (carry.*) @as(u8, 1) else @as(u8, 0)) +% 1;
                const result = x +% y;

                zero.* = result == 0;
                negative.* = true;
                halfCarry.* = checkHalfCarry8(x, y);
                carry.* = checkCarry8(x, y);

                dst.* = result;
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
                const x = dst.*;
                const y = ~src +% 1;
                const result = x +% y;

                zero.* = result == 0;
                negative.* = true;
                halfCarry.* = checkHalfCarry8(x, y);
                carry.* = checkCarry8(x, y);
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

fn checkCarry8(x: u8, y: u8) bool {
    return @addWithOverflow(x, y)[1] == 1;
}

fn checkHalfCarry8(x: u8, y: u8) bool {
    return (((x & 0x0f) + (y & 0x0f)) & 0x10) == 0x10;
}

fn stepCurrentInstr(gb: *Gb) void {
    switch (gb.ir) {
        0x00 => fetchOpcode(gb),
        0x01 => stepLdReg16Imm16(gb, Dst16.BC),
        0x02 => stepLdIndA(gb, Dst8.IndBC),
        0x03 => stepIncDec16(gb, Dst16.BC, .inc),
        0x04 => stepIncDecReg8(gb, Dst8.B, .inc),
        0x05 => stepIncDecReg8(gb, Dst8.B, .dec),
        0x06 => stepLdRegImm(gb, Dst8.B),
        0x07 => stepRlca(gb),
        0x08 => stepLdImm16SP(gb),
        0x09 => stepAddHLReg16(gb, Src16.BC),
        0x0a => stepLdAInd(gb, Src8.IndBC),
        0x0b => stepIncDec16(gb, Dst16.BC, .dec),
        0x0c => stepIncDecReg8(gb, Dst8.C, .inc),
        0x0d => stepIncDecReg8(gb, Dst8.C, .dec),
        0x0e => stepLdRegImm(gb, Dst8.C),
        0x0f => stepRrca(gb),

        0x10 => stepStop(gb),
        0x11 => stepLdReg16Imm16(gb, Dst16.DE),
        0x12 => stepLdIndA(gb, Dst8.IndDE),
        0x13 => stepIncDec16(gb, Dst16.DE, .inc),
        0x14 => stepIncDecReg8(gb, Dst8.D, .inc),
        0x15 => stepIncDecReg8(gb, Dst8.D, .dec),
        0x16 => stepLdRegImm(gb, Dst8.D),
        0x17 => stepRla(gb),
        0x18 => stepJr(gb),
        0x19 => stepAddHLReg16(gb, Src16.DE),
        0x1a => stepLdAInd(gb, Src8.IndDE),
        0x1b => stepIncDec16(gb, Dst16.DE, .dec),
        0x1c => stepIncDecReg8(gb, Dst8.E, .inc),
        0x1d => stepIncDecReg8(gb, Dst8.E, .dec),
        0x1e => stepLdRegImm(gb, Dst8.E),
        0x1f => stepRra(gb),

        0x20 => stepJrCond(gb, Cond.NZ),
        0x21 => stepLdReg16Imm16(gb, Dst16.HL),
        0x22 => stepLdIndA(gb, Dst8.IndHLInc),
        0x23 => stepIncDec16(gb, Dst16.HL, .inc),
        0x24 => stepIncDecReg8(gb, Dst8.H, .inc),
        0x25 => stepIncDecReg8(gb, Dst8.H, .dec),
        0x26 => stepLdRegImm(gb, Dst8.H),
        0x27 => stepDaa(gb),
        0x28 => stepJrCond(gb, Cond.Z),
        0x29 => stepAddHLReg16(gb, Src16.HL),
        0x2a => stepLdAInd(gb, Src8.IndHLInc),
        0x2b => stepIncDec16(gb, Dst16.HL, .dec),
        0x2c => stepIncDecReg8(gb, Dst8.L, .inc),
        0x2d => stepIncDecReg8(gb, Dst8.L, .dec),
        0x2e => stepLdRegImm(gb, Dst8.L),
        0x2f => stepCpl(gb),

        0x30 => stepJrCond(gb, Cond.NC),
        0x31 => stepLdReg16Imm16(gb, Dst16.SP),
        0x32 => stepLdIndA(gb, Dst8.IndHLDec),
        0x33 => stepIncDec16(gb, Dst16.SP, .inc),
        0x34 => stepIncDecIndHL(gb, .inc),
        0x35 => stepIncDecIndHL(gb, .dec),
        0x36 => stepLdIndHLImm(gb),
        0x37 => stepScf(gb),
        0x38 => stepJrCond(gb, Cond.C),
        0x39 => stepAddHLReg16(gb, Src16.SP),
        0x3a => stepLdAInd(gb, Src8.IndHLDec),
        0x3b => stepIncDec16(gb, Dst16.SP, .dec),
        0x3c => stepIncDecReg8(gb, Dst8.A, .inc),
        0x3d => stepIncDecReg8(gb, Dst8.A, .dec),
        0x3e => stepLdRegImm(gb, Dst8.A),
        0x3f => stepCcf(gb),

        // ld r, r
        0x40...0x7f => {
            const src_encoding = @as(u3, @truncate(gb.ir & 0b0000_0111));
            const src = Src8.decode(src_encoding);
            const dst_encoding = @as(u3, @truncate((gb.ir & 0b0011_1000) >> 3));
            const dst = Dst8.decode(dst_encoding);

            if (src == Src8.IndHL and dst == Dst8.IndHL) {
                stepHalt(gb);
            } else if (src == Src8.IndHL) {
                stepLdRegInd(gb, dst, src);
            } else if (dst == Dst8.IndHL) {
                stepLdIndReg(gb, dst, src);
            } else {
                stepLdRegReg(gb, dst, src);
            }
        },

        // 8-bit arithmetic
        0x80...0xbf => {
            const src_encoding = @as(u3, @truncate(gb.ir & 0b0000_0111));
            const src = Src8.decode(src_encoding);
            const op = AluOp.decode(@as(u3, @truncate(gb.ir & 0b0000_0111)));
            stepAluOp(gb, op, src);
        },

        0xc0 => stepRetCond(gb, Cond.NZ),
        0xc2 => stepJpCond(gb, Cond.NZ),
        0xc3 => stepJp(gb),
        0xc4 => stepCallCond(gb, Cond.NZ),
        0xc7 => stepRst(gb, 0x00),
        0xc8 => stepRetCond(gb, Cond.Z),
        0xc9 => stepRet(gb),
        0xca => stepJpCond(gb, Cond.Z),
        0xcb => {},
        0xcc => stepCallCond(gb, Cond.Z),
        0xcd => stepCall(gb),
        0xcf => stepRst(gb, 0x08),

        0xd0 => stepRetCond(gb, Cond.NC),
        0xd2 => stepJpCond(gb, Cond.NC),
        0xd4 => stepCallCond(gb, Cond.NC),
        0xd7 => stepRst(gb, 0x10),
        0xd8 => stepRetCond(gb, Cond.C),
        0xda => stepJpCond(gb, Cond.C),
        0xdc => stepCallCond(gb, Cond.C),
        0xdf => stepRst(gb, 0x18),

        0xe7 => stepRst(gb, 0x20),
        0xef => stepRst(gb, 0x28),

        0xf7 => stepRst(gb, 0x30),
        0xff => stepRst(gb, 0x38),

        else => {
            const MASK_543: u8 = 0b11_000_111;
            const MASK_54: u8 = 0b11_00_1111;
            const MASK_43: u8 = 0b111_00_111;

            if (gb.ir & MASK_543 == 0b11_000_110) {
                // 8-bit arithmetic, immediate operand
                const op = AluOp.decode(@as(u3, @truncate((gb.ir & 0b0011_1000) >> 3)));
                stepAluOpImm(gb, op);
            } else if (gb.ir & MASK_54 == 0b00_00_0001) {
                // ld r16, imm16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepLdReg16Imm16(gb, dst);
            } else if (gb.ir & MASK_54 == 0b00_00_0010) {
                // ld [r16], a
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst8.decodeIndLoad(dst_encoding);
                stepLdIndReg(gb, dst, Src8.A);
            } else if (gb.ir & MASK_54 == 0b00_00_1010) {
                // ld a, [r16]
                //const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                //const dst = Dst8.decodeIndLoad(dst_encoding);
                //stepLdAInd(gb, dst);
            } else if (gb.ir & MASK_54 == 0b00_00_0011) {
                // inc r16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepIncDec16(gb, dst, .inc);
            } else if (gb.ir & MASK_54 == 0b00_00_1011) {
                // dec r16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepIncDec16(gb, dst, .dec);
            } else if (gb.ir & MASK_54 == 0b00_00_1001) {
                // add hl, r16
                const src_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const src = Src16.decode(src_encoding);
                stepAddHLReg16(gb, src);
            } else if (gb.ir & MASK_543 == 0b00_000_100) {
                // inc r8
                const dst_encoding = @as(u3, @truncate((gb.ir & 0b0011_1000) >> 3));
                const dst = Dst8.decode(dst_encoding);
                stepIncDecReg8(gb, dst, .inc);
            } else if (gb.ir & MASK_543 == 0b00_000_101) {
                // dec r8
                const dst_encoding = @as(u3, @truncate((gb.ir & 0b0011_1000) >> 3));
                const dst = Dst8.decode(dst_encoding);
                stepIncDecReg8(gb, dst, .dec);
            } else if (gb.ir & MASK_543 == 0b00_000_110) {
                // ld r8, imm8
                const dst_encoding = @as(u3, @truncate((gb.ir & 0b0011_1000) >> 3));
                const dst = Dst8.decode(dst_encoding);
                stepLdRegImm(gb, dst);
            } else if (gb.ir & MASK_43 == 0b001_00_000) {
                // jr cond, imm8
                const cond_encoding = @as(u2, @truncate((gb.ir & 0b0001_1000) >> 3));
                const cond = Cond.decode(cond_encoding);
                stepJrCond(gb, cond);
            } else if (gb.ir & MASK_43 == 0b110_00_000) {
                // ret cond
                const cond_encoding = @as(u2, @truncate((gb.ir & 0b0001_1000) >> 3));
                const cond = Cond.decode(cond_encoding);
                stepRetCond(gb, cond);
            } else if (gb.ir & MASK_43 == 0b110_00_010) {
                // jp cond, imm16
                const cond_encoding = @as(u2, @truncate((gb.ir & 0b0001_1000) >> 3));
                const cond = Cond.decode(cond_encoding);
                stepJpCond(gb, cond);
            } else if (gb.ir & MASK_43 == 0b110_00_100) {
                // call cond, imm16
                const cond_encoding = @as(u2, @truncate((gb.ir & 0b0001_1000) >> 3));
                const cond = Cond.decode(cond_encoding);
                stepCallCond(gb, cond);
            } else if (gb.ir & MASK_543 == 0b11_000_111) {
                // call rst, target
                const target_encoding = @as(u2, @truncate((gb.ir & 0b0011_1000) >> 3));
                const target: u8 = switch (target_encoding) {
                    0 => 0x00,
                    1 => 0x10,
                    2 => 0x20,
                    3 => 0x30,
                };
                stepRst(gb, target);
            }
        },
    }
}

fn fetchOpcode(gb: *Gb) void {
    gb.ir = gb.read(gb.pc);
    gb.pc +%= 1;
    gb.current_instr_cycle = 0;

    // TODO interrupt handling
}

fn stepHalt(_: *Gb) void {
    // TODO
}

fn stepLdAInd(gb: *Gb, comptime src: Src8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = src.read(gb);
        },
        else => {
            gb.a = gb.z;

            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdAIndNN(gb: *Gb) void {
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

            fetchOpcode(gb);
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
            fetchOpcode(gb);
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
            fetchOpcode(gb);
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
            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdRegReg(gb: *Gb, dst: Dst8, src: Src8) void {
    dst.write(src.read(gb), gb);
    fetchOpcode(gb);
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

                fetchOpcode(gb);
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

        fetchOpcode(gb);
    }
}

fn stepAluOpImm(gb: *Gb, op: AluOp) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.pc +%= 1;
            gb.z = gb.read(gb.pc);
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

            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdReg16Imm16(gb: *Gb, dst: Dst16) void {
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

            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

const IncDec = enum { inc, dec };

fn stepIncDec16(gb: *Gb, dst: Dst16, comptime mode: IncDec) void {
    switch (gb.current_instr_cycle) {
        0 => {
            const result = if (mode == .inc) dst.read(gb) +% 1 else dst.read(gb) -% 1;
            dst.write(result, gb);
        },
        else => {
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepAddHLReg16(gb: *Gb, src: Src16) void {
    switch (gb.current_instr_cycle) {
        0 => {
            AluOp.execute(
                .add,
                &gb.l,
                src.readLower(gb),
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );
        },
        else => {
            AluOp.execute(
                .adc,
                &gb.h,
                src.readUpper(gb),
                &gb.zero,
                &gb.negative,
                &gb.halfCarry,
                &gb.carry,
            );

            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepIncDecReg8(gb: *Gb, dst: Dst8, comptime mode: IncDec) void {
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

    fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdRegImm(gb: *Gb, dst: Dst8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        else => {
            dst.write(gb.z, gb);

            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepJpCond(gb: *Gb, cond: Cond) void {
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
                fetchOpcode(gb);
                return;
            }
        },
        else => {
            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepJrCond(gb: *Gb, cond: Cond) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.z = gb.read(gb.pc);
            gb.pc +%= 1;
        },
        1 => {
            if (cond.check(gb)) {
                calcJrDestAddr(gb.pc, gb.z, &gb.w, &gb.z);
            } else {
                fetchOpcode(gb);
                return;
            }
        },
        else => {
            gb.pc = as16(gb.w, gb.z);
            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepCallCond(gb: *Gb, cond: Cond) void {
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
                fetchOpcode(gb);
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
            fetchOpcode(gb);
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRetCond(gb: *Gb, cond: Cond) void {
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
                fetchOpcode(gb);
                return;
            }
        },
        2 => {
            gb.pc = as16(gb.w, gb.z);
        },
        else => {
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRst(gb: *Gb, target: u8) void {
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
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepRlca(_: *Gb) void {}

fn stepRla(_: *Gb) void {}

fn stepDaa(_: *Gb) void {}

fn stepScf(_: *Gb) void {}

fn stepRrca(_: *Gb) void {}

fn stepRra(_: *Gb) void {}

fn stepCpl(_: *Gb) void {}

fn stepCcf(_: *Gb) void {}

fn stepStop(_: *Gb) void {}
