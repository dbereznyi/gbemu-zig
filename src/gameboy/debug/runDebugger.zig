const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const executeCmd = @import("executeCmd.zig").executeCmd;

pub fn runDebugger(gb: *Gb) !void {
    gb.debug.stdOutMutex.lock();
    std.debug.print("> ", .{});
    gb.debug.stdOutMutex.unlock();

    while (true) {
        var inputBuf: [128]u8 = undefined;
        const inputLen = try std.io.getStdIn().read(&inputBuf);

        gb.debug.stdOutMutex.lock();
        defer std.debug.print("> ", .{});
        defer gb.debug.stdOutMutex.unlock();

        var cmd: DebugCmd = undefined;
        if (inputLen > 1) {
            cmd = DebugCmd.parse(inputBuf[0..inputLen]) orelse {
                std.debug.print("Invalid command\n\n", .{});
                continue;
            };
        } else {
            cmd = gb.debug.lastCommand orelse {
                continue;
            };
        }

        gb.debug.lastCommand = cmd;
        gb.debug.sendCommand(cmd);
        gb.debug.pendingResultSem.wait();
        std.debug.print("{s}\n", .{gb.debug.pendingResult.items});
        gb.debug.pendingResult.shrinkRetainingCapacity(0);
    }
}
