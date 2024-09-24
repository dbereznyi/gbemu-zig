const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Ppu = @import("../gameboy.zig").Ppu;
const IoReg = @import("../gameboy.zig").IoReg;
const Interrupt = @import("../gameboy.zig").Interrupt;

const ENABLE_DEBUGGING = true;
const ENABLE_SOFTWARE_BREAKPOINTS = false;

pub fn shouldDebugBreak(gb: *Gb) bool {
    if (!ENABLE_DEBUGGING) {
        return false;
    }
    if (!gb.isRunning()) {
        return false;
    }

    // Note: with stepAccurate(), skipCurrentInstruction should be ignored.
    if (false and gb.debug.skipCurrentInstruction) {
        gb.debug.skipCurrentInstruction = false;
        return false;
    }
    if (gb.debug.stepModeEnabled) {
        return true;
    }

    if (ENABLE_SOFTWARE_BREAKPOINTS and gb.ir == 0x40) { // software breakpoint ("ld b, b")
        return true;
    }

    var breakpointHit = false;
    for (gb.debug.breakpoints.items) |breakpoint| {
        const addr = breakpoint.addr;
        const bank = breakpoint.bank;
        if (gb.pc == addr and gb.cart.getBank(gb.pc) == bank) {
            breakpointHit = true;
            break;
        }
    }
    if (breakpointHit) {
        return true;
    }
    return false;
}
