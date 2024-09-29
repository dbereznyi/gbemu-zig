const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const TacFlag = @import("../gameboy.zig").TacFlag;

pub fn stepTimer(gb: *Gb) void {
    gb.io_regs[IoReg.DIV] = @truncate(gb.timer.system_counter >> 8);
    gb.timer.system_counter +%= 1;

    const tac = gb.io_regs[IoReg.TAC];
    if (tac & TacFlag.ENABLE > 0) {
        switch (gb.timer.state) {
            .running => {
                const clock_speed: u2 = @as(u2, @truncate(tac & TacFlag.CLOCK_SELECT));
                const cycles_for_increment: usize = switch (clock_speed) {
                    // 4096Hz (increment every 256 M-cycles)
                    0b00 => 256,
                    // 262144Hz (increment every 4 M-cycles)
                    0b01 => 4,
                    // 65536Hz (increment every 16 M-cycles)
                    0b10 => 16,
                    // 16384Hz (increment every 64 M-cycles)
                    0b11 => 64,
                };

                gb.timer.cycles_elapsed += 1;
                if (gb.timer.cycles_elapsed >= cycles_for_increment) {
                    gb.timer.cycles_elapsed = 0;

                    gb.io_regs[IoReg.TIMA] +%= 1;
                    if (gb.io_regs[IoReg.TIMA] == 0x00) {
                        gb.timer.state = .reloading_tima;
                    }
                }
            },
            .reloading_tima => {
                gb.io_regs[IoReg.TIMA] = 0;
                gb.requestInterrupt(Interrupt.TIMER);
                gb.timer.state = .reloaded_tima;
            },
            .reloaded_tima => {
                gb.timer.state = .running;
            },
        }
    }
}
