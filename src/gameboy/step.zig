const Gb = @import("gameboy.zig").Gb;
const stepCpu = @import("cpu/step.zig").stepCpu;
const stepPpu = @import("ppu/step.zig").stepPpu;
const stepDma = @import("dma/step.zig").stepDma;
const stepJoypad = @import("joypad/step.zig").stepJoypad;
const stepTimer = @import("timer/step.zig").stepTimer;
const shouldDebugBreak = @import("debug/shouldDebugBreak.zig").shouldDebugBreak;
const runDebugger = @import("debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("debug/executeCmd.zig").executeCmd;

pub fn stepGameboy(gb: *Gb, cycles: usize) !void {
    try processDebugCommand(gb);
    for (0..cycles) |_| {
        if (gb.debug.isPaused()) {
            return;
        }
        if (gb.cycles_until_ei == 1) {
            gb.ime = true;
        }
        gb.cycles_until_ei -|= 1;

        stepCpu(gb);
        stepJoypad(gb);
        stepPpu(gb);
        stepDma(gb);
        stepTimer(gb);

        gb.cycles +%= 1;
    }
}

fn processDebugCommand(gb: *Gb) !void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    try executeDebugCmd(debugCmd, gb);
    gb.debug.acknowledgeCommand();
}
