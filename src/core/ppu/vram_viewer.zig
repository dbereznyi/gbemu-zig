const std = @import("std");
const Pixel = @import("./pixel.zig").Pixel;
const Gb = @import("../root.zig").Gb;
const IoReg = @import("../gameboy.zig").IoReg;

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
