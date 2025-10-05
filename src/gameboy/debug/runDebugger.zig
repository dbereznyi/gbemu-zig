const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const executeCmd = @import("executeCmd.zig").executeCmd;

pub fn runDebugger(gb: *Gb) !void {
    gb.debug.std_out_mutex.lock();
    std.debug.print("> ", .{});
    gb.debug.std_out_mutex.unlock();

    while (true) {
        var inputBuf: [128]u8 = undefined;
        const inputLen = try std.io.getStdIn().read(&inputBuf);

        gb.debug.std_out_mutex.lock();
        defer std.debug.print("> ", .{});
        defer gb.debug.std_out_mutex.unlock();

        var cmd: DebugCmd = undefined;
        if (inputLen > 1) {
            cmd = DebugCmd.parse(inputBuf[0..inputLen]) orelse {
                std.debug.print("Invalid command\n\n", .{});
                continue;
            };
        } else {
            cmd = gb.debug.last_command orelse {
                continue;
            };
        }

        gb.debug.last_command = cmd;
        gb.debug.sendCommand(cmd);
        gb.debug.pending_result_sem.wait();
        std.debug.print("{s}\n", .{gb.debug.pending_result.items});
        gb.debug.pending_result.shrinkRetainingCapacity(0);
    }
}
