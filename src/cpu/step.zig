const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const executeCurrentInstruction = @import("execute.zig").executeCurrentInstruction;

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
