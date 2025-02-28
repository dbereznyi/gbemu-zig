const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy/gameboy.zig").Gb;
const stepGameboy = @import("gameboy/step.zig").stepGameboy;
const Button = @import("gameboy/joypad/joypad.zig").Joypad.Button;
const Palette = @import("gameboy/ppu/ppu.zig").Ppu.Palette;
const runDebugger = @import("gameboy/debug/runDebugger.zig").runDebugger;
const executeDebugCmd = @import("gameboy/debug/executeCmd.zig").executeCmd;
const renderVramViewer = @import("gameboy/ppu/step.zig").renderVramViewer;

const SCALE = 3;

const CYCLES_UNTIL_VBLANK: usize = 16416;
const VBLANK_CYCLES: usize = 1140;
const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + VBLANK_CYCLES;

const SAMPLE_RATE: u32 = 44100;
const NUM_CHANNELS: u32 = 2;
const BUFFER_SIZE: u32 = 4096 * NUM_CHANNELS;

fn freq(hz: comptime_float) f32 {
    return @as(f32, @floatFromInt(SAMPLE_RATE)) / hz;
}

const A4_FREQ: f32 = freq(440.0);
const A5_FREQ: f32 = freq(880.0);

const Oscillator = struct {
    current_step: f32,
    step_size: f32,
    volume: f32,

    pub fn init(rate: f32, volume: f32) Oscillator {
        return .{
            .current_step = 0.0,
            .step_size = (2 * std.math.pi) / rate,
            .volume = volume,
        };
    }

    pub fn next(self: *Oscillator) f32 {
        self.current_step += self.step_size;
        return std.math.sin(self.current_step) * self.volume;
    }
};

const Triangle = struct {
    current_step: f32,
    step_size: f32,
    volume: f32,

    const Self = @This();

    pub fn init(rate: f32, volume: f32) Self {
        return .{
            .current_step = 0.0,
            .step_size = 1 / rate,
            .volume = volume,
        };
    }

    pub fn next(self: *Self) f32 {
        self.current_step += std.math.wrap(self.step_size, 1);
        const frac = std.math.modf(self.current_step).fpart;
        return frac - 0.5 * self.volume;
    }
};

const Square = struct {
    current_step: f32,
    step_size: f32,
    volume: f32,

    const Self = @This();

    pub fn init(rate: f32, volume: f32) Self {
        return .{
            .current_step = 0.0,
            .step_size = 1 / rate,
            .volume = volume,
        };
    }

    pub fn next(self: *Self) f32 {
        self.current_step += std.math.wrap(self.step_size, 1);
        const frac = std.math.modf(self.current_step).fpart;
        return std.math.sign(frac - 0.5) * self.volume;
    }
};

