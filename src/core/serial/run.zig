const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;

const SC_TRANSFER_ENABLE = 0x80;
const SC_CLOCK_SELECT = 0x01;

pub fn runSerial(gb: *Gb, cycles: usize) void {
    if (gb.io_regs[IoReg.SC] & SC_TRANSFER_ENABLE == 0) {
        return;
    }

    gb.serial.bits_transferred = 0;

    if (gb.io_regs[IoReg.SC] & SC_CLOCK_SELECT == 1) {
        // Try to send a bit out
        const send_bit: u1 = @truncate((gb.io_regs[IoReg.SB] & 0x80) >> 7);
        const sent = gb.serial.callback.send(send_bit);
        if (sent) {
            gb.io_regs[IoReg.SB] <<= 1;
            const received_bit = gb.serial.callback.receive() orelse 1;
        }
    } else {
        // Wait for a bit to come in
    }
}
