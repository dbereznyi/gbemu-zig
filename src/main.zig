const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const LcdcFlag = @import("gameboy.zig").LcdcFlag;
const ObjFlag = @import("gameboy.zig").ObjFlag;
const runCpu = @import("cpu/run.zig").runCpu;
const stepCpu = @import("cpu/run.zig").stepCpu;
const runPpu = @import("ppu.zig").runPpu;
const stepPpu = @import("ppu.zig").stepPpu;
const Ppu = @import("ppu.zig").Ppu;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;

const SCALE = 4;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try std.io.getStdErr().writer().print("Usage: {s} <path to ROM file>\n", .{args[0]});
        std.process.exit(1);
    }

    const romFilepath = args[1];

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("gameboy", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 160 * SCALE, 144 * SCALE, c.SDL_WINDOW_OPENGL) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGB24, c.SDL_TEXTUREACCESS_STREAMING, 160, 144) orelse {
        c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    const rom = try std.fs.cwd().readFileAlloc(alloc, romFilepath, 1024 * 1024 * 1024);
    var gb = try Gb.init(alloc, rom);
    defer gb.deinit(alloc);

    var pixels: []Pixel = try alloc.alloc(Pixel, 160 * 144);
    for (pixels, 0..) |_, i| {
        pixels[i] = .{ .r = 0, .g = 0, .b = 0 };
    }
    //const pixels1: []u8 = try alloc.alloc(u8, 160*144*3);
    //const pixels2: []u8 = try alloc.alloc(u8, 160*144*3);
    //var currentPixels: *[]u8 = pixels1;
    //var previousPixels: *[]u8 = pixels2;

    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(pixels), 160 * 3);

    if (false) {
        try initVramForTesting(&gb, alloc);
    }

    if (false) {
        try gb.debug.breakpoints.append(0x0100);
    }

    var quit = std.atomic.Value(bool).init(false);

    var gameboyThread = try std.Thread.spawn(.{}, runGameboy, .{
        &gb,
        &quit,
        pixels,
    });
    defer gameboyThread.join();

    while (!quit.load(.monotonic)) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYUP => {
                    if (event.key.keysym.sym == c.SDLK_l) {
                        gb.write(IoReg.LCDC, gb.read(IoReg.LCDC) ^ LcdcFlag.ON);
                    }
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_RIGHT => {
                            gb.write(IoReg.SCX, gb.read(IoReg.SCX) +% 1);
                        },
                        c.SDLK_LEFT => {
                            gb.write(IoReg.SCX, gb.read(IoReg.SCX) -% 1);
                        },
                        c.SDLK_UP => {
                            gb.write(IoReg.SCY, gb.read(IoReg.SCY) +% 1);
                        },
                        c.SDLK_DOWN => {
                            gb.write(IoReg.SCY, gb.read(IoReg.SCY) -% 1);
                        },
                        else => {},
                    }
                },
                c.SDL_QUIT => {
                    quit.store(true, .monotonic);
                },
                else => {},
            }
        }

        if (gb.isOnAndInVBlank()) {
            //std.debug.print("updating texture\n", .{});
            // try updateScreen(texture, gb.screen, texturePixels, &texturePitch);
            _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);
        }

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

fn updateScreen(texture: *c.SDL_Texture, screen: []Pixel, pixels: []u8, pitch: *c_int) !void {
    var rawPixels: *anyopaque = pixels.ptr;
    if (c.SDL_LockTexture(texture, null, @ptrCast(&rawPixels), @ptrCast(pitch)) != 0) {
        c.SDL_Log("Failed to lock texture: %s", c.SDL_GetError());
        return error.SDLRuntimeError;
    }
    defer c.SDL_UnlockTexture(texture);

    for (0..144) |y| {
        for (0..160) |x| {
            const pitchUsize = @as(usize, @intCast(pitch.*));
            const pixelsOffset = y * pitchUsize + 3 * x;
            const screenOffset = 160 * y + x;
            const pixel = screen[screenOffset];

            //std.debug.print("screenOffset={} (r={d:0>3} g={d:0>3} b={d:0>3})\n", .{ screenOffset, pixel.r, pixel.g, pixel.b });

            pixels[pixelsOffset] = pixel.r;
            pixels[pixelsOffset + 1] = pixel.g;
            pixels[pixelsOffset + 2] = pixel.b;
        }
    }
}

fn runGameboy(gb: *Gb, quit: *std.atomic.Value(bool), pixels: []Pixel) !void {
    var ppu = Ppu.init();

    while (!quit.load(.monotonic)) {
        const CYCLES_UNTIL_VBLANK: usize = 16416;
        var currentCycles: usize = 0;
        while (currentCycles < CYCLES_UNTIL_VBLANK) {
            if (true) {
                try printDebugState(gb, &ppu);
            }

            const cpuCycles = stepCpu(gb);
            for (0..cpuCycles) |_| {
                ppu.step(gb);
            }

            currentCycles += cpuCycles;
        }

        for (gb.screen, 0..) |_, i| {
            pixels[i].r = gb.screen[i].r;
            pixels[i].g = gb.screen[i].g;
            pixels[i].b = gb.screen[i].b;
        }

        std.debug.assert(ppu.mode == .vBlank);
        std.debug.assert(gb.isInVBlank.load(.monotonic));

        if (false) {
            try printDebugState(gb, &ppu);

            std.debug.print("> ", .{});

            var inputBuf: [64]u8 = undefined;
            const len = try std.io.getStdIn().read(&inputBuf);
            if (len > 0 and inputBuf[0] == 'q') {
                quit.store(true, .monotonic);
            }
        }

        const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + 1140;
        std.time.sleep(FRAME_CYCLES * 1000);

        while (ppu.mode != .oam) {
            if (false) {
                try printDebugState(gb, &ppu);
            }

            const cpuCycles = stepCpu(gb);
            for (0..cpuCycles) |_| {
                ppu.step(gb);
            }

            currentCycles += cpuCycles;
        }
    }
}

