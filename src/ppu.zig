const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const Interrupt = @import("gameboy.zig").Interrupt;
const LcdcFlag = @import("gameboy.zig").LcdcFlag;
const ObjFlag = @import("gameboy.zig").ObjFlag;
const StatFlag = @import("gameboy.zig").StatFlag;
const AtomicOrder = std.builtin.AtomicOrder;
const sleepPrecise = @import("util.zig").sleepPrecise;

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

const TileDataAddressingMode = enum {
    unsigned, // "$8000 method"
    signed, // "$8800 method"
};

const ObjectAttribute = struct {
    y: u8,
    x: u8,
    tileNumber: u8,
    flags: u8,
    oamIndex: usize, // used for sorting
};

fn objectAttributeIsLessThan(_: void, lhs: ObjectAttribute, rhs: ObjectAttribute) bool {
    if (lhs.x != rhs.x) {
        return lhs.x < rhs.x;
    }

    return lhs.oamIndex < rhs.oamIndex;
}

pub fn runPpu(gb: *Gb, screenRwl: *std.Thread.RwLock, screen: []Pixel, quit: *std.atomic.Value(bool)) !void {
    const palette = PALETTE_GREY;

    while (true) {
        const wy = gb.read(IoReg.WY); // WY is only checked once per frame

        // If the window gets disabled during HBlank and then re-enabled later on,
        // we want to continue drawing from where we left off.
        // To do this, the current Y position of the window is tracked separately.
        var windowY: usize = 0;

        const ie = gb.read(IoReg.IE);
        const stat = gb.read(IoReg.STAT);
        const vblankInterruptsEnabled = ie & Interrupt.VBLANK > 0;
        const statInterruptsEnabled = ie & Interrupt.STAT > 0;
        const intOnMode0 = stat & StatFlag.INT_MODE_0_ENABLE > 0;
        const intOnMode1 = stat & StatFlag.INT_MODE_1_ENABLE > 0;
        const intOnMode2 = stat & StatFlag.INT_MODE_2_ENABLE > 0;
        const intOnLycIncident = stat & StatFlag.INT_LYC_INCIDENT_ENABLE > 0;

        for (0..144) |y| {
            // Mode 2 - OAM scan
            const oamStart = try std.time.Instant.now();
            gb.oamMutex.lock();

            if (gb.ime and statInterruptsEnabled and intOnMode2) {
                gb.requestInterrupt(Interrupt.STAT);
            }

            gb.setStatMode(StatFlag.MODE_2);

            var objAttrsLineArr: [10]ObjectAttribute = undefined;
            var objAttrsLineLen: usize = 0;
            readObjectAttributesForLine(y, &objAttrsLineArr, &objAttrsLineLen, gb);
            const objAttrsLine = objAttrsLineArr[0..objAttrsLineLen];

            const actualOamTime = (try std.time.Instant.now()).since(oamStart);
            try sleepPrecise(OAM_TIME_NS -| actualOamTime);

            gb.oamMutex.unlock();

            // Mode 3 - Drawing pixels

            const drawStart = try std.time.Instant.now();
            gb.setStatMode(StatFlag.MODE_3);

            for (0..160) |x| {
                screenRwl.lock();
                const colorId = colorIdAt(x, y, gb, objAttrsLine, &windowY, wy);
                screen[y * 160 + x] = palette[colorId];
                screenRwl.unlock();
            }

            const actualDrawTime = (try std.time.Instant.now()).since(drawStart);
            try sleepPrecise(DRAW_TIME_NS -| actualDrawTime);

            // Mode 0 - Horizontal blank

            gb.write(IoReg.LY, @truncate(y));
            const lycIncident = y == gb.read(IoReg.LYC);
            gb.setStatLycIncident(lycIncident);
            if (gb.ime and statInterruptsEnabled and intOnLycIncident and lycIncident) {
                gb.requestInterrupt(Interrupt.STAT);
            }

            gb.setStatMode(StatFlag.MODE_0);
            if (gb.ime and statInterruptsEnabled and intOnMode0) {
                gb.requestInterrupt(Interrupt.STAT);
            }

            try sleepPrecise(HBLANK_TIME_NS);

            gb.waitForDebugUnpause();
        }

        // Mode 1 - Vertical blank

        gb.setStatMode(StatFlag.MODE_1);
        if (gb.ime and statInterruptsEnabled and intOnMode1) {
            gb.requestInterrupt(Interrupt.STAT);
        }
        if (gb.ime and vblankInterruptsEnabled) {
            gb.requestInterrupt(Interrupt.VBLANK);
        }

        for (0..10) |_| {
            const ly = gb.read(IoReg.LY);
            gb.write(IoReg.LY, ly +% 1);

            try sleepPrecise(LINE_TIME_NS);

            gb.waitForDebugUnpause();
        }

        if (quit.load(AtomicOrder.monotonic)) {
            return;
        }
    }
}

