const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;
const ExecState = @import("../gameboy.zig").ExecState;
const as16 = @import("../util.zig").as16;
const Src8 = @import("operand.zig").Src8;
const Dst8 = @import("operand.zig").Dst8;
const Src16 = @import("operand.zig").Src16;
const Dst16 = @import("operand.zig").Dst16;
const decodeInstrAt = @import("decode.zig").decodeInstrAt;

pub fn executeCurrentInstruction(gb: *Gb) usize {
    gb.branchCond = false;

    const instr = decodeInstrAt(gb.pc, gb);
    switch (instr) {
        .INVALID => |opcode| std.debug.panic("invalid opcode ${x}\n", .{opcode}),

        .NOP => {},
        .HALT => halt(gb),
        .STOP => stop(gb),
        .EI => ei(gb),
        .DI => di(gb),
        .DAA => daa(gb),
        .CPL => cpl(gb),
        .SCF => scf(gb),
        .CCF => ccf(gb),

        .LD_8 => |args| ld8(gb, args.dst, args.src),
        .LD_16 => |args| ld16(gb, args.dst, args.src),

        .INC_8 => |dst| inc8(gb, dst),
        .INC_16 => |dst| inc16(gb, dst),
        .DEC_8 => |dst| dec8(gb, dst),
        .DEC_16 => |dst| dec16(gb, dst),
        .ADD => |src| add(gb, src),
        .ADC => |src| adc(gb, src),
        .SUB => |src| sub(gb, src),
        .SBC => |src| sbc(gb, src),
        .AND => |src| and_(gb, src),
        .XOR => |src| xor(gb, src),
        .OR => |src| or_(gb, src),
        .CP => |src| cp(gb, src),
        .ADD_16 => |args| add16(gb, args.dst, args.src),
        .ADD_SP => |offset| addSp(gb, offset),

        .JP => |addr| jp(gb, addr),
        .JP_COND => |args| jpCond(gb, args.addr, args.cond.check(gb)),
        .JP_HL => jpHl(gb),
        .JR => |offset| jr(gb, offset),
        .JR_COND => |args| jrCond(gb, args.offset, args.cond.check(gb)),
        .CALL => |addr| call(gb, addr),
        .CALL_COND => |args| callCond(gb, args.addr, args.cond.check(gb)),
        .RET => ret(gb),
        .RET_COND => |cond| retCond(gb, cond.check(gb)),
        .RETI => reti(gb),
        .RST => |vec| rst(gb, vec),

        .POP => |dst| pop(gb, dst),
        .PUSH => |src| push(gb, src),

        .RLCA => rlca(gb),
        .RRCA => rrca(gb),
        .RLA => rla(gb),
        .RRA => rra(gb),

        .RLC => |dst| rlc(gb, dst),
        .RRC => |dst| rrc(gb, dst),
        .RL => |dst| rl(gb, dst),
        .RR => |dst| rr(gb, dst),
        .SLA => |dst| sla(gb, dst),
        .SRA => |dst| sra(gb, dst),
        .SWAP => |dst| swap(gb, dst),
        .SRL => |dst| srl(gb, dst),
        .BIT => |args| bit(gb, args.dst, args.bit),
        .RES => |args| res(gb, args.dst, args.bit),
        .SET => |args| set(gb, args.dst, args.bit),
    }

    if (!gb.skipPcIncrement) {
        gb.*.pc +%= instr.size();
    } else {
        gb.skipPcIncrement = false;
    }

    return instr.cycles(gb.branchCond);
}

fn incHL(gb: *Gb) void {
    const hl = as16(gb.h, gb.l);
    const hlInc = hl +% 1;
    gb.h = @truncate(hlInc >> 8);
    gb.l = @truncate(hlInc);
}

fn decHL(gb: *Gb) void {
    const hl = as16(gb.h, gb.l);
    const hlDec = hl -% 1;
    gb.h = @truncate(hlDec >> 8);
    gb.l = @truncate(hlDec);
}

