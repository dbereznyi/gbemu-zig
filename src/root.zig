const std = @import("std");
const testing = std.testing;

test "bess" {
    const Gb = @import("gameboy/gameboy.zig").Gb;
    const IoReg = @import("gameboy/gameboy.zig").IoReg;
    const readBess = @import("gameboy/bess.zig").readBess;
    const loadBess = @import("gameboy/bess.zig").loadBess;
    const writeBess = @import("gameboy/bess.zig").writeBess;
    const runGameboyForNumCycles = @import("gameboy/run.zig").runGameboyForNumCycles;

    const alloc = std.testing.allocator;

    const rom = try std.fs.cwd().readFileAlloc(alloc, "roms/hello-world.gb", 128 * 1024);
    defer alloc.free(rom);

    var gb = try Gb.init(alloc, rom, null);
    defer gb.deinit(alloc);

    runGameboyForNumCycles(&gb, 20000);

    const pc_prev = gb.pc;
    const sp_prev = gb.sp;
    const a_prev = gb.a;
    const b_prev = gb.b;
    const c_prev = gb.c;
    const d_prev = gb.d;
    const e_prev = gb.e;
    const h_prev = gb.h;
    const l_prev = gb.l;
    const zero_prev = gb.zero;
    const negative_prev = gb.negative;
    const halfCarry_prev = gb.halfCarry;
    const carry_prev = gb.carry;
    const vram_prev = try alloc.dupe(u8, gb.vram);
    defer alloc.free(vram_prev);
    const wram_prev = try alloc.dupe(u8, gb.wram);
    defer alloc.free(wram_prev);
    const oam_prev = try alloc.dupe(u8, gb.oam);
    defer alloc.free(oam_prev);
    const system_counter_prev = gb.timer.system_counter;
    const io_regs_prev = try alloc.dupe(u8, gb.io_regs);
    defer alloc.free(io_regs_prev);
    const hram_prev = try alloc.dupe(u8, gb.hram);
    defer alloc.free(hram_prev);
    const ie_prev = gb.ie;
    const cart_ram_prev = try alloc.dupe(u8, gb.cart.ram);
    defer alloc.free(cart_ram_prev);

    const bess_buf = try alloc.alloc(u8, 64 * 1024 * 1024);
    defer alloc.free(bess_buf);
    var bess_fbs = std.io.fixedBufferStream(bess_buf);
    var bess_writer = std.io.countingWriter(bess_fbs.writer());
    try writeBess(&gb, bess_writer.writer());

    const bess_data = bess_buf[0..bess_writer.bytes_written];

    // {
    //     const file = try std.fs.cwd().createFile("bess.dat", .{});
    //     try file.writer().writeAll(bess_data);
    // }

    const bess = try readBess(alloc, bess_data);
    defer bess.deinit(alloc);

    loadBess(&gb, bess);

    try testing.expect(gb.pc == pc_prev);
    try testing.expect(gb.sp == sp_prev);
    try testing.expect(gb.a == a_prev);
    try testing.expect(gb.b == b_prev);
    try testing.expect(gb.c == c_prev);
    try testing.expect(gb.d == d_prev);
    try testing.expect(gb.e == e_prev);
    try testing.expect(gb.h == h_prev);
    try testing.expect(gb.l == l_prev);
    try testing.expect(gb.zero == zero_prev);
    try testing.expect(gb.negative == negative_prev);
    try testing.expect(gb.halfCarry == halfCarry_prev);
    try testing.expect(gb.carry == carry_prev);
    try testing.expect(std.mem.eql(u8, gb.vram, vram_prev));
    try testing.expect(std.mem.eql(u8, gb.wram, wram_prev));
    try testing.expect(std.mem.eql(u8, gb.oam, oam_prev));
    try testing.expect(gb.io_regs[IoReg.JOYP] == io_regs_prev[IoReg.JOYP]);
    try testing.expect(gb.timer.system_counter & 0xff00 == system_counter_prev & 0xff00);
    try testing.expect(gb.io_regs[IoReg.TIMA] == io_regs_prev[IoReg.TIMA]);
    try testing.expect(gb.io_regs[IoReg.TMA] == io_regs_prev[IoReg.TMA]);
    try testing.expect(gb.io_regs[IoReg.TAC] == io_regs_prev[IoReg.TAC]);
    try testing.expect(gb.io_regs[IoReg.IF] == io_regs_prev[IoReg.IF]);
    try testing.expect(gb.io_regs[IoReg.LCDC] == io_regs_prev[IoReg.LCDC]);
    try testing.expect(gb.io_regs[IoReg.STAT] == io_regs_prev[IoReg.STAT]);
    try testing.expect(gb.io_regs[IoReg.SCY] == io_regs_prev[IoReg.SCY]);
    try testing.expect(gb.io_regs[IoReg.SCX] == io_regs_prev[IoReg.SCX]);
    // try testing.expect(gb.io_regs[IoReg.LY] == io_regs_prev[IoReg.LY]);
    // try testing.expect(gb.io_regs[IoReg.LYC] == io_regs_prev[IoReg.LYC]);
    try testing.expect(gb.io_regs[IoReg.DMA] == io_regs_prev[IoReg.DMA]);
    try testing.expect(gb.io_regs[IoReg.BGP] == io_regs_prev[IoReg.BGP]);
    try testing.expect(gb.io_regs[IoReg.OBP0] == io_regs_prev[IoReg.OBP0]);
    try testing.expect(gb.io_regs[IoReg.OBP1] == io_regs_prev[IoReg.OBP1]);
    try testing.expect(gb.io_regs[IoReg.WY] == io_regs_prev[IoReg.WY]);
    try testing.expect(gb.io_regs[IoReg.WX] == io_regs_prev[IoReg.WX]);
    try testing.expect(std.mem.eql(u8, gb.hram, hram_prev));
    try testing.expect(gb.ie == ie_prev);
    try testing.expect(std.mem.eql(u8, gb.cart.ram, cart_ram_prev));
}
