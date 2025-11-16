const std = @import("std");
const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;
const ApuReg = @import("../apu/apu.zig").ApuReg;
const MbcReg = @import("../cart.zig").MbcReg;

pub fn writeBess(gb: *Gb, writer: *std.Io.Writer) !void {
    const ram_start = writer.end;
    try writer.writeAll(gb.wram);

    const vram_start = writer.end;
    try writer.writeAll(gb.vram);

    const mbc_ram_start = writer.end;
    try writer.writeAll(gb.cart.ram);

    const oam_start = writer.end;
    try writer.writeAll(gb.oam);

    const hram_start = writer.end;
    try writer.writeAll(gb.hram);

    const first_block_start = writer.end;
    try writeName(writer);
    try writeInfo(writer, gb.cart.rom_title, gb.cart.global_checksum);
    try writeCore(
        writer,
        gb,
        ram_start,
        vram_start,
        mbc_ram_start,
        oam_start,
        hram_start,
    );
    try writeMbc(writer, gb);
    try writeEnd(writer);

    try writer.writeInt(u32, @truncate(first_block_start), .little);
    try writer.writeAll("BESS");
}

fn writeName(writer: *std.Io.Writer) !void {
    const name = "dbereznyi/gbemu";
    try writer.writeAll("NAME");
    try writer.writeInt(u32, name.len, .little);
    try writer.writeAll(name);
}

fn writeInfo(writer: *std.Io.Writer, title: []const u8, checksum: u16) !void {
    if (title.len != 16) {
        return error.InfoBlockInvalidTitleLength;
    }

    try writer.writeAll("INFO");
    try writer.writeInt(u32, 18, .little);
    try writer.writeAll(title[0..16]);
    try writer.writeInt(u16, checksum, .little);
}

