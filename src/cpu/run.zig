const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const LcdcFlag = @import("../gameboy.zig").LcdcFlag;
const ObjFlag = @import("../gameboy.zig").ObjFlag;
const sleepPrecise = @import("../util.zig").sleepPrecise;
const stepInstr = @import("step.zig").stepInstr;
const decodeInstrAt = @import("decode.zig").decodeInstrAt;
const parseDebugCmd = @import("../debug.zig").parseDebugCmd;

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

pub fn runCpu(gb: *Gb, quit: *std.atomic.Value(bool)) !void {
    while (true) {
        const if_ = gb.read(IoReg.IF);
        const interruptPending = gb.ime and if_ > 0;

        switch (gb.execState) {
            .running => {
                var breakpointHit = false;
                for (gb.debug.breakpoints.items) |breakpoint| {
                    if (gb.pc == breakpoint) {
                        breakpointHit = true;
                        break;
                    }
                }
                if (gb.debug.stepModeEnabled or breakpointHit) {
                    gb.debug.stepModeEnabled = true;
                    try debugBreak(gb, quit);
                }

                const start = try std.time.Instant.now();

                if (interruptPending) {
                    handleInterrupt(gb, if_);
                }

                const cyclesElapsed = stepInstr(gb);

                const actualElapsed = (try std.time.Instant.now()).since(start);
                gb.debug.expectedCpuTimeNs = cyclesElapsed * 1000;
                gb.debug.actualCpuTimeNs = actualElapsed;

                try sleepPrecise(cyclesElapsed * 1000 -| actualElapsed);
            },
            .halted => {
                if (interruptPending) {
                    gb.execState = .running;
                    handleInterrupt(gb, if_);
                } else {
                    try sleepPrecise(1000);
                    //gb.waitForInterrupt();
                }
            },
            .haltedDiscardInterrupt => {
                if (interruptPending) {
                    gb.execState = .running;
                    discardInterrupt(gb, if_);
                } else {
                    gb.waitForInterrupt();
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

fn debugBreak(gb: *Gb, quit: *std.atomic.Value(bool)) !void {
    gb.debugPause();

    printRegisters(gb);

    var instrStrBuf: [64]u8 = undefined;
    var instrNextStrBuf: [64]u8 = undefined;

    const instr = decodeInstrAt(gb.pc, gb);
    const instrStr = try instr.toStr(&instrStrBuf);

    const instrNext = decodeInstrAt(gb.pc + instr.size(), gb);
    const instrNextStr = try instrNext.toStr(&instrNextStrBuf);

    std.debug.print("\n", .{});
    std.debug.print("==> ${x:0>4}: {s} (${x:0>2} ${x:0>2} ${x:0>2}) \n", .{
        gb.pc,
        instrStr,
        gb.read(gb.pc),
        gb.read(gb.pc + 1),
        gb.read(gb.pc + 2),
    });
    std.debug.print("    ${x:0>4}: {s} (${x:0>2} ${x:0>2} ${x:0>2}) \n", .{
        gb.pc + instr.size(),
        instrNextStr,
        gb.read(gb.pc + instr.size()),
        gb.read(gb.pc + instr.size() + 1),
        gb.read(gb.pc + instr.size() + 2),
    });

    var resumeExecution = false;
    while (!resumeExecution) {
        std.debug.print("> ", .{});

        var inputBuf: [64]u8 = undefined;
        const inputLen = try std.io.getStdIn().read(&inputBuf);

        if (inputLen > 1) {
            const cmd = parseDebugCmd(inputBuf[0..inputLen]) orelse {
                std.debug.print("Invalid command\n", .{});
                continue;
            };

            switch (cmd) {
                .quit => {
                    quit.store(true, .monotonic);
                    resumeExecution = true;
                },
                .step => {
                    resumeExecution = true;
                },
                .continue_ => {
                    gb.debug.stepModeEnabled = false;
                    resumeExecution = true;
                },
                .breakpointList => blk: {
                    if (gb.debug.breakpoints.items.len == 0) {
                        std.debug.print("No active breakpoints set.\n", .{});
                        break :blk;
                    }

                    std.debug.print("Active breakpoints:\n", .{});

                    for (gb.debug.breakpoints.items) |breakpoint| {
                        std.debug.print("  ${x:0>4}\n", .{breakpoint});
                    }
                },
                .breakpointSet => |addr| {
                    try gb.debug.breakpoints.append(addr);
                    std.debug.print("Set breakpoint at ${x:0>4}\n", .{addr});
                },
                .viewRegisters => printRegisters(gb),
                .viewStack => {
                    var addr = gb.sp;
                    while (addr < gb.debug.stackBase) {
                        std.debug.print("  ${x:0>4}: ${x:0>2}\n", .{ addr, gb.read(addr) });
                        addr += 1;
                    }
                },
            }

            std.debug.print("\n", .{});
        } else {
            resumeExecution = true;
        }
    }

    gb.debugUnpause();
}

fn printRegisters(gb: *Gb) void {
    std.debug.print("PC: ${x:0>4} SP: ${x:0>4}\n", .{ gb.pc, gb.sp });
    std.debug.print("Z: {} N: {} H: {} C: {}\n", .{ gb.zero, gb.negative, gb.halfCarry, gb.carry });
    std.debug.print("A: ${x:0>2} B: ${x:0>2} D: ${x:0>2} H: ${x:0>2}\n", .{ gb.a, gb.b, gb.d, gb.h });
    std.debug.print("F: ${x:0>2} C: ${x:0>2} E: ${x:0>2} L: ${x:0>2}\n", .{ gb.readFlags(), gb.c, gb.e, gb.l });
    std.debug.print("LY: ${x:0>2} LCDC: %{b:0>8} STAT: %{b:0>8}\n", .{
        gb.read(IoReg.LY),
        gb.read(IoReg.LCDC),
        gb.read(IoReg.STAT),
    });
}