fn ld16(gb: *Gb, dst: Dst16, src: Src16) void {
    const val = src.read(gb);
    dst.write(val, gb);
}

fn ld8(gb: *Gb, dst: Dst8, src: Src8) void {
    const val = src.read(gb);
    dst.write(val, gb);
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
    const x = src.read(gb);
    const y = gb.a;
    const sum = x +% y;
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
    const x = src.read(gb);
    const y = dst.read(gb);
    const sum = x +% y;
    dst.write(sum, gb);

    gb.negative = false;
    gb.halfCarry = checkHalfCarry16(x, y);
    gb.carry = checkCarry16(x, y);
}

fn adc(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const y = gb.a;
    const carry: u8 = if (gb.carry) 1 else 0;
    const sum = x +% y +% carry;
    gb.a = sum;

    gb.zero = sum == 0;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(x, y + carry);
    gb.carry = checkCarry(x, y + carry);
}

fn sub(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const diff = gb.a -% x;
    gb.a = diff;

    gb.zero = diff == 0;
    gb.negative = true;
    gb.halfCarry = !checkHalfCarry(gb.a, ~x + 1);
    gb.carry = !checkCarry(gb.a, ~x + 1);
}

fn sbc(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const carry: u8 = if (gb.carry) 1 else 0;
    const diff = gb.a -% x -% carry;
    gb.a = diff;

    gb.zero = diff == 0;
    gb.negative = true;
    gb.halfCarry = !checkHalfCarry(gb.a, ~(x + carry) + 1);
    gb.carry = !checkCarry(gb.a, ~(x + carry) + 1);
}

fn and_(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const result = gb.a & x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = true;
    gb.carry = false;
}