fn writeCore(
    writer: *std.Io.Writer,
    gb: *Gb,
    ram_start: usize,
    vram_start: usize,
    mbc_ram_start: usize,
    oam_start: usize,
    hram_start: usize,
) !void {
    try writer.writeAll("CORE");
    try writer.writeInt(u32, 208, .little);

    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 1, .little);

    try writer.writeAll("GD  ");

    try writer.writeInt(u16, gb.pc, .little);
    const af = @as(u16, @intCast(gb.a)) << 8 | @as(u16, @intCast(gb.readFlags()));
    try writer.writeInt(u16, af, .little);
    const bc = @as(u16, @intCast(gb.b)) << 8 | @as(u16, gb.c);
    try writer.writeInt(u16, bc, .little);
    const de = @as(u16, @intCast(gb.d)) << 8 | @as(u16, gb.e);
    try writer.writeInt(u16, de, .little);
    const hl = @as(u16, @intCast(gb.h)) << 8 | @as(u16, gb.l);
    try writer.writeInt(u16, hl, .little);
    try writer.writeInt(u16, gb.sp, .little);
    try writer.writeByte(if (gb.ime) 1 else 0);
    try writer.writeByte(gb.ie);
    try writer.writeByte(if (gb.stopped) 2 else if (gb.halted) 1 else 0);
    try writer.writeByte(0);

    try writer.writeByte(gb.io_regs[IoReg.JOYP]); // 0x00
    try writer.writeByte(0); // 0x01
    try writer.writeByte(0); // 0x02
    try writer.writeByte(0); // 0x03
    try writer.writeByte(@truncate(gb.timer.system_counter >> 8)); // 0x04
    try writer.writeByte(gb.io_regs[IoReg.TIMA]); // 0x05
    try writer.writeByte(gb.io_regs[IoReg.TMA]); // 0x06
    try writer.writeByte(gb.io_regs[IoReg.TAC]); // 0x07
    for (0x08..0x0f) |_| {
        try writer.writeByte(0);
    }
    try writer.writeByte(gb.io_regs[IoReg.IF]); // 0x0f
    try writer.writeByte(gb.apu.readReg(ApuReg.NR10)); // 0x10
    try writer.writeByte(gb.apu.readReg(ApuReg.NR11)); // 0x11
    try writer.writeByte(gb.apu.readReg(ApuReg.NR12)); // 0x12
    try writer.writeByte(gb.apu.readReg(ApuReg.NR13)); // 0x13
    try writer.writeByte(gb.apu.readReg(ApuReg.NR14)); // 0x14
    try writer.writeByte(0); // 0x15
    try writer.writeByte(gb.apu.readReg(ApuReg.NR21)); // 0x16
    try writer.writeByte(gb.apu.readReg(ApuReg.NR22)); // 0x17
    try writer.writeByte(gb.apu.readReg(ApuReg.NR23)); // 0x18
    try writer.writeByte(gb.apu.readReg(ApuReg.NR24)); // 0x19
    try writer.writeByte(gb.apu.readReg(ApuReg.NR30)); // 0x1a
    try writer.writeByte(gb.apu.readReg(ApuReg.NR31)); // 0x1b
    try writer.writeByte(gb.apu.readReg(ApuReg.NR32)); // 0x1c
    try writer.writeByte(gb.apu.readReg(ApuReg.NR33)); // 0x1d
    try writer.writeByte(gb.apu.readReg(ApuReg.NR34)); // 0x1e
    try writer.writeByte(0); // 0x1f
    try writer.writeByte(gb.apu.readReg(ApuReg.NR41)); // 0x20
    try writer.writeByte(gb.apu.readReg(ApuReg.NR42)); // 0x21
    try writer.writeByte(gb.apu.readReg(ApuReg.NR43)); // 0x22
    try writer.writeByte(gb.apu.readReg(ApuReg.NR44)); // 0x23
    try writer.writeByte(gb.apu.readReg(ApuReg.NR50)); // 0x24
    try writer.writeByte(gb.apu.readReg(ApuReg.NR51)); // 0x25
    try writer.writeByte(gb.apu.readReg(ApuReg.NR52)); // 0x26
    for (0x27..0x30) |_| {
        try writer.writeByte(0); // 0x27-0x2f
    }
    {
        const wav_ram = gb.apu.ch3.wav_ram;
        var i: usize = 0;
        while (i < 32) : (i += 2) {
            const upper: u8 = wav_ram[i];
            const lower: u8 = wav_ram[i + 1];
            try writer.writeByte((upper << 4) | lower); // 0x30-0x3f
        }
    }
    try writer.writeByte(gb.io_regs[IoReg.LCDC]); // 0x40
    try writer.writeByte(gb.io_regs[IoReg.STAT]); // 0x41
    try writer.writeByte(gb.io_regs[IoReg.SCY]); // 0x42
    try writer.writeByte(gb.io_regs[IoReg.SCX]); // 0x43
    try writer.writeByte(gb.io_regs[IoReg.LY]); // 0x44
    try writer.writeByte(gb.io_regs[IoReg.LYC]); // 0x45
    try writer.writeByte(gb.io_regs[IoReg.DMA]); // 0x46
    try writer.writeByte(gb.io_regs[IoReg.BGP]); // 0x47
    try writer.writeByte(gb.io_regs[IoReg.OBP0]); // 0x48
    try writer.writeByte(gb.io_regs[IoReg.OBP1]); // 0x49
    try writer.writeByte(gb.io_regs[IoReg.WY]); // 0x4a
    try writer.writeByte(gb.io_regs[IoReg.WX]); // 0x4b
    for (0x4c..0x80) |_| {
        try writer.writeByte(0);
    }

    try writer.writeInt(u32, @truncate(gb.wram.len), .little);
    try writer.writeInt(u32, @truncate(ram_start), .little);
    try writer.writeInt(u32, @truncate(gb.vram.len), .little);
    try writer.writeInt(u32, @truncate(vram_start), .little);
    try writer.writeInt(u32, @truncate(gb.cart.ram.len), .little);
    try writer.writeInt(u32, @truncate(mbc_ram_start), .little);
    try writer.writeInt(u32, @truncate(gb.oam.len), .little);
    try writer.writeInt(u32, @truncate(oam_start), .little);
    try writer.writeInt(u32, @truncate(gb.hram.len), .little);
    try writer.writeInt(u32, @truncate(hram_start), .little);
    // BGP palettes
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u32, 0, .little);
    // OBJ palettes
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u32, 0, .little);
}

fn writeMbc(writer: *std.Io.Writer, gb: *Gb) !void {
    try writer.writeAll("MBC ");

    var buf: [16]MbcReg = undefined;
    const regs = gb.cart.getMbcRegisters(&buf);
    try writer.writeInt(u32, @truncate(regs.len * 3), .little);

    for (regs) |reg| {
        try writer.writeInt(u16, reg.addr, .little);
        try writer.writeByte(reg.val);
    }
}

fn writeEnd(writer: *std.Io.Writer) !void {
    try writer.writeAll("END ");
    try writer.writeInt(u32, 0, .little);
}
