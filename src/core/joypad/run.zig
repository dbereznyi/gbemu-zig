const std = @import("std");
const Gb = @import("../root.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;
const Interrupt = @import("../gameboy.zig").Interrupt;
const JoypFlag = @import("./joypad.zig").Joypad.JoypFlag;

pub fn runJoypad(gb: *Gb, cycles: usize) void {
    var rem_cycles = cycles + gb.joypad.cycles_odd;

    while (rem_cycles >= 4) {
        rem_cycles -= 4;

        stepJoypad(gb);
    }

    gb.joypad.cycles_odd = rem_cycles;
}

fn stepJoypad(gb: *Gb) void {
    const joyp = gb.io_regs[IoReg.JOYP];
    const buttons = gb.joypad.readButtons();
    const dpad = gb.joypad.readDpad();
    var result: u4 = undefined;
    if (joyp & JoypFlag.SELECT_BUTTONS == 0) {
        result = ~buttons;
    } else if (joyp & JoypFlag.SELECT_DPAD == 0) {
        result = ~dpad;
    } else if (joyp & JoypFlag.SELECT_BUTTONS == 0 and joyp & JoypFlag.SELECT_DPAD == 0) {
        result = ~buttons | ~dpad;
    } else {
        result = 0xf;
    }
    gb.io_regs[IoReg.JOYP] = ((joyp & 0b1111_0000) | result) | 0xc0;

    switch (gb.joypad.mode) {
        .waiting_for_low_edge => {
            std.debug.assert(gb.joypad.cycles_since_low_edge_transition == 0);

            const joyp_after = gb.io_regs[IoReg.JOYP];
            const bit0 = joyp & 0b0000_0001 > 0 and joyp_after & 0b0000_0001 == 0;
            const bit1 = joyp & 0b0000_0010 > 0 and joyp_after & 0b0000_0010 == 0;
            const bit2 = joyp & 0b0000_0100 > 0 and joyp_after & 0b0000_0100 == 0;
            const bit3 = joyp & 0b0000_1000 > 0 and joyp_after & 0b0000_1000 == 0;

            const low_edge = bit0 or bit1 or bit2 or bit3;

            if (low_edge) {
                gb.joypad.cycles_since_low_edge_transition += 1;
                gb.joypad.mode = .low_edge;
            }
        },
        .low_edge => {
            std.debug.assert(gb.joypad.cycles_since_low_edge_transition > 0);
            std.debug.assert(gb.joypad.cycles_since_low_edge_transition <= 16);

            const bit0 = joyp & 0b0000_0001 == 0;
            const bit1 = joyp & 0b0000_0010 == 0;
            const bit2 = joyp & 0b0000_0100 == 0;
            const bit3 = joyp & 0b0000_1000 == 0;
            const low_edge = bit0 or bit1 or bit2 or bit3;
            if (low_edge) {
                if (gb.joypad.cycles_since_low_edge_transition < 16) {
                    gb.joypad.cycles_since_low_edge_transition += 1;
                } else {
                    gb.joypad.cycles_since_low_edge_transition = 0;
                    if (gb.ime and gb.ie & Interrupt.JOYPAD > 0) {
                        gb.io_regs[IoReg.IF] |= Interrupt.JOYPAD;
                    }
                    gb.joypad.mode = .waiting_for_low_edge;
                }
            } else {
                gb.joypad.cycles_since_low_edge_transition = 0;
                gb.joypad.mode = .waiting_for_low_edge;
            }
        },
    }
}