fn printDebugState(gb: *Gb, ppu: *Ppu) !void {
    if (ppu.mode != .drawing) {
        return;
    }
    if (false) {
        ppu.printState(gb);
    }
    if (false) {
        var instrStrBuf: [64]u8 = undefined;

        const instr = decodeInstrAt(gb.pc, gb);
        const instrStr = try instr.toStr(&instrStrBuf);

        std.debug.print("${x:0>4}: {s}\n", .{
            gb.pc,
            instrStr,
        });
    }
}

fn initVramForTesting(gb: *Gb, alloc: std.mem.Allocator) !void {
    const bgTileData = try alloc.alloc(u8, 16 * 128);
    defer alloc.free(bgTileData);
    for (bgTileData, 0..) |_, i| {
        bgTileData[i] = 0;
    }

    const tileData = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x7e, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7e, 0x5e, 0x7e, 0x0a, 0x7c, 0x56, 0x38, 0x7c, 0xff, 0x0, 0x7e, 0xff, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xa5, 0x8b, 0xc9, 0x97, 0x7e, 0xff, 0x7c, 0x7c, 0x00, 0xc6, 0xc6, 0x00, 0x00, 0xfe, 0xc6, 0xc6, 0x00, 0xc6, 0xc6, 0x00, 0x00, 0x00 };
    for (tileData, 0..) |_, i| {
        bgTileData[i] = tileData[i];
    }

    const lcdc = LcdcFlag.ON | LcdcFlag.WIN_TILE_MAP | LcdcFlag.WIN_ENABLE | LcdcFlag.OBJ_SIZE_LARGE | LcdcFlag.OBJ_ENABLE | LcdcFlag.BG_WIN_ENABLE;

    const tileIndexStart = if (lcdc & LcdcFlag.TILE_DATA > 0) 0 else 128;

    const bgTileMap = try alloc.alloc(u8, 32 * 32);
    defer alloc.free(bgTileMap);
    for (bgTileMap, 0..) |_, i| {
        bgTileMap[i] = tileIndexStart;
    }

    bgTileMap[1] = tileIndexStart + 1;

    const winTileMap = try alloc.alloc(u8, 32 * 32);
    defer alloc.free(winTileMap);
    for (winTileMap, 0..) |_, i| {
        winTileMap[i] = tileIndexStart + 1;
    }

    const objAttrData = [_]u8{ 16, 37, 2, ObjFlag.PRIORITY_NORMAL | ObjFlag.Y_FLIP_OFF | ObjFlag.X_FLIP_OFF | ObjFlag.PALETTE_0 };
    for (objAttrData, 0..) |_, i| {
        gb.write(0xfe00 + @as(u16, @truncate(i)), objAttrData[i]);
    }

    const bgTileDataStartAddr = if (lcdc & LcdcFlag.TILE_DATA > 0) 0x8000 else 0x8800;
    for (bgTileData, 0..) |_, i| {
        gb.write(@truncate(bgTileDataStartAddr + i), bgTileData[i]);
    }

    const bgTileMapStartAddr = if (lcdc & LcdcFlag.BG_TILE_MAP > 0) 0x9c00 else 0x9800;
    for (bgTileMap, 0..) |_, i| {
        gb.write(@truncate(bgTileMapStartAddr + i), bgTileMap[i]);
    }

    const winTileMapStartAddr = if (lcdc & LcdcFlag.WIN_TILE_MAP > 0) 0x9c00 else 0x9800;
    for (winTileMap, 0..) |_, i| {
        gb.write(@truncate(winTileMapStartAddr + i), winTileMap[i]);
    }

    for (bgTileDataStartAddr..bgTileDataStartAddr + 16 * 128) |i| {
        const val = gb.read(@truncate(i));
        std.debug.print("{x:0>2} ", .{val});
        if ((i + 1) % 16 == 0) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\nbgTileMap:\n", .{});

    for (bgTileMapStartAddr..bgTileMapStartAddr + 32 * 32) |i| {
        const val = gb.read(@truncate(i));
        std.debug.print("{d:1} ", .{val - tileIndexStart});
        if ((i + 1) % 32 == 0) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n\nwinTileMap:\n", .{});

    for (winTileMapStartAddr..winTileMapStartAddr + 32 * 32) |i| {
        const val = gb.read(@truncate(i));
        std.debug.print("{d:1} ", .{val - tileIndexStart});
        if ((i + 1) % 32 == 0) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n", .{});

    gb.write(IoReg.LCDC, lcdc);
    gb.write(IoReg.BGP, 0b11_10_01_00);
    gb.write(IoReg.OBP0, 0b11_10_01_00);
    gb.write(IoReg.OBP1, 0b00_01_10_11);
    gb.write(IoReg.WX, 7);
    gb.write(IoReg.WY, 8);
}
