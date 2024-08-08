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

    if (buttons > 0 or dpad > 0) {
        if (gb.joypad.cyclesSinceLastButtonPress > 16) {
            gb.joypad.cyclesSinceLastButtonPress = 0;
            if (gb.isInterruptEnabled(Interrupt.JOYPAD)) {
                gb.requestInterrupt(Interrupt.JOYPAD);
            }
        } else {
            gb.joypad.cyclesSinceLastButtonPress += 1;
        }
    } else {
        gb.joypad.cyclesSinceLastButtonPress = 0;
    }
}
