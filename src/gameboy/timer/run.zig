const Gb = @import("../root.zig").Gb;
const Interrupt = @import("../root.zig").Interrupt;
const IoReg = @import("../root.zig").IoReg;
const TacFlag = @import("./timer.zig").TacFlag;
const constants = @import("constants");

pub fn runTimer(gb: *Gb, cycles: usize) void {
    var rem_cycles = cycles + gb.timer.odd_cycles;
    while (rem_cycles >= 4) {
        rem_cycles -= 4;

        updateSystemCounter(gb, gb.timer.system_counter +% 4);

        switch (gb.timer.state) {
            .running => {},
            .reloading_tima => {
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

const TAC_TRIGGER_BITS = [_]usize{ 512, 8, 32, 128 };

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
