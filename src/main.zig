const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const stepCpu = @import("cpu.zig").stepCpu;

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

    const screen = c.SDL_CreateWindow("gameboy", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 160 * SCALE, 144 * SCALE, c.SDL_WINDOW_OPENGL) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGB24, c.SDL_TEXTUREACCESS_STREAMING, 160, 144) orelse {
        c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    const pixels = try alloc.alloc(Pixel, 160 * 144);
    defer alloc.free(pixels);
    for (pixels) |*pixel| {
        pixel.*.r = 0xff;
        pixel.*.g = 0xff;
        pixel.*.b = 0xff;
    }

    var rwl = std.Thread.RwLock{};

    var gameboyThread = try std.Thread.spawn(.{}, runGameboy, .{ pixels, &rwl, alloc });
    gameboyThread.detach();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        rwl.lockShared();
        _ = c.SDL_UpdateTexture(texture, null, @ptrCast(pixels), 160 * 3);
        rwl.unlockShared();

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

fn runGameboy(pixels: []Pixel, rwl: *std.Thread.RwLock, alloc: std.mem.Allocator) !void {
    const rom = try std.fs.cwd().readFileAlloc(alloc, "roms/hello-world.gb", 1024 * 1024 * 1024);
    var gb = try Gb.init(alloc, rom);

    const cycles = stepCpu(&gb);
    std.debug.print("cycles = {}\n", .{cycles});

    var i: u8 = 0;
    while (true) {
        rwl.lock();
        for (pixels) |*pixel| {
            pixel.*.r = i;
            pixel.*.g = i;
            pixel.*.b = i;
        }
        rwl.unlock();

        i +%= 1;

        std.time.sleep(16666666); // ~1/60 sec
    }
}
