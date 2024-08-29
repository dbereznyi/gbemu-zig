const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Ppu = @import("../gameboy.zig").Ppu;
const IoReg = @import("../gameboy.zig").IoReg;
const Interrupt = @import("../gameboy.zig").Interrupt;

const DEBUGGING_ENABLED = true;

pub fn shouldDebugBreak(gb: *Gb) bool {
    var breakpointHit = false;
    for (gb.debug.breakpoints.items) |breakpoint| {
        const addr = breakpoint.addr;
        const bank = breakpoint.bank;
        if (gb.pc == addr and gb.cart.getBank(gb.pc) == bank) {
            breakpointHit = true;
            break;
        }
    }

    if (!DEBUGGING_ENABLED) {
        return false;
    }
    if (!gb.isRunning()) {
        return false;
    }
    if (gb.debug.skipCurrentInstruction) {
        gb.debug.skipCurrentInstruction = false;
        return false;
    }
    if (gb.debug.stepModeEnabled) {
        return true;
    }
    if (breakpointHit) {
        return true;
    }
    return false;
}
