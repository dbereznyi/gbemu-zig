const std = @import("std");
const Gb = @import("gameboy.zig").Gb;
const stepCpu = @import("cpu.zig").stepCpu;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const rom = try std.fs.cwd().readFileAlloc(alloc, "roms/hello-world.gb", 1024 * 1024 * 1024);
    var gb = try Gb.init(alloc, rom);

    const cycles = stepCpu(&gb);
    std.debug.print("cycles = {}\n", .{cycles});
}
