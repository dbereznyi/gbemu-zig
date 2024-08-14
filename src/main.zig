const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy.zig").Gb;
const Button = @import("gameboy.zig").Button;
const Palette = @import("gameboy.zig").Ppu.Palette;
const stepCpu = @import("cpu/step.zig").stepCpu;
const stepPpu = @import("ppu.zig").stepPpu;
const stepDma = @import("dma.zig").stepDma;
const stepJoypad = @import("joypad.zig").stepJoypad;
const debugBreak = @import("debug.zig").debugBreak;

const SCALE = 2;

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
    var gb = try Gb.init(alloc, rom, Palette.GREEN);
    defer gb.deinit(alloc);

    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);

    if (false) {
        try gb.debug.breakpoints.append(0x0295);
    }

    //var gameboyThread = try std.Thread.spawn(.{}, runGameboy, .{
    //    &gb,
    //    pixels,
    //});
    //defer {
    //    if (gb.debug.isPaused()) {
    //        // If the debugger is blocking gameboyThread, it's safe to detach
    //        // and let the main thread exit.
    //        gameboyThread.detach();
    //    } else {
    //        // If gameboyThread is still running normally, we want to wait for
    //        // its current loop iteration to finish and exit on its own.
    //        // (This avoids some SEGFAULT errors occurring when CTRL+C quitting.)
    //        gameboyThread.join();
    //    }
    //}

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

        const start = try std.time.Instant.now();
        const lcdOnAtStartOfFrame = gb.isLcdOn();

        const CYCLES_UNTIL_VBLANK: usize = 16416;
        _ = try simulate(CYCLES_UNTIL_VBLANK, &gb);
        std.debug.assert(gb.ppu.mode == .vBlank);
        std.debug.assert(gb.isInVBlank());

        if (lcdOnAtStartOfFrame) {
            _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);
        }
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        const VBLANK_CYCLES: usize = 1140;
        _ = try simulate(VBLANK_CYCLES, &gb);
        std.debug.assert(gb.ppu.mode != .vBlank);
        std.debug.assert(!gb.isInVBlank());

        if (false and frames % 15 == 0) {
            std.debug.print("actual **** frameTime: {} ns = {} micros = {} ms\n", .{ gb.debug.frameTimeNs, gb.debug.frameTimeNs / 1000, gb.debug.frameTimeNs / 1000 / 1000 });
            const expected: u64 = (16416 + 1140) * 1000;
            std.debug.print("expected ** frameTime: {} ns = {} micros = {} ms\n", .{ expected, expected / 1000, expected / 1000 / 1000 });
        }

        const actualFrameTimeNs = (try std.time.Instant.now()).since(start);
        gb.debug.frameTimeNs = actualFrameTimeNs;
        const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + 1140;
        std.time.sleep(FRAME_CYCLES * 1000 -| actualFrameTimeNs);
        frames +%= 1;
    }
}

fn simulate(minCycles: usize, gb: *Gb) !usize {
    var cycles: usize = 0;
    while (cycles < minCycles) {
        try debugBreak(gb);

        const cpuCycles = stepCpu(gb);
        for (0..cpuCycles) |_| {
            stepJoypad(gb);
            stepPpu(gb);
            stepDma(gb);
        }

        cycles += cpuCycles;
    }
    return cycles -| minCycles;
}