fn readObjectAttributesForLine(y: usize, objAttrsLine: *[10]ObjectAttribute, objAttrsLineLen: *usize, gb: *Gb) void {
    var objAttrs: [40]ObjectAttribute = undefined;
    var objAttrsIndex: usize = 0;
    var oamIndex: usize = 0;
    while (oamIndex < gb.oam.len) {
        objAttrs[objAttrsIndex].y = gb.oam[oamIndex];
        objAttrs[objAttrsIndex].x = gb.oam[oamIndex + 1];
        objAttrs[objAttrsIndex].tileNumber = gb.oam[oamIndex + 2];
        objAttrs[objAttrsIndex].flags = gb.oam[oamIndex + 3];
        objAttrs[objAttrsIndex].oamIndex = oamIndex;

        objAttrsIndex += 1;
        oamIndex += 4;
    }
    std.sort.block(ObjectAttribute, &objAttrs, {}, objectAttributeIsLessThan);

    const lcdc = gb.read(IoReg.LCDC);

    objAttrsLineLen.* = 0;
    for (objAttrs) |obj| {
        const yLowerBound = obj.y -% 16;
        const yUpperBound = if (lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0) obj.y else obj.y -% 8;

        if (y >= yLowerBound and y < yUpperBound) {
            const i = objAttrsLineLen.*;
            objAttrsLine[i].y = obj.y;
            objAttrsLine[i].x = obj.x;
            objAttrsLine[i].tileNumber = obj.tileNumber;
            objAttrsLine[i].flags = obj.flags;
            objAttrsLine[i].oamIndex = obj.oamIndex;
            objAttrsLineLen.* += 1;
            if (objAttrsLineLen.* == 10) {
                break;
            }
        }
    }

    std.mem.reverse(ObjectAttribute, objAttrsLine[0..objAttrsLineLen.*]);
}

