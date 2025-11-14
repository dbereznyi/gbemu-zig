const Gb = @import("../gameboy.zig").Gb;
const Interrupt = @import("../gameboy.zig").Interrupt;
const IoReg = @import("../gameboy.zig").IoReg;
const TacFlag = @import("../gameboy.zig").TacFlag;
const constants = @import("../../constants.zig");

const TAC_TRIGGER_BITS = [_]usize{ 512, 8, 32, 128 };

pub fn runTimer(gb: *Gb, cycles: usize) void {
    var rem_cycles = cycles + gb.timer.odd_cycles;
    while (rem_cycles >= 4) {
        rem_cycles -= 4;

        updateSystemCounter(gb, gb.timer.system_counter +% 4);

        switch (gb.timer.state) {
            .running => {},
            // .running => {
            //     // TODO TIMA should increment when a specific bit in the system counter rolls changes from 0 to 1

            //     const clock_speed: u2 = @as(u2, @truncate(tac & TacFlag.CLOCK_SELECT));
            //     const cycles_for_increment: usize = switch (clock_speed) {
            //         // 4096Hz (increment every 256 M-cycles)
            //         0b00 => 256,
            //         // 262144Hz (increment every 4 M-cycles)
            //         0b01 => 4,
            //         // 65536Hz (increment every 16 M-cycles)
            //         0b10 => 16,
            //         // 16384Hz (increment every 64 M-cycles)
            //         0b11 => 64,
            //     };

            //     gb.timer.cycles_elapsed += 1;
            //     if (gb.timer.cycles_elapsed >= cycles_for_increment) {
            //         gb.timer.cycles_elapsed = 0;

            //         gb.io_regs[IoReg.TIMA] +%= 1;
            //         if (gb.io_regs[IoReg.TIMA] == 0x00) {
            //             gb.timer.state = .reloading_tima;
            //         }
            //     }
            // },
            .reloading_tima => {
                //gb.io_regs[IoReg.TIMA] = 0;
                gb.requestInterrupt(Interrupt.TIMER);
                gb.timer.state = .reloaded_tima;
            },
            .reloaded_tima => {
                gb.timer.state = .running;
            },
        }

        // 1 APU cycle is 2MHz, so 2 cycles happen for every M-cycle
        gb.apu.cycles += 2;
        gb.apu.sample_cycles += constants.AUDIO.SAMPLE_RATE * 4;
    }

    gb.timer.odd_cycles = rem_cycles;
}

fn updateSystemCounter(gb: *Gb, new_value: u16) void {
    const primary_triggers = gb.timer.system_counter & ~new_value;
    if (gb.io_regs[IoReg.TAC] & TacFlag.ENABLE > 0 and primary_triggers & TAC_TRIGGER_BITS[@intCast(gb.io_regs[IoReg.TAC] & 0b11)] > 0) {
        gb.io_regs[IoReg.TIMA] +%= 1;
        if (gb.io_regs[IoReg.TIMA] == 0x00) {
            gb.io_regs[IoReg.TIMA] = gb.io_regs[IoReg.TMA];
            gb.timer.state = .reloading_tima;
        }
    }

    const bitmask = 0x1000;
    if (primary_triggers & bitmask != 0) {
        // bit changed from 0 to 1
        gb.apu.handleDivEvent();
    } else {
        const secondary_triggers = ~gb.timer.system_counter & new_value;
        if (secondary_triggers & bitmask != 0) {
            // bit was 1, changed back to 0
            gb.apu.handleSecondaryDivEvent();
        }
    }

    gb.timer.system_counter = new_value;
}
