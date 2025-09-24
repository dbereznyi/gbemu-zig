const Gb = @import("gameboy.zig").Gb;
const stepCpu = @import("cpu/step.zig").stepCpu;
const stepPpu = @import("ppu/step.zig").stepPpu;
const stepDma = @import("dma/step.zig").stepDma;
const stepJoypad = @import("joypad/step.zig").stepJoypad;
const stepTimer = @import("timer/step.zig").stepTimer;
const stepApu = @import("apu/step.zig").stepApu;
const shouldDebugBreak = @import("debug/shouldDebugBreak.zig").shouldDebugBreak;
const runDebugger = @import("debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("debug/executeCmd.zig").executeCmd;

pub fn stepGameboy(gb: *Gb, cycles: usize) !void {
    try processDebugCommand(gb);

    if (gb.debug.isPaused()) {
        return;
    }

    stepCpu(gb, cycles);
    stepJoypad(gb, cycles);
    stepPpu(gb, cycles);
    stepDma(gb, cycles);
    stepTimer(gb, cycles);
    stepApu(gb, cycles);

    gb.cycles +%= cycles;
}

fn processDebugCommand(gb: *Gb) !void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    try executeDebugCmd(debugCmd, gb);
    gb.debug.acknowledgeCommand();
}
