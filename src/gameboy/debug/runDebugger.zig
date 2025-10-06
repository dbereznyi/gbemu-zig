const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const executeCmd = @import("executeCmd.zig").executeCmd;

pub fn runDebugger(gb: *Gb) !void {
    gb.debug.std_out_mutex.lock();
    std.debug.print("> ", .{});
    gb.debug.std_out_mutex.unlock();

    while (true) {
        var input_buf: [128]u8 = undefined;
        const input_len = try std.io.getStdIn().read(&input_buf);

        gb.debug.std_out_mutex.lock();
        defer std.debug.print("> ", .{});
        defer gb.debug.std_out_mutex.unlock();

        var cmd: DebugCmd = undefined;
        if (input_len > 1) {
            cmd = DebugCmd.parse(input_buf[0..input_len]) orelse {
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
