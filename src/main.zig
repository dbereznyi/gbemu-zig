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
const stepTimer = @import("timer.zig").stepTimer;
const shouldDebugBreak = @import("debug/shouldDebugBreak.zig").shouldDebugBreak;
const runDebugger = @import("debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("debug/executeCmd.zig").executeCmd;
const renderVramViewer = @import("ppu.zig").renderVramViewer;

const SCALE = 3;

const CYCLES_UNTIL_VBLANK: usize = 16416;
const VBLANK_CYCLES: usize = 1140;
const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + VBLANK_CYCLES;

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

    // Main window

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

    // VRAM viewer window

    const VRAM_WINDOW_WIDTH = 16 * 8;
    const VRAM_WINDOW_HEIGHT = 3 * 8 * 8;

    const vram_window = c.SDL_CreateWindow("vram viewer", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, VRAM_WINDOW_WIDTH * SCALE, VRAM_WINDOW_HEIGHT * SCALE, c.SDL_WINDOW_OPENGL) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const vram_renderer = c.SDL_CreateRenderer(vram_window, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const vram_texture = c.SDL_CreateTexture(vram_renderer, c.SDL_PIXELFORMAT_RGB24, c.SDL_TEXTUREACCESS_STREAMING, VRAM_WINDOW_WIDTH, VRAM_WINDOW_HEIGHT) orelse {
        c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    var vram_pixels = try alloc.alloc(Pixel, VRAM_WINDOW_HEIGHT * VRAM_WINDOW_WIDTH);
    defer alloc.free(vram_pixels);

    // ---

    const rom = try std.fs.cwd().readFileAlloc(alloc, romFilepath, 1024 * 1024 * 1024);
    var gb = try Gb.init(alloc, rom, Palette.GREEN);
    defer gb.deinit(alloc);

    const debuggerThread = try std.Thread.spawn(.{}, runDebugger, .{&gb});
    debuggerThread.detach();

    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);

    if (true) {
        try gb.debug.breakpoints.append(.{ .bank = 16, .addr = 0x7074 });
        gb.debug.stackBase = 0xdfff;
    }

    var frames: usize = 0;
    while (gb.isRunning()) {
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
                c.SDL_WINDOWEVENT => {
                    if (event.window.event == c.SDL_WINDOWEVENT_CLOSE) {
                        if (event.window.windowID == c.SDL_GetWindowID(vram_window)) {
                            c.SDL_HideWindow(vram_window);
                        } else if (event.window.windowID == c.SDL_GetWindowID(window)) {
                            gb.setIsRunning(false);
                        }
                    }
                },
                c.SDL_QUIT => gb.setIsRunning(false),
                else => {},
            }
        }

        const start = try std.time.Instant.now();
        const lcdOnAtStartOfFrame = gb.isLcdOn();

        try handleDebugCmd(&gb);

        if (!gb.debug.isPaused()) {
            _ = try simulate(CYCLES_UNTIL_VBLANK, &gb);
        }

        if (lcdOnAtStartOfFrame) {
            _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);
        }
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, texture, null, null);
        c.SDL_RenderPresent(renderer);

        renderVramViewer(&gb, &vram_pixels);
        _ = c.SDL_UpdateTexture(vram_texture, null, @ptrCast(vram_pixels), VRAM_WINDOW_WIDTH * 3);
        _ = c.SDL_RenderClear(vram_renderer);
        _ = c.SDL_RenderCopy(vram_renderer, vram_texture, null, null);
        c.SDL_RenderPresent(vram_renderer);

        if (!gb.debug.isPaused()) {
            _ = try simulate(VBLANK_CYCLES, &gb);
        }

        if (false and frames % 15 == 0) {
            std.debug.print("actual **** frameTime: {} ns = {} micros = {} ms\n", .{ gb.debug.frameTimeNs, gb.debug.frameTimeNs / 1000, gb.debug.frameTimeNs / 1000 / 1000 });
            const expected: u64 = (FRAME_CYCLES) * 1000;
            std.debug.print("expected ** frameTime: {} ns = {} micros = {} ms\n", .{ expected, expected / 1000, expected / 1000 / 1000 });
        }

        const actualFrameTimeNs = (try std.time.Instant.now()).since(start);
        gb.debug.frameTimeNs = actualFrameTimeNs;
        std.time.sleep(FRAME_CYCLES * 1000 -| actualFrameTimeNs);
        frames +%= 1;
    }
}

fn simulate(minCycles: usize, gb: *Gb) !usize {
    var cycles: usize = 0;
    while (cycles < minCycles) {
        try handleDebugCmd(gb);
        if (shouldDebugBreak(gb)) {
            gb.debug.stdOutMutex.lock();
            std.debug.print("\n", .{});
            try gb.printCurrentAndNextInstruction();
            std.debug.print("\n> ", .{});
            gb.debug.stdOutMutex.unlock();

            gb.debug.setPaused(true);
            gb.debug.stepModeEnabled = true;
            return cycles;
        }

        const cpuCycles = stepCpu(gb);
        for (0..cpuCycles) |_| {
            stepJoypad(gb);
            stepPpu(gb);
            stepDma(gb);
            stepTimer(gb);
        }

        cycles += cpuCycles;
    }
    return cycles -| minCycles;
}

fn handleDebugCmd(gb: *Gb) !void {
    const debugCmd = gb.debug.receiveCommand() orelse return;
    try executeDebugCmd(debugCmd, gb);
    gb.debug.acknowledgeCommand();
}