fn xor(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const result = gb.a ^ x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn or_(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const result = gb.a | x;
    gb.a = result;

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn cp(gb: *Gb, src: Src8) void {
    const x = src.read(gb);
    const result = gb.a -% x;

    gb.zero = result == 0;
    gb.negative = true;
    gb.halfCarry = !checkHalfCarry(gb.a, ~x + 1);
    gb.carry = !checkCarry(gb.a, ~x + 1);
}

fn inc8(gb: *Gb, dst: Dst8) void {
    const initialValue = dst.read(gb);
    const result = initialValue +% 1;
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = checkHalfCarry(initialValue, 1);
}

fn dec8(gb: *Gb, dst: Dst8) void {
    const initialValue = dst.read(gb);
    const result = initialValue -% 1;
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = true;
    gb.halfCarry = checkHalfCarry(initialValue, 0xff);
}

fn inc16(gb: *Gb, dst: Dst16) void {
    const initialValue = dst.read(gb);
    const result = initialValue +% 1;
    dst.write(result, gb);
}

fn dec16(gb: *Gb, dst: Dst16) void {
    const initialValue = dst.read(gb);
    const result = initialValue -% 1;
    dst.write(result, gb);
}

fn calcJrDestAddr(pc: u16, offset: u8) u16 {
    const offsetI8: i8 = @bitCast(offset);
    const pcI16: i16 = @intCast(pc);
    return @intCast(pcI16 +% offsetI8);
}

test "calcJrDestAddr" {
    const offset: u8 = 156; // -100 as i8
    const pc: u16 = 1500;
    const expected: u16 = 1400; // 1500 - 100 = 1400

    const result = calcJrDestAddr(pc, offset);
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
    return address -% 3;
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
    const destAddr = Src16.read(.HL, gb);
    gb.pc = calcJpDestAddr(destAddr);
}

fn calcRetDestAddr(address: u16) u16 {
    // subtract 1 byte to account for PC getting incremented by the size of RET (1 byte)
    return address -% 1;
}

fn ret(gb: *Gb) void {
    gb.pc = calcRetDestAddr(gb.pop16());
}

fn retCond(gb: *Gb, cond: bool) void {
    if (cond) {
        gb.pc = calcRetDestAddr(gb.pop16());
        gb.branchCond = true;
    }
}

fn reti(gb: *Gb) void {
    gb.pc = calcRetDestAddr(gb.pop16());
    gb.ime = true;
}

fn calcCallDestAddr(address: u16) u16 {
    // subtract 3 bytes to account for PC getting incremented by the size of CALL (3 bytes)
    return address -% 3;
}

fn call(gb: *Gb, address: u16) void {
    gb.push16(gb.pc +% 3);
    gb.pc = calcCallDestAddr(address);
}

fn callCond(gb: *Gb, address: u16, cond: bool) void {
    if (cond) {
        gb.push16(gb.pc +% 3);
        gb.pc = calcCallDestAddr(address);
        gb.branchCond = true;
    }
}

fn rst(gb: *Gb, address: u8) void {
    gb.push16(gb.pc +% 1);
    // subtract 1 byte to account for PC getting incremented by the size of RST (1 byte)
    gb.pc = address -% 1;
}

fn pop(gb: *Gb, dst: Dst16) void {
    const value = gb.pop16();
    dst.write(value, gb);
}

fn push(gb: *Gb, src: Src16) void {
    const value = src.read(gb);
    gb.push16(value);
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
        const interruptPending = (gb.read(IoReg.IE) & gb.read(IoReg.IF)) > 0;
        if (!interruptPending) {
            gb.execState = ExecState.haltedDiscardInterrupt;
        } else {
            gb.execState = ExecState.running;
            gb.skipPcIncrement = true;
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
    gb.sp = @intCast(spI16 +% valueI8);

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
    const value = dst.read(gb);

    const bit7 = value & 0b1000_0000;
    const result = (value << 1) | (bit7 >> 7);
    dst.write(result, gb);

    gb.zero = dst.read(gb) == 0;
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
    const value = dst.read(gb);

    const bit0 = value & 0b0000_0001;
    const result = (value >> 1) | (bit0 << 7);
    dst.write(result, gb);

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
    const value = dst.read(gb);

    const newBit0: u8 = if (gb.carry) 1 else 0;
    const bit7 = value & 0b1000_0000;
    const result = (gb.a << 1) | newBit0;
    dst.write(result, gb);

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
    const value = dst.read(gb);

    const newBit7: u8 = if (gb.carry) 1 else 0;
    const bit0 = value & 0b0000_0001;
    const result = (gb.a >> 1) | (newBit7 << 7);
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn sla(gb: *Gb, dst: Dst8) void {
    const value = dst.read(gb);

    const bit7 = value & 0b1000_0000;
    const result = value << 1;
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit7 > 0;
}

fn sra(gb: *Gb, dst: Dst8) void {
    const value = dst.read(gb);

    const bit7 = value & 0b1000_0000;
    const bit0 = value & 0b0000_0001;
    const result = bit7 | (value >> 1);
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn swap(gb: *Gb, dst: Dst8) void {
    const value = dst.read(gb);

    const low = value & 0b0000_1111;
    const high = value & 0b1111_0000;
    const result = (low << 4) | (high >> 4);
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = false;
}

fn srl(gb: *Gb, dst: Dst8) void {
    const value = dst.read(gb);

    const bit0 = value & 0b0000_0001;
    const result = value >> 1;
    dst.write(result, gb);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = false;
    gb.carry = bit0 > 0;
}

fn bit(gb: *Gb, dst: Dst8, n: u3) void {
    const value = dst.read(gb);

    const result = value & (@as(u8, 1) << n);

    gb.zero = result == 0;
    gb.negative = false;
    gb.halfCarry = true;
}

fn res(gb: *Gb, dst: Dst8, n: u3) void {
    const value = dst.read(gb);

    const mask = ~(@as(u8, 1) << n);
    const result = value & mask;
    dst.write(result, gb);
}

fn set(gb: *Gb, dst: Dst8, n: u3) void {
    const value = dst.read(gb);

    const mask = (@as(u8, 1) << n);
    const result = value | mask;
    dst.write(result, gb);
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
