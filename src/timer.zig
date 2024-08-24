const Gb = @import("gameboy.zig").Gb;
const Interrupt = @import("gameboy.zig").Interrupt;
const IoReg = @import("gameboy.zig").IoReg;
const TacFlag = @import("gameboy.zig").TacFlag;

pub fn stepTimer(gb: *Gb) void {
    const div = gb.read(IoReg.DIV);
    gb.write(IoReg.DIV, div +% 8);

    const tac = gb.read(IoReg.TAC);
    if (tac & TacFlag.ENABLE > 0) {
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

        if (gb.timer.cycles_elapsed >= cycles_for_increment) {
            gb.timer.cycles_elapsed = 0;

            const tima = gb.read(IoReg.TIMA);
            if (tima == 0xff) {
                gb.write(IoReg.TIMA, gb.read(IoReg.TMA));
                gb.requestInterrupt(Interrupt.TIMER);
            } else {
                gb.write(IoReg.TIMA, tima +% 1);
            }
        } else {
            gb.timer.cycles_elapsed += 1;
        }
    }
}
