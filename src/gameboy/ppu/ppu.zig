const std = @import("std");
const Pixel = @import("../../pixel.zig").Pixel;
const format = std.fmt.format;
const constants = @import("../../constants.zig");

pub const Ppu = struct {
    const Self = @This();

    pub const VblankCallback = struct {
        context: *anyopaque,
        callback: *const fn (context: *anyopaque, screen: []Pixel) void,
    };

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

    pub const Palette = enum {
        /// A greyscale palette. Seems to be used often by emulators/later consoles.
        grey,
        /// A green-ish palette. Closer in feel to original DMG graphics.
        green,

        pub fn data(self: @This()) [4]Pixel {
            return switch (self) {
                .grey => [4]Pixel{
                    .{ .r = 255, .g = 255, .b = 255 },
                    .{ .r = 176, .g = 176, .b = 176 },
                    .{ .r = 63, .g = 63, .b = 63 },
                    .{ .r = 0, .g = 0, .b = 0 },
                },
                .green => [4]Pixel{
                    .{ .r = 239, .g = 255, .b = 222 },
                    .{ .r = 173, .g = 215, .b = 148 },
                    .{ .r = 82, .g = 146, .b = 115 },
                    .{ .r = 24, .g = 52, .b = 66 },
                },
            };
        }

        pub fn toStr(self: @This()) []const u8 {
            return switch (self) {
                .grey => "grey",
                .green => "green",
            };
        }
    };

    dots: usize,
    palette: Palette,
    y: usize,
    x: usize,
    wy: u8,
    windowY: usize,
    mode: Ppu.Mode,
    obj_attrs_buf: [10]Ppu.ObjectAttribute,
    obj_attrs: []Ppu.ObjectAttribute,

    scanning_oam: bool,
    drawing: bool,

    screen: []Pixel,
    vblank_callback: ?VblankCallback,

    cycles_odd: usize,

    pub fn init(alloc: std.mem.Allocator) !Ppu {
        const palette = Palette.green;

        const screen: []Pixel = try alloc.alloc(Pixel, constants.GB.SCREEN_WIDTH * constants.GB.SCREEN_HEIGHT);
        for (screen) |*pixel| {
            pixel.* = palette.data()[0];
        }

        return Ppu{
            .dots = 0,
            .palette = palette,
            .y = 0,
            .x = 0,
            .wy = 0,
            .windowY = 0,
            .mode = .oam,
            .obj_attrs_buf = undefined,
            .obj_attrs = undefined,
            .scanning_oam = false,
            .drawing = false,
            .screen = screen,
            .vblank_callback = null,
            .cycles_odd = 0,
        };
    }

    pub fn deinit(self: *const Self, alloc: std.mem.Allocator) void {
        alloc.free(self.screen);
    }

    pub fn reset(self: *Self) void {
        self.dots = 0;
        self.y = 0;
        self.x = 0;
        self.wy = 0;
        self.windowY = 0;
        self.mode = .oam;
        self.obj_attrs.len = 0;
        self.scanning_oam = false;
        self.drawing = false;
        self.cycles_odd = 0;
        @memset(self.screen, self.palette.data()[0]);
    }

    pub fn setVblankCallback(self: *Self, vblank_callback: VblankCallback) void {
        self.vblank_callback = vblank_callback;
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
        try format(writer, "Cycles until next frame: {}\n", .{70224 - ppu.dots});
    }
};
