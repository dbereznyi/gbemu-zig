const std = @import("std");
const Pixel = @import("../../pixel.zig").Pixel;
const Gb = @import("../gameboy.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;
const Interrupt = @import("../gameboy.zig").Interrupt;
const LcdcFlag = @import("../gameboy.zig").LcdcFlag;
const ObjFlag = @import("../gameboy.zig").ObjFlag;
const StatFlag = @import("../gameboy.zig").StatFlag;
const Ppu = @import("ppu.zig").Ppu;

const LINE_DOTS: usize = 456;
const OAM_DOTS: usize = 80;
const DRAWING_DOTS: usize = 172;
const HBLANK_DOTS: usize = 204;
const VBLANK_DOTS: usize = 4560;

const DRAWING_START: usize = OAM_DOTS;
const HBLANK_START: usize = DRAWING_START + DRAWING_DOTS;
const VBLANK_START: usize = LINE_DOTS * 144;
const VBLANK_END: usize = VBLANK_START + VBLANK_DOTS;

const TileDataAddressingMode = enum {
    unsigned, // "$8000 method"
    signed, // "$8800 method"
};

// Advance the state of the PPU by 1 M-cycle (= 4 dots).
pub fn stepPpu(gb: *Gb) void {
    std.debug.assert(gb.ppu.dots % 4 == 0);
    std.debug.assert(gb.ppu.dots < VBLANK_END);

    switch (gb.ppu.mode) {
        .oam => {
            std.debug.assert(gb.ppu.dots % LINE_DOTS < DRAWING_START);
            std.debug.assert(gb.ppu.x == 0);
            std.debug.assert(gb.ppu.y < 144);
            std.debug.assert(gb.io_regs[IoReg.LY] < 144);
            std.debug.assert(!gb.isDrawing);

            if (gb.ppu.dots % LINE_DOTS == 0) {
                const stat = gb.io_regs[IoReg.STAT];
                const statInterruptsEnabled = gb.ie & Interrupt.STAT > 0;
                const intOnMode2 = stat & StatFlag.INT_MODE_2_ENABLE > 0;
                if (statInterruptsEnabled and intOnMode2) {
                    gb.requestInterrupt(Interrupt.STAT);
                }

                gb.setStatMode(StatFlag.MODE_2);

                if (gb.isLcdOn()) {
                    gb.scanningOam = true;
                    gb.ppu.obj_attrs = readObjectAttributesForLine(
                        gb.ppu.y,
                        &gb.ppu.obj_attrs_buf,
                        gb,
                    );
                } else {
                    gb.ppu.obj_attrs.len = 0;
                }
            } else if (gb.ppu.dots % LINE_DOTS == DRAWING_START - 4) {
                gb.scanningOam = false;
                gb.ppu.mode = .drawing;
            }
        },
        .drawing => {
            std.debug.assert(gb.ppu.dots % LINE_DOTS >= DRAWING_START);
            std.debug.assert(gb.ppu.dots % LINE_DOTS < HBLANK_START);
            std.debug.assert(gb.ppu.y < 144);
            std.debug.assert(gb.io_regs[IoReg.LY] < 144);
            std.debug.assert(!gb.scanningOam);

            if (gb.ppu.dots == DRAWING_START) {
                gb.ppu.windowY = 0;
                gb.ppu.wy = gb.io_regs[IoReg.WY];
            }

            if (gb.ppu.dots % LINE_DOTS == DRAWING_START) {
                gb.isDrawing = true;
                gb.setStatMode(StatFlag.MODE_3);
            } else if (gb.ppu.dots % LINE_DOTS >= DRAWING_START + 12) {
                for (gb.ppu.x..gb.ppu.x + 4) |x| {
                    const colorId = colorIdAt(
                        x,
                        gb.ppu.y,
                        gb,
                        gb.ppu.obj_attrs,
                        &gb.ppu.windowY,
                        gb.ppu.wy,
                    );
                    gb.screen[gb.ppu.y * 160 + x] = gb.ppu.palette.data()[colorId];
                }
                gb.ppu.x = (gb.ppu.x + 4) % 160;

                if (gb.ppu.dots % LINE_DOTS == HBLANK_START - 4) {
                    // TODO need to account for mode 3 varying in length
                    gb.ppu.x = 0;
                    gb.isDrawing = false;
                    gb.ppu.mode = .hBlank;
                }
            }
        },
        .hBlank => {
            std.debug.assert(gb.ppu.dots % LINE_DOTS >= HBLANK_START);
            std.debug.assert(gb.ppu.dots < VBLANK_START);
            std.debug.assert(gb.ppu.x == 0);
            std.debug.assert(gb.ppu.y < 144);
            std.debug.assert(gb.io_regs[IoReg.LY] < 144);
            std.debug.assert(!gb.scanningOam);
            std.debug.assert(!gb.isDrawing);

            if (gb.ppu.dots % LINE_DOTS == HBLANK_START) {
                const stat = gb.io_regs[IoReg.STAT];
                const statInterruptsEnabled = gb.ie & Interrupt.STAT > 0;
                const intOnMode0 = stat & StatFlag.INT_MODE_0_ENABLE > 0;

                gb.setStatMode(StatFlag.MODE_0);
                if (statInterruptsEnabled and intOnMode0) {
                    gb.requestInterrupt(Interrupt.STAT);
                }
            } else if (gb.ppu.dots % LINE_DOTS == LINE_DOTS - 4) {
                gb.ppu.y += 1;

                const stat = gb.io_regs[IoReg.STAT];
                const statInterruptsEnabled = gb.ie & Interrupt.STAT > 0;
                const intOnLycIncident = stat & StatFlag.INT_LYC_INCIDENT_ENABLE > 0;

                // TODO when is this actually supposed to trigger?
                gb.io_regs[IoReg.LY] = @truncate(gb.ppu.y);
                const lycIncident = gb.ppu.y == gb.io_regs[IoReg.LYC];
                gb.setStatLycIncident(lycIncident);
                if (statInterruptsEnabled and intOnLycIncident and lycIncident) {
                    gb.requestInterrupt(Interrupt.STAT);
                }

                if (gb.ppu.y < 144) {
                    gb.scanningOam = true;
                    gb.ppu.mode = .oam;
                } else {
                    gb.inVBlank.store(true, .monotonic);
                    gb.ppu.mode = .vBlank;
                }
            }
        },
        .vBlank => {
            std.debug.assert(gb.ppu.dots >= VBLANK_START);
            std.debug.assert(gb.ppu.dots < VBLANK_END);
            std.debug.assert(gb.ppu.y >= 144);
            std.debug.assert(gb.ppu.y < 154);
            std.debug.assert(gb.io_regs[IoReg.LY] >= 144);
            std.debug.assert(gb.io_regs[IoReg.LY] < 154);
            std.debug.assert(!gb.scanningOam);
            std.debug.assert(!gb.isDrawing);

            if (gb.ppu.dots == VBLANK_START) {
                const stat = gb.io_regs[IoReg.STAT];
                const vblankInterruptsEnabled = gb.ie & Interrupt.VBLANK > 0;
                const statInterruptsEnabled = gb.ie & Interrupt.STAT > 0;
                const intOnMode1 = stat & StatFlag.INT_MODE_1_ENABLE > 0;

                gb.setStatMode(StatFlag.MODE_1);
                if (statInterruptsEnabled and intOnMode1) {
                    gb.requestInterrupt(Interrupt.STAT);
                }
                if (vblankInterruptsEnabled) {
                    gb.requestInterrupt(Interrupt.VBLANK);
                }
            }

            if (gb.ppu.dots % LINE_DOTS == LINE_DOTS - 4) {
                // TODO do LYC incident interrupts occur in VBLANK?
                gb.ppu.y = (gb.ppu.y + 1) % 154;
                gb.io_regs[IoReg.LY] = @truncate(gb.ppu.y);
            }

            if (gb.ppu.dots == VBLANK_END - 4) {
                gb.inVBlank.store(false, .monotonic);
                gb.scanningOam = true;
                gb.ppu.mode = .oam;
            }
        },
    }

    gb.ppu.dots = (gb.ppu.dots + 4) % VBLANK_END;
}

fn readObjectAttributesForLine(y: usize, selected_objs_buf: *[10]Ppu.ObjectAttribute, gb: *Gb) []Ppu.ObjectAttribute {
    var obj_attrs: [40]Ppu.ObjectAttribute = undefined;
    var obj_attrs_index: usize = 0;
    var oam_index: usize = 0;
    while (oam_index < gb.oam.len) : ({
        oam_index += 4;
        obj_attrs_index += 1;
    }) {
        obj_attrs[obj_attrs_index].y = gb.oam[oam_index];
        obj_attrs[obj_attrs_index].x = gb.oam[oam_index + 1];
        obj_attrs[obj_attrs_index].tileNumber = gb.oam[oam_index + 2];
        obj_attrs[obj_attrs_index].flags = gb.oam[oam_index + 3];
        obj_attrs[obj_attrs_index].oamIndex = oam_index;
    }
    std.debug.assert(gb.oam.len <= 160);

    const lcdc = gb.io_regs[IoReg.LCDC];

    var selected_objs_count: usize = 0;
    for (obj_attrs) |obj| {
        const large_objects = lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0;
        const yLowerBound = obj.y -| 16;
        const yUpperBound = if (large_objects) obj.y else obj.y -% 8;

        if (!large_objects and obj.y <= 8) {
            continue;
        }

        if (y >= yLowerBound and y < yUpperBound) {
            const i = selected_objs_count;
            selected_objs_buf[i].y = obj.y;
            selected_objs_buf[i].x = obj.x;
            selected_objs_buf[i].tileNumber = obj.tileNumber;
            selected_objs_buf[i].flags = obj.flags;
            selected_objs_buf[i].oamIndex = obj.oamIndex;
            selected_objs_count += 1;
            if (selected_objs_count == 10) {
                break;
            }
        }
    }

    const selected_objs = selected_objs_buf[0..selected_objs_count];
    std.sort.block(Ppu.ObjectAttribute, selected_objs, {}, Ppu.ObjectAttribute.isLessThan);

    // TODO can probably skip this by just iterating over attributes in reverse when drawing
    std.mem.reverse(Ppu.ObjectAttribute, selected_objs);

    return selected_objs;
}

fn colorIdAt(x: usize, y: usize, gb: *Gb, obj_attrs: []const Ppu.ObjectAttribute, windowY: *usize, wy: u8) usize {
    const lcdc = gb.io_regs[IoReg.LCDC];
    if (lcdc & LcdcFlag.ON == 0) {
        return 0;
    }

    const obj_tile_data = gb.vram[0x0000..0x1000];
    const bgTileData = if (lcdc & LcdcFlag.TILE_DATA > 0) gb.vram[0x0000..0x1000] else gb.vram[0x0800..0x1800];
    const bgTileMap = if (lcdc & LcdcFlag.BG_TILE_MAP > 0) gb.vram[0x1c00..0x2000] else gb.vram[0x1800..0x1c00];
    const winTileMap = if (lcdc & LcdcFlag.WIN_TILE_MAP > 0) gb.vram[0x1c00..0x2000] else gb.vram[0x1800..0x1c00];

    const bgp = gb.io_regs[IoReg.BGP];
    const scx = gb.io_regs[IoReg.SCX];
    const scy = gb.io_regs[IoReg.SCY];
    const wx = gb.io_regs[IoReg.WX];
    const obp0 = gb.io_regs[IoReg.OBP0];
    const obp1 = gb.io_regs[IoReg.OBP1];

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
        for (obj_attrs) |obj| {
            const objXInRange = x + 8 >= obj.x and x < obj.x;
            if (!objXInRange) {
                continue;
            }
            const objYInRange = y + 16 >= obj.y and y < obj.y;
            if (!objYInRange) {
                continue;
            }

            const tileYBase = y + 16 - @as(usize, @intCast(obj.y));
            const tileXBase = x + 8 - @as(usize, @intCast(obj.x));
            const tileY = if (obj.flags & ObjFlag.Y_FLIP_ON > 0) (if (lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0) 15 - tileYBase else 7 - tileYBase) else tileYBase;
            const tileX = if (obj.flags & ObjFlag.X_FLIP_ON > 0) 7 - tileXBase else tileXBase;
            const tileNumber = if (lcdc & LcdcFlag.OBJ_SIZE_LARGE > 0) obj.tileNumber & 0b1111_1110 else obj.tileNumber;
            const tileDataIndex = (@as(usize, tileNumber) * 16) + (tileY * 2);
            const tile = obj_tile_data[tileDataIndex .. tileDataIndex + 2];
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

pub fn renderVramViewer(gb: *Gb, pixels: *[]Pixel) void {
    const tile_data = gb.vram[0x0000..0x1800];
    const palette = gb.io_regs[IoReg.BGP];

    for (pixels.*, 0..) |*pixel, i| {
        const y = @divTrunc(i, 16 * 8);
        const x = i % (16 * 8);

        const tile_number = @divTrunc(y, 8) * 16 + @divTrunc(x, 8);

        // Figure out which pixel of the tile is at (x, y), and look up the corresponding tile data.
        const tile_x = x % 8;
        const tile_y = y % 8;
        const tile_data_index = (tile_number * 16) + (tile_y * 2);
        const tile = tile_data[tile_data_index .. tile_data_index + 2];

        // Look up the 2 bits that define the the pixel at (tileX, tileY) of this tile.
        const pixel_mask = @as(u8, 1) << @as(u3, @truncate(7 - tile_x));
        const high_bit = (tile[1] & pixel_mask) >> @as(u3, @truncate(7 - tile_x));
        const low_bit = (tile[0] & pixel_mask) >> @as(u3, @truncate(7 - tile_x));

        // Calculate the color ID by indexing into the palette.
        const palette_index = 2 * high_bit + low_bit;
        const palette_mask = @as(u8, 0b11) << @as(u3, @truncate(palette_index * 2));
        const color_id = @as(usize, @intCast((palette & palette_mask) >> @as(u3, @truncate(palette_index * 2))));

        pixel.* = gb.ppu.palette.data()[color_id];
    }
}
