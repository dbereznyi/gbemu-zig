const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const IoReg = @import("gameboy.zig").IoReg;
const LcdcFlag = @import("gameboy.zig").LcdcFlag;
const stepCpu = @import("cpu.zig").stepCpu;
const runPpu = @import("ppu.zig").runPpu;
const AtomicOrder = std.builtin.AtomicOrder;

const SCALE = 4;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

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

    const rom = try std.fs.cwd().readFileAlloc(alloc, "roms/hello-world.gb", 1024 * 1024 * 1024);
    var gb = try Gb.init(alloc, rom);
    defer gb.deinit(alloc);

    try initVramForTesting(&gb, alloc);

    const screen: []Pixel = try alloc.alloc(Pixel, 160 * 144);
    defer alloc.free(screen);
    for (screen) |*pixel| {
        pixel.*.r = 0;
        pixel.*.g = 0;
        pixel.*.b = 0;
    }
    var screenRwl = std.Thread.RwLock{};

    var quit = std.atomic.Value(bool).init(false);

    var cpuThread = try std.Thread.spawn(.{}, runCpu, .{&gb});
    defer cpuThread.join();

    var ppuThread = try std.Thread.spawn(.{}, runPpu, .{ &gb, &screenRwl, screen, &quit });
    defer ppuThread.join();

    while (!quit.load(AtomicOrder.monotonic)) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYUP => {
                    if (event.key.keysym.sym == c.SDLK_l) {
                        gb.write(IoReg.LCDC, gb.read(IoReg.LCDC) ^ LcdcFlag.ON);
                    }
                },
                c.SDL_QUIT => {
                    quit.store(true, AtomicOrder.monotonic);
                },
                else => {},
            }
        }

        screenRwl.lockShared();
        _ = c.SDL_UpdateTexture(texture, null, @ptrCast(screen), 160 * 3);
        screenRwl.unlockShared();

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

fn runCpu(gb: *Gb) void {
    const cycles = stepCpu(gb);
    std.debug.print("cycles = {}\n", .{cycles});

    // var i: u8 = 0;
    // while (true) {
    //     // TODO
    //     // stepCpu(...)
    //     // stepPpu(...)

    //     screenRwl.lock();
    //     for (screen) |*pixel| {
    //         pixel.*.r = i;
    //         pixel.*.g = i;
    //         pixel.*.b = i;
    //     }
    //     screenRwl.unlock();

    //     i +%= 1;

    //     std.time.sleep(16666666); // ~1/60 sec
    // }
}

fn initVramForTesting(gb: *Gb, alloc: std.mem.Allocator) !void {
    const bgTileData = try alloc.alloc(u8, 16 * 128);
    defer alloc.free(bgTileData);
    for (bgTileData, 0..) |_, i| {
        bgTileData[i] = 0;
    }

    const tileData = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x7e, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7e, 0x5e, 0x7e, 0x0a, 0x7c, 0x56, 0x38, 0x7c };
    for (tileData, 0..) |_, i| {
        bgTileData[i] = tileData[i];
    }

    const lcdc = LcdcFlag.ON | LcdcFlag.WIN_TILE_MAP | LcdcFlag.WIN_ENABLE | LcdcFlag.BG_WIN_ENABLE;

    const tileIndexStart = if (lcdc & LcdcFlag.TILE_DATA > 0) 0 else 128;

    const bgTileMap = try alloc.alloc(u8, 32 * 32);
    defer alloc.free(bgTileMap);
    for (bgTileMap, 0..) |_, i| {
        bgTileMap[i] = tileIndexStart;
    }

    bgTileMap[1] = tileIndexStart + 1;

    const winTileMap = try alloc.alloc(u8, 32 * 32);
    defer alloc.free(bgTileMap);
    for (winTileMap, 0..) |_, i| {
        winTileMap[i] = if (i % 2 == 1 and i % 8 == 1) tileIndexStart else tileIndexStart + 1;
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
        std.debug.print("{x} ", .{val});
        if ((i + 1) % 16 == 0) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\nbgTileMap:\n", .{});

    for (bgTileMapStartAddr..bgTileMapStartAddr + 128) |i| {
        const val = gb.read(@truncate(i));
        std.debug.print("{} ", .{val});
    }
    std.debug.print("\n\nwinTileMap:\n", .{});

    for (winTileMapStartAddr..winTileMapStartAddr + 128) |i| {
        const val = gb.read(@truncate(i));
        std.debug.print("{} ", .{val});
    }
    std.debug.print("\n", .{});

    gb.write(IoReg.LCDC, lcdc);
    gb.write(IoReg.BGP, 0b11_10_01_00);
    gb.write(IoReg.WX, 7);
    gb.write(IoReg.WY, 8);
}
