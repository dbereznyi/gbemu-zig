const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
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

    const myTile = [_]u8{ 0x3c, 0x7e, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x7e, 0x5e, 0x7e, 0x0a, 0x7c, 0x56, 0x38, 0x7c };
    for (myTile, 0..) |_, i| {
        bgTileData[2 + i] = myTile[i];
    }

    const bgTileMap = try alloc.alloc(u8, 128);
    defer alloc.free(bgTileMap);
    for (bgTileMap, 0..) |_, i| {
        bgTileMap[i] = 0;
    }

    bgTileMap[1] = 1;

    const bgTileDataStartAddr = 0x8000;
    for (bgTileData, 0..) |_, i| {
        gb.write(@truncate(bgTileDataStartAddr + i), bgTileData[i]);
    }

    const bgTileMapStartAddr = 0x9800;
    for (bgTileMap, 0..) |_, i| {
        gb.write(@truncate(bgTileMapStartAddr + i), bgTileMap[i]);
    }

    const LCD_ENABLE = 0b1000_0000;
    const BG_ENABLE = 0b0000_0001;
    gb.write(0xff40, LCD_ENABLE | BG_ENABLE);
}
