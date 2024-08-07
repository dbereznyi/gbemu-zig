const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const stepInstr = @import("step.zig").stepInstr;

pub fn stepCpu(gb: *Gb) u64 {
    const if_ = gb.read(IoReg.IF);
    const interruptPending = gb.ime and if_ > 0;

    switch (gb.execState) {
        .running => {
            if (interruptPending) {
                handleInterrupt(gb, if_);
            }
            const cyclesElapsed = stepInstr(gb);
            return cyclesElapsed;
        },
        .halted => {
            if (interruptPending) {
                handleInterrupt(gb, if_);
                gb.execState = .running;
            }
            return 1;
        },
        .haltedDiscardInterrupt => {
            if (interruptPending) {
                discardInterrupt(gb, if_);
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

fn handleInterrupt(gb: *Gb, if_: u8) void {
    if (if_ & Interrupt.VBLANK > 0) {
        gb.push16(gb.pc);
        gb.pc = 0x0040;
        gb.write(IoReg.IF, if_ & ~Interrupt.VBLANK);
    } else if (if_ & Interrupt.STAT > 0) {
        gb.push16(gb.pc);
        gb.pc = 0x0048;
        gb.write(IoReg.IF, if_ & ~Interrupt.STAT);
    } else if (if_ & Interrupt.TIMER > 0) {
        gb.push16(gb.pc);
        gb.pc = 0x0050;
        gb.write(IoReg.IF, if_ & ~Interrupt.TIMER);
    } else if (if_ & Interrupt.SERIAL > 0) {
        gb.push16(gb.pc);
        gb.pc = 0x0058;
        gb.write(IoReg.IF, if_ & ~Interrupt.SERIAL);
    } else if (if_ & Interrupt.JOYPAD > 0) {
        gb.push16(gb.pc);
        gb.pc = 0x0060;
        gb.write(IoReg.IF, if_ & ~Interrupt.JOYPAD);
    }

    gb.ime = false;
}

fn discardInterrupt(gb: *Gb, if_: u8) void {
    if (if_ & Interrupt.VBLANK > 0) {
        gb.write(IoReg.IF, if_ & ~Interrupt.VBLANK);
    } else if (if_ & Interrupt.STAT > 0) {
        gb.write(IoReg.IF, if_ & ~Interrupt.STAT);
    } else if (if_ & Interrupt.TIMER > 0) {
        gb.write(IoReg.IF, if_ & ~Interrupt.TIMER);
    } else if (if_ & Interrupt.SERIAL > 0) {
        gb.write(IoReg.IF, if_ & ~Interrupt.SERIAL);
    } else if (if_ & Interrupt.JOYPAD > 0) {
        gb.write(IoReg.IF, if_ & ~Interrupt.JOYPAD);
    }
}
