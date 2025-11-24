const std = @import("std");

pub fn printAddrSpace(writer: *std.Io.Writer, pc: u16, rom_bank: u8) !void {
    switch (pc) {
        0x0000...0x3fff => try writer.print("rom__0::", .{}),
        0x4000...0x7fff => try writer.print("rom{d:_>3}::", .{rom_bank}),
        // TODO handle RAM banks
        else => try writer.print("        ", .{}),
    }
}
