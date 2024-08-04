const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const LcdcFlag = @import("../gameboy.zig").LcdcFlag;
const ObjFlag = @import("../gameboy.zig").ObjFlag;
const stepCpu = @import("step.zig").stepCpu;
const decodeInstrAt = @import("decode.zig").decodeInstrAt;

pub fn runCpu(gb: *Gb, quit: *std.atomic.Value(bool)) !void {
    while (true) {
        const if_ = gb.read(IoReg.IF);
        const interruptPending = gb.ime and if_ > 0;

        switch (gb.execState) {
            .running => {
                const start = try std.time.Instant.now();

                if (interruptPending) {
                    handleInterrupt(gb, if_, false);
                }

                if (true) {
                    gb.debugPause();

                    std.debug.print("PC: {X:0>4} SP: {:0>4}\n", .{ gb.pc, gb.sp });
                    std.debug.print("Z: {} N: {} H: {} C: {}\n", .{ gb.zero, gb.negative, gb.halfCarry, gb.carry });
                    std.debug.print("A: {X:0>2} B: {X:0>2} D: {X:0>2} H {X:0>2}\n", .{ gb.a, gb.b, gb.d, gb.h });
                    std.debug.print("F: {X:0>2} C: {X:0>2} E: {X:0>2} L {X:0>2}\n", .{ gb.readFlags(), gb.c, gb.e, gb.l });
                    std.debug.print("LY: {X:0>2} LCDC: {b:0>8} STAT: {b:0>8}\n", .{
                        gb.read(IoReg.LY),
                        gb.read(IoReg.LCDC),
                        gb.read(IoReg.STAT),
                    });

                    const instr = decodeInstrAt(gb.pc, gb);
                    var instrStrBuf: [64]u8 = undefined;
                    const instrStr = try instr.toStr(&instrStrBuf);
                    std.debug.print("\n${X:0>4}: {s} ({X:0>2} {X:0>2} {X:0>2}) \n", .{
                        gb.pc,
                        instrStr,
                        gb.read(gb.pc),
                        gb.read(gb.pc + 1),
                        gb.read(gb.pc + 2),
                    });

                    var inputBuf: [64]u8 = undefined;
                    const inputLen = try std.io.getStdIn().read(&inputBuf);
                    if (inputLen > 0 and inputBuf[0] == 'q') {
                        quit.store(true, .monotonic);
                        gb.debugUnpause();
                        return;
                    }

                    gb.debugUnpause();
                }

                const cyclesElapsed = stepCpu(gb);

                const actualElapsed = (try std.time.Instant.now()).since(start);
                std.time.sleep(cyclesElapsed * 1000 -| actualElapsed);
            },
            .halted => {
                if (interruptPending) {
                    gb.execState = .running;
                    handleInterrupt(gb, if_, false);
                } else {
                    std.time.sleep(1000);
                }
            },
            .haltedSkipInterrupt => {
                if (interruptPending) {
                    gb.execState = .running;
                    handleInterrupt(gb, if_, true);
                } else {
                    std.time.sleep(1000);
                }
            },
            .stopped => {
                // TODO handle properly
                std.log.info("STOP was executed\n", .{});
                return;
            },
        }

        if (quit.load(.monotonic)) {
            return;
        }
    }
}

fn handleInterrupt(gb: *Gb, if_: u8, skipHandler: bool) void {
    gb.pushPc();

    if (if_ & Interrupt.VBLANK > 0) {
        if (!skipHandler) {
            gb.pc = 0x0040;
        }
        gb.write(IoReg.IF, if_ & ~Interrupt.VBLANK);
    } else if (if_ & Interrupt.STAT > 0) {
        if (!skipHandler) {
            gb.pc = 0x0048;
        }
        gb.write(IoReg.IF, if_ & ~Interrupt.STAT);
    } else if (if_ & Interrupt.TIMER > 0) {
        if (!skipHandler) {
            gb.pc = 0x0050;
        }
        gb.write(IoReg.IF, if_ & ~Interrupt.TIMER);
    } else if (if_ & Interrupt.SERIAL > 0) {
        if (!skipHandler) {
            gb.pc = 0x0058;
        }
        gb.write(IoReg.IF, if_ & ~Interrupt.SERIAL);
    } else if (if_ & Interrupt.JOYPAD > 0) {
        if (!skipHandler) {
            gb.pc = 0x0060;
        }
        gb.write(IoReg.IF, if_ & ~Interrupt.JOYPAD);
    }

    gb.ime = false;
}
