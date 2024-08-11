const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const LcdcFlag = @import("gameboy.zig").LcdcFlag;
const ObjFlag = @import("gameboy.zig").ObjFlag;
const Button = @import("gameboy.zig").Button;
const stepCpu = @import("cpu/step.zig").stepCpu;
const runPpu = @import("ppu.zig").runPpu;
const stepPpu = @import("ppu.zig").stepPpu;
const Ppu = @import("ppu.zig").Ppu;
const decodeInstrAt = @import("cpu/decode.zig").decodeInstrAt;
const debugBreak = @import("debug.zig").debugBreak;
const stepJoypad = @import("joypad.zig").stepJoypad;

const SCALE = 4;

var forceQuit = false;

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

    const pixels: []Pixel = try alloc.alloc(Pixel, 160 * 144);
    defer alloc.free(pixels);

    std.mem.copyForwards(Pixel, pixels, gb.screen);

    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(pixels), 160 * 3);

    if (false) {
        try initVramForTesting(&gb, alloc);
    }

    if (false) {
        try gb.debug.breakpoints.append(0x0060);
    }

    var gameboyThread = try std.Thread.spawn(.{}, runGameboy, .{
        &gb,
        pixels,
    });
    defer {
        if (gb.isDebugPaused()) {
            // If the debugger is blocking gameboyThread, it's safe to detach
            // and let the main thread exit.
            gameboyThread.detach();
        } else {
            // If gameboyThread is still running normally, we want to wait for
            // it's current loop iteration to finish and exit on its own.
            // (This avoids some SEGFAULT errors occurring when CTRL+C quitting.)
            gameboyThread.join();
        }
    }

    // In order to gracefully handle CTRL+C.
    std.posix.sigaction(std.c.SIG.INT, &std.posix.Sigaction{
        .handler = .{ .handler = struct {
            pub fn handler(_: c_int) callconv(.C) void {
                forceQuit = true;
            }
        }.handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null) catch {
        std.log.warn("could not register signal handler for SIG_INT\n", .{});
    };

    var frames: usize = 0;
    while (gb.isRunning()) {
        if (forceQuit) {
            gb.setIsRunning(false);
            return;
        }

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYUP => switch (event.key.keysym.sym) {
                    c.SDLK_a => gb.joypad.releaseButton(Button.START),
                    c.SDLK_s => gb.joypad.releaseButton(Button.SELECT),
                    c.SDLK_z => gb.joypad.releaseButton(Button.A),
                    c.SDLK_x => gb.joypad.releaseButton(Button.B),
                    c.SDLK_RIGHT => gb.joypad.releaseButton(Button.RIGHT),
                    c.SDLK_LEFT => gb.joypad.releaseButton(Button.LEFT),
                    c.SDLK_UP => gb.joypad.releaseButton(Button.UP),
                    c.SDLK_DOWN => gb.joypad.releaseButton(Button.DOWN),
                    else => {},
                },
                c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    c.SDLK_a => gb.joypad.pressButton(Button.START),
                    c.SDLK_s => gb.joypad.pressButton(Button.SELECT),
                    c.SDLK_z => gb.joypad.pressButton(Button.A),
                    c.SDLK_x => gb.joypad.pressButton(Button.B),
                    c.SDLK_RIGHT => gb.joypad.pressButton(Button.RIGHT),
                    c.SDLK_LEFT => gb.joypad.pressButton(Button.LEFT),
                    c.SDLK_UP => gb.joypad.pressButton(Button.UP),
                    c.SDLK_DOWN => gb.joypad.pressButton(Button.DOWN),
                    else => {},
                },
                c.SDL_QUIT => gb.setIsRunning(false),
                else => {},
            }
        }

        if (gb.isOnAndInVBlank()) {
            _ = c.SDL_UpdateTexture(texture, null, @ptrCast(pixels), 160 * 3);
        }

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
        frames +%= 1;
    }
}

fn runGameboy(gb: *Gb, pixels: []Pixel) !void {
    var ppu = Ppu.init();

    while (gb.isRunning()) {
        const lcdOnAtStartOfFrame = gb.read(IoReg.LCDC) & LcdcFlag.ON > 0;

        const CYCLES_UNTIL_VBLANK: usize = 16416;
        _ = try simulate(CYCLES_UNTIL_VBLANK, gb, &ppu);

        std.debug.assert(ppu.mode == .vBlank);
        std.debug.assert(gb.isInVBlank.load(.monotonic));

        if (lcdOnAtStartOfFrame) {
            std.mem.copyForwards(Pixel, pixels, gb.screen);
        }

        const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + 1140;
        std.time.sleep(FRAME_CYCLES * 1000);

        const VBLANK_CYCLES: usize = 1140;
        _ = try simulate(VBLANK_CYCLES, gb, &ppu);

        std.debug.assert(ppu.mode != .vBlank);
        std.debug.assert(!gb.isInVBlank.load(.monotonic));
    }
}

fn simulate(minCycles: usize, gb: *Gb, ppu: *Ppu) !usize {
    var cycles: usize = 0;
    while (cycles < minCycles) {
        try debugBreak(gb, ppu);

        const cpuCycles = stepCpu(gb);
        for (0..cpuCycles) |_| {
            stepJoypad(gb);
            ppu.step(gb);
        }

        cycles += cpuCycles;
    }
    return cycles;
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
