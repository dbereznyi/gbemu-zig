const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Condition = @import("operand.zig").Condition;
const Src8 = @import("operand.zig").Src8;
const Dst8 = @import("operand.zig").Dst8;
const Src16 = @import("operand.zig").Src16;
const Dst16 = @import("operand.zig").Dst16;

const InstrTag = enum {
    INVALID,

    NOP,
    HALT,
    STOP,
    EI,
    DI,
    DAA,
    CPL,
    SCF,
    CCF,

    LD_8,
    LD_16,

    INC_8,
    INC_16,
    DEC_8,
    DEC_16,
    ADD,
    ADC,
    SUB,
    SBC,
    AND,
    XOR,
    OR,
    CP,
    ADD_16,
    ADD_SP,

    JP,
    JP_COND,
    JP_HL,
    JR,
    JR_COND,
    CALL,
    CALL_COND,
    RET,
    RET_COND,
    RETI,
    RST,

    POP,
    PUSH,

    RLCA,
    RRCA,
    RLA,
    RRA,

    RLC,
    RRC,
    RL,
    RR,
    SLA,
    SRA,
    SWAP,
    SRL,
    BIT,
    RES,
    SET,
};

const DstSrc8 = struct {
    dst: Dst8,
    src: Src8,
};

const DstSrc16 = struct {
    dst: Dst16,
    src: Src16,
};

const CondAddr = struct {
    cond: Condition,
    addr: u16,
};

const CondOffset = struct {
    cond: Condition,
    offset: u8,
};

const Dst8Bit = struct {
    dst: Dst8,
    bit: u3,
};