const Audio = struct {
    oscillator: Oscillator,
    triangle: Triangle,
    square: Square,
};

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

    const rom_filepath = args[1];
    const dirname = std.fs.path.dirname(rom_filepath) orelse "";
    const save_data_filepath = try std.fmt.allocPrint(
        alloc,
        "{s}{c}{s}.sav",
        .{ dirname, std.fs.path.sep, std.fs.path.stem(rom_filepath) },
    );
    defer alloc.free(save_data_filepath);

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    // Audio

    var audio_spec = c.SDL_AudioSpec{
        .freq = SAMPLE_RATE,
        .format = c.AUDIO_F32,
        .channels = NUM_CHANNELS,
        .samples = BUFFER_SIZE,
        .size = undefined,
        .silence = undefined,
        //.callback = audioCallback,
        //.userdata = @ptrCast(gb.apu.samples_front),
        .callback = null,
        .userdata = undefined,
    };

    //var audio = Audio{
    //    .oscillator = Oscillator.init(A4_FREQ, 0.8),
    //    .triangle = Triangle.init(freq(100), 0.8),
    //    .square = Square.init(freq(50), 0.5),
    //};
    //audio_spec.userdata = @ptrCast(&audio);

    const audio_device = c.SDL_OpenAudioDevice(null, 0, &audio_spec, null, 0);
    if (audio_device < 0) {
        c.SDL_Log("Unable to open audio device: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_CloseAudioDevice(audio_device);

    // Main window

    const window = c.SDL_CreateWindow(
        "gameboy",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        160 * SCALE,
        144 * SCALE,
        c.SDL_WINDOW_OPENGL,
    ) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGB24,
        c.SDL_TEXTUREACCESS_STREAMING,
        160,
        144,
    ) orelse {
        c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    // VRAM viewer window

    const VRAM_WINDOW_WIDTH = 16 * 8;
    const VRAM_WINDOW_HEIGHT = 3 * 8 * 8;

    var main_window_x: c_int = undefined;
    var main_window_y: c_int = undefined;
    c.SDL_GetWindowPosition(window, &main_window_x, &main_window_y);
    const vram_window_x = main_window_x + (160 * SCALE);
    const vram_window_y = main_window_y + 10;

    const vram_window = c.SDL_CreateWindow(
        "vram viewer",
        vram_window_x,
        vram_window_y,
        VRAM_WINDOW_WIDTH * SCALE,
        VRAM_WINDOW_HEIGHT * SCALE,
        c.SDL_WINDOW_OPENGL,
    ) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const vram_renderer = c.SDL_CreateRenderer(vram_window, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const vram_texture = c.SDL_CreateTexture(
        vram_renderer,
        c.SDL_PIXELFORMAT_RGB24,
        c.SDL_TEXTUREACCESS_STREAMING,
        VRAM_WINDOW_WIDTH,
        VRAM_WINDOW_HEIGHT,
    ) orelse {
        c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    var vram_pixels = try alloc.alloc(
        Pixel,
        VRAM_WINDOW_HEIGHT * VRAM_WINDOW_WIDTH,
    );
    defer alloc.free(vram_pixels);

    // GB init

    const rom = try std.fs.cwd().readFileAlloc(alloc, rom_filepath, 1024 * 1024 * 1024);
    defer alloc.free(rom);

    const save_data: ?[]u8 = read_save_data: {
        const data = std.fs.cwd().readFileAlloc(alloc, save_data_filepath, 128 * 1024) catch |err| switch (err) {
            error.FileNotFound => break :read_save_data null,
            else => {
                std.log.warn("Failed to read save data: {}\n", .{err});
                break :read_save_data null;
            },
        };
        break :read_save_data data;
    };
    defer if (save_data) |data| alloc.free(data);

    var gb = try Gb.init(alloc, rom, save_data, Palette.green, audio_device);
    defer gb.deinit(alloc);

    // ---

    const debuggerThread = try std.Thread.spawn(.{}, runDebugger, .{&gb});
    debuggerThread.detach();

    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(gb.screen), 160 * 3);
    c.SDL_PauseAudioDevice(audio_device, 0);

    if (true) {
        //try gb.debug.breakpoints.append(.{ .bank = 3, .addr = 0x4000 });
        //try gb.debug.breakpoints.append(.{ .bank = 0, .addr = 0x0181 });
        gb.debug.stackBase = 0xdfff;
    }

    while (gb.isRunning()) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYUP => switch (event.key.keysym.sym) {
                    c.SDLK_a => gb.joypad.releaseButton(Button.start),
                    c.SDLK_s => gb.joypad.releaseButton(Button.select),
                    c.SDLK_x => gb.joypad.releaseButton(Button.a),
                    c.SDLK_z => gb.joypad.releaseButton(Button.b),
                    c.SDLK_RIGHT => gb.joypad.releaseButton(Button.right),
                    c.SDLK_LEFT => gb.joypad.releaseButton(Button.left),
                    c.SDLK_UP => gb.joypad.releaseButton(Button.up),
                    c.SDLK_DOWN => gb.joypad.releaseButton(Button.down),
                    else => {},
                },
                c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    c.SDLK_a => gb.joypad.pressButton(Button.start),
                    c.SDLK_s => gb.joypad.pressButton(Button.select),
                    c.SDLK_x => gb.joypad.pressButton(Button.a),
                    c.SDLK_z => gb.joypad.pressButton(Button.b),
                    c.SDLK_RIGHT => gb.joypad.pressButton(Button.right),
                    c.SDLK_LEFT => gb.joypad.pressButton(Button.left),
                    c.SDLK_UP => gb.joypad.pressButton(Button.up),
                    c.SDLK_DOWN => gb.joypad.pressButton(Button.down),
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
        const lcd_on_at_start_of_frame = gb.isLcdOn();

        try stepGameboy(&gb, FRAME_CYCLES);

        if (lcd_on_at_start_of_frame) {
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

        const actualFrameTimeNs = (try std.time.Instant.now()).since(start);
        const delay_ns = FRAME_CYCLES * 1000 -| actualFrameTimeNs;
        if (delay_ns > 100) {
            std.time.sleep(delay_ns);
        }

        {
            const uncapped_fps = 1_000_000_000 / actualFrameTimeNs;
            const fps = if (uncapped_fps > 60) 60 else uncapped_fps;
            var buf: [32]u8 = undefined;
            const title = try std.fmt.bufPrint(&buf, "gameboy (FPS: {})\x00", .{fps});
            const title_cstr: [*:0]const u8 = title.ptr[0 .. title.len - 1 :0];
            c.SDL_SetWindowTitle(window, title_cstr);
        }
    }

    try gb.cart.persistRam(save_data_filepath);
}

fn audioCallback(userdata: ?*anyopaque, buffer_maybe: ?[*]u8, _: c_int) callconv(.C) void {
    const samples = if (userdata) |ud| @as([*]f32, @alignCast(@ptrCast(ud))) else return;
    const buffer = @as([*]f32, @alignCast(@ptrCast(buffer_maybe orelse return)));

    @memset(buffer[0..@intCast(BUFFER_SIZE)], 0);
    //std.debug.print("AUDIO **** copying samples to buffer\n", .{});
    @memcpy(buffer[0..@intCast(BUFFER_SIZE)], samples);
    //std.debug.print("AUDIO **** copying samples to buffer DONE\n", .{});
}
