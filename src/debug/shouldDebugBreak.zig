const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Ppu = @import("../gameboy.zig").Ppu;
const IoReg = @import("../gameboy.zig").IoReg;
const Interrupt = @import("../gameboy.zig").Interrupt;

const DEBUGGING_ENABLED = true;

pub fn shouldDebugBreak(gb: *Gb) bool {
    var breakpointHit = false;
    for (gb.debug.breakpoints.items) |addr| {
        if (gb.pc == addr) {
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
    if (breakpointHit or gb.debug.stepModeEnabled) {
        if (gb.debug.skipCurrentBreakpoint) {
            gb.debug.skipCurrentBreakpoint = false;
            return false;
        }
        return true;
    } else {
        return false;
    }
}
