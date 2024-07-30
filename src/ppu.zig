const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const AtomicOrder = std.builtin.AtomicOrder;

const LCDC_ON: u8 = 0b1000_0000;
const LCDC_WIN_TILE_MAP: u8 = 0b0100_0000;
const LCDC_WIN_DISP: u8 = 0b0010_0000;
const LCDC_TILE_DATA: u8 = 0b0001_0000;
const LCDC_BG_TILE_MAP: u8 = 0b0000_1000;
const LCDC_OBJ_SIZE: u8 = 0b0000_0100;
const LCDC_OBJ_DISP: u8 = 0b0000_0010;
const LCDC_BG_DISP: u8 = 0b0000_0001;

const PALETTE_GREY = [_]Pixel{
    .{ .r = 255, .g = 255, .b = 255 },
    .{ .r = 127, .g = 127, .b = 127 },
    .{ .r = 63, .g = 63, .b = 63 },
    .{ .r = 0, .g = 0, .b = 0 },
};

const OAM_TIME_NS: u64 = 19_000;
const DRAW_TIME_NS: u64 = 41_000;
const HBLANK_TIME_NS: u64 = 48_600;
const LINE_TIME_NS: u64 = 108_718;

pub fn runPpu(gb: *Gb, screenRwl: *std.Thread.RwLock, screen: []Pixel, quit: *std.atomic.Value(bool)) !void {
    while (true) {
        for (0..144) |y| {
            // Mode 2 - OAM scan

            std.time.sleep(OAM_TIME_NS);

            // Mode 3 - Drawing pixels

            const drawStart = try std.time.Instant.now();

            gb.vramMutex.lock();

            for (0..160) |x| {
                const lcdc = gb.read(IoReg.LCDC);
                const bgTileData = if (lcdc & LCDC_TILE_DATA > 0) gb.vram[0x0000..0x1000] else gb.vram[0x0800..0x1800];
                const bgTileMap = if (lcdc & LCDC_BG_TILE_MAP > 0) gb.vram[0x1c00..0x2000] else gb.vram[0x1800..0x1c00];

                const bgp = gb.read(IoReg.BGP);
                const scx = gb.read(IoReg.SCX);
                const scy = gb.read(IoReg.SCY);

                if (lcdc & LCDC_BG_DISP > 0) {
                    const scrolledX = x +% @as(usize, @intCast(scx));
                    const scrolledY = y +% @as(usize, @intCast(scy));
                    const currentTileIndex: usize = (@divTrunc(scrolledY, 8)) * 32 + (@divTrunc(scrolledX, 8));
                    const tileDataIndex: usize = if (lcdc & LCDC_TILE_DATA > 0) @as(usize, @intCast(bgTileMap[currentTileIndex])) else @as(usize, @intCast(bgTileMap[currentTileIndex] +% 128));
                    const rowIndex = scrolledY % 8;
                    const colIndex = scrolledX % 8;
                    const rowStart = (tileDataIndex * 16) + (rowIndex * 2);
                    const row = bgTileData[rowStart .. rowStart + 2];
                    const colMask = @as(u8, 1) << @as(u3, @truncate(7 - colIndex));
                    const highBit = (row[1] & colMask) >> @as(u3, @truncate(7 - colIndex));
                    const lowBit = (row[0] & colMask) >> @as(u3, @truncate(7 - colIndex));
                    const paletteIndex = 2 * highBit + lowBit;
                    const bgpMask = @as(u8, 0b11) << @as(u3, @truncate(paletteIndex * 2));
                    const bgpPaletteIndex = @as(usize, @intCast((bgp & bgpMask) >> @as(u3, @truncate(paletteIndex * 2))));

                    screenRwl.lock();
                    screen[y * 160 + x] = PALETTE_GREY[bgpPaletteIndex];
                    screenRwl.unlock();
                }
            }

            gb.vramMutex.unlock();

            const actualDrawTime = (try std.time.Instant.now()).since(drawStart);
            std.time.sleep(DRAW_TIME_NS -| actualDrawTime);

            // Mode 0 - Horizontal blank

            std.time.sleep(HBLANK_TIME_NS);
        }

        // Mode 1 - Vertical blank

        for (0..10) |_| {
            std.time.sleep(LINE_TIME_NS);
        }

        if (quit.load(AtomicOrder.monotonic)) {
            return;
        }
    }
}
