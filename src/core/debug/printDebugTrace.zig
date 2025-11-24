const std = @import("std");
const Gb = @import("../root.zig").Gb;
const decodeInstrAt = @import("../cpu/root.zig").decodeInstrAt;
const mem = @import("../memory/root.zig");
const printAddrSpace = @import("./printAddrSpace.zig").printAddrSpace;

pub fn printDebugTrace(gb: *Gb, writer: *std.Io.Writer) !void {
    //const PRINT_INSTR_BYTES = true;

    try gb.debug.printExecutionTrace(writer, 5);

    var pc_offset: u16 = 0;

    for (0..6) |instr_offset| {
        var instrStrBuf: [64]u8 = undefined;
        const instr = decodeInstrAt(gb.pc + pc_offset, gb);
        const bank = gb.cart.getBank(gb.pc + pc_offset);

        const instr_str = try instr.toStr(&instrStrBuf);
        try writer.print("{s} ", .{if (instr_offset == 0) "==>" else "   "});
        try printAddrSpace(writer, gb.pc, bank);
        try writer.print("{x:0>4}: {s} ", .{
            gb.pc + pc_offset,
            instr_str,
        });

        // if (PRINT_INSTR_BYTES) {
        //     try writer.print("(", .{});
        //     for (0..instr.size()) |i| {
        //         try writer.print("${x:0>2}", .{mem.read(gb, gb.pc + pc_offset + @as(u16, @intCast(i)))});
        //         if (i < instr.size() - 1) {
        //             try writer.print(" ", .{});
        //         }
        //     }
        //     try writer.print(")", .{});
        // }
        try writer.print("\n", .{});

        pc_offset += instr.size();
    }
}
