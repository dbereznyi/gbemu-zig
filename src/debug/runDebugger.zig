const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const executeCmd = @import("executeCmd.zig").executeCmd;

pub fn runDebugger(gb: *Gb) !void {
    while (true) {
        std.debug.print("> ", .{});
        var inputBuf: [128]u8 = undefined;
        const inputLen = try std.io.getStdIn().read(&inputBuf);

        if (inputLen > 0) {
            const cmd = DebugCmd.parse(inputBuf[0..inputLen]) orelse {
                std.debug.print("Invalid command\n", .{});
                continue;
            };

            gb.debug.sendCommand(cmd);

            gb.debug.pendingResultSem.wait();
            const result = gb.debug.pendingResult orelse continue;
            std.debug.print("{s}\n", .{result});
        }
    }
}
