const std = @import("std");
const Pixel = @import("../../pixel.zig").Pixel;
const format = std.fmt.format;

pub const Ppu = struct {
    pub const Mode = enum {
        oam,
        drawing,
        hBlank,
        vBlank,
    };

    pub const ObjectAttribute = struct {
        y: u8,
        x: u8,
        tileNumber: u8,
        flags: u8,
        oamIndex: usize, // used for sorting

        pub fn isLessThan(_: void, lhs: ObjectAttribute, rhs: ObjectAttribute) bool {
            if (lhs.x != rhs.x) {
                return lhs.x < rhs.x;
            }

            return lhs.oamIndex < rhs.oamIndex;
        }
    };

    pub const Palette = .{
        // A greyscale palette. Seems to be used often by emulators/later consoles.
        .GREY = [4]Pixel{
            .{ .r = 255, .g = 255, .b = 255 },
            .{ .r = 127, .g = 127, .b = 127 },
            .{ .r = 63, .g = 63, .b = 63 },
            .{ .r = 0, .g = 0, .b = 0 },
        },
        // A green-ish palette. Closer in feel to original DMG graphics.
        .GREEN = [4]Pixel{
            .{ .r = 239, .g = 255, .b = 222 },
            .{ .r = 173, .g = 215, .b = 148 },
            .{ .r = 82, .g = 146, .b = 115 },
            .{ .r = 24, .g = 52, .b = 66 },
        },
    };

    dots: usize,
    palette: [4]Pixel,
    y: usize,
    x: usize,
    wy: u8,
    windowY: usize,
    mode: Ppu.Mode,
    objAttrsLineBuf: [10]Ppu.ObjectAttribute,
    objAttrsLine: []Ppu.ObjectAttribute,

    pub fn init(palette: [4]Pixel) Ppu {
        return Ppu{
            .dots = 0,
            .palette = palette,
            .y = 0,
            .x = 0,
            .wy = 0,
            .windowY = 0,
            .mode = .oam,
            .objAttrsLineBuf = undefined,
            .objAttrsLine = undefined,
        };
    }

    pub fn printState(ppu: *const Ppu, writer: anytype) !void {
        try format(writer, "dots={d:>6} y={d:0>3} x={d:0>3} wy={d:0>3} windowY={d:0>3} mode={s}\n", .{
            ppu.dots,
            ppu.y,
            ppu.x,
            ppu.wy,
            ppu.windowY,
            switch (ppu.mode) {
                .oam => "oam",
                .drawing => "drawing",
                .hBlank => "hBlank",
                .vBlank => "vBlank",
            },
        });
    }
};
