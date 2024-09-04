const std = @import("std");
const as16 = @import("../util.zig").as16;
const incAs16 = @import("../util.zig").incAs16;
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const executeCurrentInstruction = @import("execute.zig").executeCurrentInstruction;
const Src8 = @import("operand.zig").Src8;
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

const AluOp8 = enum {
    add,
    adc,
    sub,
    sbc,
    and_,
    xor,
    or_,
    cp,

    pub fn execute(self: AluOp8, gb: *Gb, src: Src8) void {
        switch (self) {
            .add => {
                const x = gb.a;
                const y = src.read(gb);
                const result = x +% y;

                gb.zero = result == 0;
                gb.negative = false;
                gb.halfCarry = checkHalfCarry8(x, y);
                gb.carry = checkCarry8(x, y);

                gb.a = result;
            },
            .adc => {
                const x = gb.a;
                const y = src.read(gb) +% if (gb.carry) @as(u8, 1) else @as(u8, 0);
                const result = x +% y;

                gb.zero = result == 0;
                gb.negative = false;
                gb.halfCarry = checkHalfCarry8(x, y);
                gb.carry = checkCarry8(x, y);

                gb.a = result;
            },
            .sub => {
                const x = gb.a;
                const y = ~src.read(gb) +% 1;
                const result = x +% y;

                gb.zero = result == 0;
                gb.negative = true;
                gb.halfCarry = checkHalfCarry8(x, y);
                gb.carry = checkCarry8(x, y);

                gb.a = result;
            },
            .sbc => {
                const x = gb.a;
                const y = ~(src.read(gb) +% if (gb.carry) @as(u8, 1) else @as(u8, 0)) +% 1;
                const result = x +% y;

                gb.zero = result == 0;
                gb.negative = true;
                gb.halfCarry = checkHalfCarry8(x, y);
                gb.carry = checkCarry8(x, y);

                gb.a = result;
            },
            .and_ => {
                const x = gb.a;
                const y = src.read(gb);
                const result = x & y;

                gb.zero = result == 0;
                gb.negative = false;
                gb.halfCarry = true;
                gb.carry = false;

                gb.a = result;
            },
            .xor => {
                const x = gb.a;
                const y = src.read(gb);
                const result = x ^ y;

                gb.zero = result == 0;
                gb.negative = false;
                gb.halfCarry = false;
                gb.carry = false;

                gb.a = result;
            },
            .or_ => {
                const x = gb.a;
                const y = src.read(gb);
                const result = x | y;

                gb.zero = result == 0;
                gb.negative = false;
                gb.halfCarry = false;
                gb.carry = false;

                gb.a = result;
            },
            .cp => {
                const x = gb.a;
                const y = ~src.read(gb) +% 1;
                const result = x +% y;

                gb.zero = result == 0;
                gb.negative = true;
                gb.halfCarry = checkHalfCarry8(x, y);
                gb.carry = checkCarry8(x, y);
            },
        }
    }

    fn checkCarry8(x: u8, y: u8) bool {
        return @addWithOverflow(x, y)[1] == 1;
    }

    fn checkHalfCarry8(x: u8, y: u8) bool {
        return (((x & 0x0f) + (y & 0x0f)) & 0x10) == 0x10;
    }

    pub fn decode(val: u3) AluOp8 {
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

fn stepCurrentInstr(gb: *Gb) void {
    switch (gb.ir) {
        // nop
        0x00 => fetchOpcode(gb),
        // ld [imm16], sp
        0x08 => stepLdImm16SP(gb),

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
            const op = AluOp8.decode(@as(u3, @truncate(gb.ir & 0b0000_0111)));
            stepAluOp8(gb, op, src);
        },

        else => {
            if (gb.ir & 0b11_000_111 == 0b11_000_110) {
                // 8-bit arithmetic, immediate operand
                const op = AluOp8.decode(@as(u3, @truncate((gb.ir & 0b0011_1000) >> 3)));
                stepAluOp8Imm(gb, op);
            } else if (gb.ir & 0b11_00_1111 == 0b00_00_0001) {
                // ld r16, imm16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepLdReg16Imm16(gb, dst);
            } else if (gb.ir & 0b11_00_1111 == 0b00_00_0010) {
                // ld [r16], a
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst8.decodeIndLoad(dst_encoding);
                stepLdIndReg(gb, dst, Src8.A);
            } else if (gb.ir & 0b11_00_1111 == 0b00_00_1010) {
                // ld a, [r16]
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst8.decodeIndLoad(dst_encoding);
                stepLdRegInd(gb, dst, Src8.A);
            } else if (gb.ir & 0b11_00_1111 == 0b00_00_0011) {
                // inc r16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepIncDec16(gb, dst, .inc);
            } else if (gb.ir & 0b11_00_1111 == 0b00_00_1011) {
                // dec r16
                const dst_encoding = @as(u2, @truncate((gb.ir & 0b0011_0000) >> 4));
                const dst = Dst16.decode(dst_encoding);
                stepIncDec16(gb, dst, .dec);
            }
        },
    }
}

fn fetchOpcode(gb: *Gb) void {
    gb.pc +%= 1;
    gb.ir = gb.read(gb.pc);
    gb.current_instr_cycle = 0;

    // TODO interrupt handling
}

fn stepHalt(_: *Gb) void {
    // TODO
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

fn stepLdRegReg(gb: *Gb, dst: Dst8, src: Src8) void {
    dst.write(src.read(gb), gb);
    fetchOpcode(gb);
}

fn stepAluOp8(gb: *Gb, op: AluOp8, src: Src8) void {
    if (src == .IndHL) {
        switch (gb.current_instr_cycle) {
            0 => {
                gb.z = src.read(gb);
            },
            else => {
                op.execute(gb, Src8{ .Imm = gb.z });
                fetchOpcode(gb);
                return;
            },
        }
        gb.current_instr_cycle += 1;
    } else {
        op.execute(gb, src);
        fetchOpcode(gb);
    }
}

fn stepAluOp8Imm(gb: *Gb, op: AluOp8) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.pc += 1;
            gb.z = gb.read(gb.pc);
        },
        else => {
            op.execute(gb, Src8{ .Imm = gb.z });
            fetchOpcode(gb);
            return;
        },
    }
    gb.current_instr_cycle += 1;
}

fn stepLdReg16Imm16(gb: *Gb, dst: Dst16) void {
    switch (gb.current_instr_cycle) {
        0 => {
            gb.pc += 1;
            gb.z = gb.read(gb.pc);
        },
        1 => {
            gb.pc += 1;
            gb.w = gb.read(gb.pc);
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
            gb.pc += 1;
            gb.z = gb.read(gb.pc);
        },
        1 => {
            gb.pc += 1;
            gb.w = gb.read(gb.pc);
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
