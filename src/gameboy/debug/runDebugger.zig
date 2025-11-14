const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const DebugCmd = @import("cmd.zig").DebugCmd;
const executeCmd = @import("executeCmd.zig").executeCmd;

pub fn runDebugger(gb: *Gb) !void {
    gb.debug.std_out_mutex.lock();
    std.debug.print("> ", .{});
    gb.debug.std_out_mutex.unlock();

    while (true) {
        var input_buf: [1024]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&input_buf);
        const stdin_io_reader = &stdin_reader.interface;
        var line_writer = std.Io.Writer.Allocating.init(gb.debug.alloc);
        defer line_writer.deinit();
        _ = try stdin_io_reader.streamDelimiter(&line_writer.writer, '\n');
        const line = line_writer.written();

        gb.debug.std_out_mutex.lock();
        defer std.debug.print("> ", .{});
        defer gb.debug.std_out_mutex.unlock();

        var cmd: DebugCmd = undefined;
        if (line.len > 0) {
            cmd = DebugCmd.parse(line) orelse {
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