pub const Instr = union(InstrTag) {
    INVALID: u8,

    NOP: void,
    HALT: void,
    STOP: void,
    EI: void,
    DI: void,
    DAA: void,
    CPL: void,
    SCF: void,
    CCF: void,

    LD_8: DstSrc8,
    LD_16: DstSrc16,

    INC_8: Dst8,
    INC_16: Dst16,
    DEC_8: Dst8,
    DEC_16: Dst16,
    ADD: Src8,
    ADC: Src8,
    SUB: Src8,
    SBC: Src8,
    AND: Src8,
    XOR: Src8,
    OR: Src8,
    CP: Src8,
    ADD_16: DstSrc16,
    ADD_SP: u8,

    JP: u16,
    JP_COND: CondAddr,
    JP_HL: void,
    JR: u8,
    JR_COND: CondOffset,
    CALL: u16,
    CALL_COND: CondAddr,
    RET: void,
    RET_COND: Condition,
    RETI: void,
    RST: u8,

    POP: Dst16,
    PUSH: Src16,

    RLCA: void,
    RRCA: void,
    RLA: void,
    RRA: void,

    RLC: Dst8,
    RRC: Dst8,
    RL: Dst8,
    RR: Dst8,
    SLA: Dst8,
    SRA: Dst8,
    SWAP: Dst8,
    SRL: Dst8,
    BIT: Dst8Bit,
    RES: Dst8Bit,
    SET: Dst8Bit,

    pub fn toStr(instr: Instr, buf: []u8) ![]u8 {
        const mnemonic = switch (instr) {
            .INVALID => "??",
            .NOP => "nop",
            .HALT => "halt",
            .STOP => "stop",
            .EI => "ei",
            .DI => "di",
            .DAA => "daa",
            .CPL => "cpl",
            .SCF => "scf",
            .CCF => "ccf",

            .LD_8 => |args| if (args.dst == .IndIoReg or args.src == .IndIoReg) "ldh" else "ld",
            .LD_16 => "ld",

            .INC_8 => "inc",
            .INC_16 => "inc",
            .DEC_8 => "dec",
            .DEC_16 => "dec",
            .ADD => "add",
            .ADC => "adc",
            .SUB => "sub",
            .SBC => "sbc",
            .AND => "and",
            .XOR => "xor",
            .OR => "or",
            .CP => "cp",
            .ADD_16 => "add",
            .ADD_SP => "add",

            .JP => "jp",
            .JP_COND => "jp",
            .JP_HL => "jp",
            .JR => "jr",
            .JR_COND => "jr",
            .CALL => "call",
            .CALL_COND => "call",
            .RET => "ret",
            .RET_COND => "ret",
            .RETI => "reti",
            .RST => "rst",

            .POP => "pop",
            .PUSH => "push",

            .RLCA => "rlca",
            .RRCA => "rrca",
            .RLA => "rla",
            .RRA => "rra",

            .RLC => "rlc",
            .RRC => "rrc",
            .RL => "rl",
            .RR => "rr",
            .SLA => "sla",
            .SRA => "sra",
            .SWAP => "swap",
            .SRL => "srl",
            .BIT => "bit",
            .RES => "res",
            .SET => "set",
        };

        var condBuf: [2]u8 = undefined;
        const condStr: ?[]u8 = switch (instr) {
            .JP_COND => |args| try args.cond.toStr(&condBuf),
            .JR_COND => |args| try args.cond.toStr(&condBuf),
            .CALL_COND => |args| try args.cond.toStr(&condBuf),
            .RET_COND => |cond| try cond.toStr(&condBuf),
            else => null,
        };

        var dstBuf: [16]u8 = undefined;
        const dstStr: ?[]u8 = switch (instr) {
            .LD_8 => |args| try args.dst.toStr(&dstBuf),
            .LD_16 => |args| try args.dst.toStr(&dstBuf),

            .INC_8 => |dst| try dst.toStr(&dstBuf),
            .INC_16 => |dst| try dst.toStr(&dstBuf),
            .DEC_8 => |dst| try dst.toStr(&dstBuf),
            .DEC_16 => |dst| try dst.toStr(&dstBuf),
            .ADD_16 => |args| try args.dst.toStr(&dstBuf),
            .ADD_SP => |n8| try std.fmt.bufPrint(&dstBuf, "${x:0>2}", .{n8}),

            .JP => |n16| try std.fmt.bufPrint(&dstBuf, "${x:0>4}", .{n16}),
            .JR => |n8| try std.fmt.bufPrint(&dstBuf, "${x:0>2}", .{n8}),
            .CALL => |n16| try std.fmt.bufPrint(&dstBuf, "${x:0>4}", .{n16}),
            .CALL_COND => |args| try std.fmt.bufPrint(&dstBuf, "${x:0>4}", .{args.addr}),
            .RST => |n8| try std.fmt.bufPrint(&dstBuf, "${x:0>2}", .{n8}),

            .POP => |dst| try dst.toStr(&dstBuf),

            .RLC => |dst| try dst.toStr(&dstBuf),
            .RRC => |dst| try dst.toStr(&dstBuf),
            .RL => |dst| try dst.toStr(&dstBuf),
            .RR => |dst| try dst.toStr(&dstBuf),
            .SLA => |dst| try dst.toStr(&dstBuf),
            .SRA => |dst| try dst.toStr(&dstBuf),
            .SWAP => |dst| try dst.toStr(&dstBuf),
            .SRL => |dst| try dst.toStr(&dstBuf),
            .BIT => |args| try args.dst.toStr(&dstBuf),
            .RES => |args| try args.dst.toStr(&dstBuf),
            .SET => |args| try args.dst.toStr(&dstBuf),

            else => null,
        };

        var srcBuf: [16]u8 = undefined;
        const srcStr: ?[]u8 = switch (instr) {
            .LD_8 => |args| try args.src.toStr(&srcBuf),
            .LD_16 => |args| try args.src.toStr(&srcBuf),

            .ADD => |src| try src.toStr(&srcBuf),
            .ADC => |src| try src.toStr(&srcBuf),
            .SUB => |src| try src.toStr(&srcBuf),
            .SBC => |src| try src.toStr(&srcBuf),
            .AND => |src| try src.toStr(&srcBuf),
            .XOR => |src| try src.toStr(&srcBuf),
            .OR => |src| try src.toStr(&srcBuf),
            .CP => |src| try src.toStr(&srcBuf),
            .ADD_16 => |args| try args.src.toStr(&srcBuf),

            .PUSH => |src| try src.toStr(&srcBuf),

            else => null,
        };

        const param1: ?[]u8 = condStr orelse (dstStr orelse null);
        const param2: ?[]u8 = srcStr orelse null;

        return try std.fmt.bufPrint(buf, "{s} {s}{s}{s}", .{
            mnemonic,
            param1 orelse "",
            if (param1 != null and param2 != null) ", " else "",
            param2 orelse "",
        });
    }
};
