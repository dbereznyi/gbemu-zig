const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const runCpu = @import("cpu/run.zig").runCpu;
const shouldDebugBreak = @import("debug/shouldDebugBreak.zig").shouldDebugBreak;
const runDebugger = @import("debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("debug/executeCmd.zig").executeCmd;

pub fn runGameboy(gb: *Gb) void {
    processDebugCommand(gb);

    if (gb.debug.isPaused()) {
        return;
    }

    runCpu(gb);
}

fn processDebugCommand(gb: *Gb) void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    executeDebugCmd(debugCmd, gb) catch {}; // TODO do something better on error
    gb.debug.acknowledgeCommand();
}