fn colorIdAt(x: usize, y: usize, gb: *Gb, objAttrs: []const ObjectAttribute, windowY: *usize, wy: u8) usize {
    const lcdc = gb.read(IoReg.LCDC);

    if (lcdc & LcdcFlag.ON == 0) {
        return 0;
    }

    gb.vramMutex.lock();

    const bgTileData = if (lcdc & LcdcFlag.TILE_DATA > 0) gb.vram[0x0000..0x1000] else gb.vram[0x0800..0x1800];
    const bgTileMap = if (lcdc & LcdcFlag.BG_TILE_MAP > 0) gb.vram[0x1c00..0x2000] else gb.vram[0x1800..0x1c00];
    const winTileMap = if (lcdc & LcdcFlag.WIN_TILE_MAP > 0) gb.vram[0x1c00..0x2000] else gb.vram[0x1800..0x1c00];

    const bgp = gb.read(IoReg.BGP);
    const scx = gb.read(IoReg.SCX);
    const scy = gb.read(IoReg.SCY);
    const wx = gb.read(IoReg.WX);
    const obp0 = gb.read(IoReg.OBP0);
    const obp1 = gb.read(IoReg.OBP1);

    var colorId: usize = 0;

    if (lcdc & LcdcFlag.BG_WIN_ENABLE > 0) {
        const scrolledX = @as(usize, @intCast(@as(u8, @intCast(x)) +% scx));
        const scrolledY = @as(usize, @intCast(@as(u8, @intCast(y)) +% scy));
        const addrMode: TileDataAddressingMode = if (lcdc & LcdcFlag.TILE_DATA > 0) .unsigned else .signed;
        colorId = colorIdForBgWinAt(scrolledX, scrolledY, bgp, addrMode, bgTileData, bgTileMap);
    }

    if (lcdc & LcdcFlag.BG_WIN_ENABLE > 0 and lcdc & LcdcFlag.WIN_ENABLE > 0) {
        const wxInRange = wx >= 0 and wx <= 166;
        const wyInRange = wy >= 0 and wy <= 143;
        const xInRange = x + 7 >= wx and x + 7 <= 166;
        const yInRange = y >= wy and y <= 143;

        if (wxInRange and wyInRange and xInRange and yInRange) {
            const windowX = x + 7 - @as(usize, @intCast(wx));
            const addrMode: TileDataAddressingMode = if (lcdc & LcdcFlag.TILE_DATA > 0) .unsigned else .signed;
            colorId = colorIdForBgWinAt(windowX, windowY.*, bgp, addrMode, bgTileData, winTileMap);

            if (x == 159) {
                windowY.* += 1;
            }
        }
    }

    if (lcdc & LcdcFlag.OBJ_ENABLE > 0) {
        for (objAttrs) |obj| {
            const objXInRange = x + 8 >= obj.x and x < obj.x;
            if (!objXInRange) {
                continue;
            }

            const tileYBase = y + 16 - @as(usize, @intCast(obj.y));
            const tileXBase = x + 8 - @as(usize, @intCast(obj.x));
            const tileY = if (obj.flags & ObjFlag.Y_FLIP_ON > 0) (if (lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0) 15 - tileYBase else 7 - tileYBase) else tileYBase;
            const tileX = if (obj.flags & ObjFlag.X_FLIP_ON > 0) 7 - tileXBase else tileXBase;
            const tileNumber = if (lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0) obj.tileNumber & 0b1111_1110 else obj.tileNumber;
            const tileDataIndex = (tileNumber * 16) + (tileY * 2);
            const tile = bgTileData[tileDataIndex .. tileDataIndex + 2];
            const pixelMask = @as(u8, 1) << @as(u3, @truncate(7 - tileX));
            const highBit = (tile[1] & pixelMask) >> @as(u3, @truncate(7 - tileX));
            const lowBit = (tile[0] & pixelMask) >> @as(u3, @truncate(7 - tileX));
            const paletteIndex = 2 * highBit + lowBit;
            if (paletteIndex == 0) {
                // Transparent pixel.
                continue;
            }
            const paletteMask = @as(u8, 0b11) << @as(u3, @truncate(paletteIndex * 2));
            const objPalette = if (obj.flags & ObjFlag.PALETTE_1 > 0) obp1 else obp0;
            const priority = obj.flags & ObjFlag.PRIORITY_LOW > 0;
            if (priority and colorId != 0) {
                // BG/Window has drawing priority over this object.
                continue;
            }

            colorId = @as(usize, @intCast((objPalette & paletteMask) >> @as(u3, @truncate(paletteIndex * 2))));
        }
    }

    gb.vramMutex.unlock();

    return colorId;
}

fn colorIdForBgWinAt(x: usize, y: usize, palette: u8, addrMode: TileDataAddressingMode, tileData: []u8, tileMap: []u8) usize {
    // Figure out which tile is at (x, y).
    const currentTile = @divTrunc(y, 8) * 32 + @divTrunc(x, 8);
    const tileNumber = if (addrMode == .unsigned) @as(usize, @intCast(tileMap[currentTile])) else @as(usize, @intCast(tileMap[currentTile] +% 128));

    // Figure out which pixel of the tile is at (x, y), and look up the corresponding tile data.
    const tileX = x % 8;
    const tileY = y % 8;
    const tileDataIndex = (tileNumber * 16) + (tileY * 2);
    const tile = tileData[tileDataIndex .. tileDataIndex + 2];

    // Look up the 2 bits that define the the pixel at (tileX, tileY) of this tile.
    const pixelMask = @as(u8, 1) << @as(u3, @truncate(7 - tileX));
    const highBit = (tile[1] & pixelMask) >> @as(u3, @truncate(7 - tileX));
    const lowBit = (tile[0] & pixelMask) >> @as(u3, @truncate(7 - tileX));

    // Calculate the color ID by indexing into the palette.
    const paletteIndex = 2 * highBit + lowBit;
    const paletteMask = @as(u8, 0b11) << @as(u3, @truncate(paletteIndex * 2));
    const colorId = @as(usize, @intCast((palette & paletteMask) >> @as(u3, @truncate(paletteIndex * 2))));

    return colorId;
}
