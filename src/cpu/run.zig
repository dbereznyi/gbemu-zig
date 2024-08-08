const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const stepInstr = @import("step.zig").stepInstr;

pub fn stepCpu(gb: *Gb) u64 {
    const interruptPending = gb.ime and gb.anyInterruptsPending();

    switch (gb.execState) {
        .running => {
            if (interruptPending) {
                handleInterrupt(gb);
            }
            return stepInstr(gb);
        },
        .halted => {
            if (interruptPending) {
                handleInterrupt(gb);
                gb.execState = .running;
            }
            return 1;
        },
        .haltedDiscardInterrupt => {
            if (interruptPending) {
                discardInterrupt(gb);
                gb.execState = .running;
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
    gb.push16(gb.pc);

    if (gb.isInterruptPending(Interrupt.VBLANK)) {
        gb.pc = 0x0040;
        gb.clearInterrupt(Interrupt.VBLANK);
    } else if (gb.isInterruptPending(Interrupt.STAT)) {
        gb.pc = 0x0048;
        gb.clearInterrupt(Interrupt.STAT);
    } else if (gb.isInterruptPending(Interrupt.TIMER)) {
        gb.pc = 0x0050;
        gb.clearInterrupt(Interrupt.TIMER);
    } else if (gb.isInterruptPending(Interrupt.SERIAL)) {
        gb.pc = 0x0058;
        gb.clearInterrupt(Interrupt.SERIAL);
    } else if (gb.isInterruptPending(Interrupt.JOYPAD)) {
        gb.pc = 0x0060;
        gb.clearInterrupt(Interrupt.JOYPAD);
    }

    gb.ime = false;
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
