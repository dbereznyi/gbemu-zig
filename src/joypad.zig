const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const Interrupt = @import("gameboy.zig").Interrupt;
const JoypFlag = @import("gameboy.zig").JoypFlag;

pub fn stepJoypad(gb: *Gb) void {
    const joyp = gb.read(IoReg.JOYP);
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
    gb.write(IoReg.JOYP, (joyp & 0b1111_0000) | result);

    switch (gb.joypad.mode) {
        .waitingForLowEdge => {
            std.debug.assert(gb.joypad.cyclesSinceLowEdgeTransition == 0);

            const joypAfter = gb.read(IoReg.JOYP);
            const bit0 = joyp & 0b0000_0001 > 0 and joypAfter & 0b0000_0001 == 0;
            const bit1 = joyp & 0b0000_0010 > 0 and joypAfter & 0b0000_0010 == 0;
            const bit2 = joyp & 0b0000_0100 > 0 and joypAfter & 0b0000_0100 == 0;
            const bit3 = joyp & 0b0000_1000 > 0 and joypAfter & 0b0000_1000 == 0;

            const lowEdgeTransitionOccurred = bit0 or bit1 or bit2 or bit3;

            if (lowEdgeTransitionOccurred) {
                gb.joypad.cyclesSinceLowEdgeTransition += 1;
                gb.joypad.mode = .lowEdge;
            }
        },
        .lowEdge => {
            std.debug.assert(gb.joypad.cyclesSinceLowEdgeTransition > 0);
            std.debug.assert(gb.joypad.cyclesSinceLowEdgeTransition <= 16);

            const bit0 = joyp & 0b0000_0001 == 0;
            const bit1 = joyp & 0b0000_0010 == 0;
            const bit2 = joyp & 0b0000_0100 == 0;
            const bit3 = joyp & 0b0000_1000 == 0;
            const lowEdge = bit0 or bit1 or bit2 or bit3;
            if (lowEdge) {
                if (gb.joypad.cyclesSinceLowEdgeTransition < 16) {
                    gb.joypad.cyclesSinceLowEdgeTransition += 1;
                } else {
                    gb.joypad.cyclesSinceLowEdgeTransition = 0;
                    if (gb.ime and gb.isInterruptEnabled(Interrupt.JOYPAD)) {
                        gb.requestInterrupt(Interrupt.JOYPAD);
                    }
                    gb.joypad.mode = .waitingForLowEdge;
                }
            } else {
                gb.joypad.cyclesSinceLowEdgeTransition = 0;
                gb.joypad.mode = .waitingForLowEdge;
            }
        },
    }
}
