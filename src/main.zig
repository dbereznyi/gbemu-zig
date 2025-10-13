const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("pixel.zig").Pixel;
const Gb = @import("gameboy/gameboy.zig").Gb;
const runGameboy = @import("gameboy/run.zig").runGameboy;
const Palette = @import("gameboy/ppu/ppu.zig").Ppu.Palette;
const runDebugger = @import("gameboy/debug/runDebugger.zig").runDebugger;
const Sample = @import("sample.zig").Sample;
const constants = @import("constants.zig");
const renderVramViewer = @import("gameboy/ppu/vram_viewer.zig").renderVramViewer;

const CYCLES_UNTIL_VBLANK: usize = 16416;
const VBLANK_CYCLES: usize = 1140;
const FRAME_CYCLES: usize = CYCLES_UNTIL_VBLANK + VBLANK_CYCLES;

const WINDOW_SCALE = 3;

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

    var sdl = try Sdl.init(alloc);
    defer sdl.deinit(alloc);

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

    var gb = try Gb.init(
        alloc,
        rom,
        save_data,
        Palette.green,
        .{
            .context = @ptrCast(&sdl),
            .callback = @ptrCast(&Sdl.vblankCallback),
        },
        .{
            .context = @ptrCast(&sdl),
            .callback = @ptrCast(&Sdl.audioCallback),
        },
    );
    defer gb.deinit(alloc);

    if (false) {
        //try gb.debug.breakpoints.append(.{ .bank = 3, .addr = 0x4000 });
        try gb.debug.breakpoints.append(.{ .bank = 0, .addr = 0x028a });
        gb.debug.stack_base = 0xdfff;
    }

    try sdl.run(&gb);

    try gb.cart.persistRam(save_data_filepath);
}

const Window = struct {
    const Self = @This();

    pub const Config = struct {
        title: [*c]const u8,
        width: c_int,
        height: c_int,
        scale: c_int,
        pos_x: ?c_int,
        pos_y: ?c_int,
    };

    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,

    width: c_int,
    height: c_int,
    scale: c_int,

    pub fn init(config: Config) !Self {
        const window = c.SDL_CreateWindow(
            config.title,
            if (config.pos_x) |pos_x| pos_x else c.SDL_WINDOWPOS_UNDEFINED,
            if (config.pos_y) |pos_y| pos_y else c.SDL_WINDOWPOS_UNDEFINED,
            config.width * config.scale,
            config.height * config.scale,
            c.SDL_WINDOW_OPENGL,
        ) orelse {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGB24,
            c.SDL_TEXTUREACCESS_STREAMING,
            config.width,
            config.height,
        ) orelse {
            c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        return .{
            .window = window,
            .renderer = renderer,
            .texture = texture,
            .width = config.width,
            .height = config.height,
            .scale = config.scale,
        };
    }

    pub fn deinit(self: *const Self) void {
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }

    pub fn setPixels(self: *Self, pixels: []Pixel) void {
        _ = c.SDL_UpdateTexture(self.texture, null, @ptrCast(pixels), self.width * self.scale);
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        const title_cstr: [*:0]const u8 = title.ptr[0 .. title.len - 1 :0];
        c.SDL_SetWindowTitle(self.window, title_cstr);
    }
};

const Sdl = struct {
    const Self = @This();
    const FPS_LEN = 10;

    gb: ?*Gb,
    gb_window: Window,
    vram_pixels: []Pixel,
    vram_window: Window,
    audio_device: u32,
    samples_buf: []Sample,
    samples_buf_ix: usize,
    last_vblank_at: std.time.Instant,
    fps: [FPS_LEN]f32,
    fps_ix: usize,

    pub fn init(alloc: std.mem.Allocator) !Self {
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        const gb_window = try Window.init(.{
            .title = "gameboy",
            .width = constants.GB.SCREEN_WIDTH,
            .height = constants.GB.SCREEN_HEIGHT,
            .scale = WINDOW_SCALE,
            .pos_x = null,
            .pos_y = null,
        });

        const VRAM_WINDOW_WIDTH = 16 * 8;
        const VRAM_WINDOW_HEIGHT = 3 * 8 * 8;
        var gb_window_x: c_int = undefined;
        var gb_window_y: c_int = undefined;
        _ = c.SDL_GetWindowPosition(gb_window.window, &gb_window_x, &gb_window_y);

        const vram_window = try Window.init(.{
            .title = "vram viewer",
            .width = VRAM_WINDOW_WIDTH,
            .height = VRAM_WINDOW_HEIGHT,
            .scale = WINDOW_SCALE,
            .pos_x = gb_window_x + (constants.GB.SCREEN_WIDTH * WINDOW_SCALE),
            .pos_y = gb_window_y,
        });

        var audio_spec = c.SDL_AudioSpec{
            .freq = constants.AUDIO.SAMPLE_RATE,
            .format = c.AUDIO_F32,
            .channels = constants.AUDIO.NUM_CHANNELS,
            .samples = constants.AUDIO.SAMPLES_BUFFER_LEN,
            .size = undefined,
            .silence = undefined,
            .callback = null,
            .userdata = undefined,
        };
        const audio_device = c.SDL_OpenAudioDevice(null, 0, &audio_spec, null, 0);
        if (audio_device < 0) {
            c.SDL_Log("Unable to open audio device: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        const samples_buf = try alloc.alloc(Sample, constants.AUDIO.SAMPLES_BUFFER_LEN);

        return .{
            .gb = null,
            .gb_window = gb_window,
            .vram_pixels = try alloc.alloc(Pixel, VRAM_WINDOW_HEIGHT * VRAM_WINDOW_WIDTH),
            .vram_window = vram_window,
            .audio_device = audio_device,
            .samples_buf = samples_buf,
            .samples_buf_ix = 0,
            .last_vblank_at = try std.time.Instant.now(),
            .fps = [_]f32{0.0} ** FPS_LEN,
            .fps_ix = 0,
        };
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        alloc.free(self.samples_buf);
        c.SDL_CloseAudioDevice(self.audio_device);
        self.gb_window.deinit();
        self.vram_window.deinit();
        alloc.free(self.vram_pixels);
        c.SDL_Quit();
    }

    pub fn run(self: *Self, gb: *Gb) !void {
        self.gb = gb;

        const debugger_thread = try std.Thread.spawn(.{}, runDebugger, .{gb});
        debugger_thread.detach();

        c.SDL_PauseAudioDevice(self.audio_device, 0);

        self.gb_window.setPixels(gb.ppu.screen);

        renderVramViewer(gb, &self.vram_pixels);
        self.vram_window.setPixels(self.vram_pixels);

        self.last_vblank_at = try std.time.Instant.now();

        while (gb.isRunning()) {
            if (gb.debug.isPaused()) {
                self.handleEvents();
            }

            runGameboy(gb);
        }
    }

    fn handleEvents(self: *Self) void {
        if (self.gb) |gb| {
            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event) != 0) {
                switch (event.type) {
                    c.SDL_KEYUP => switch (event.key.keysym.sym) {
                        c.SDLK_a => gb.joypad.releaseButton(.start),
                        c.SDLK_s => gb.joypad.releaseButton(.select),
                        c.SDLK_x => gb.joypad.releaseButton(.a),
                        c.SDLK_z => gb.joypad.releaseButton(.b),
                        c.SDLK_RIGHT => gb.joypad.releaseButton(.right),
                        c.SDLK_LEFT => gb.joypad.releaseButton(.left),
                        c.SDLK_UP => gb.joypad.releaseButton(.up),
                        c.SDLK_DOWN => gb.joypad.releaseButton(.down),
                        else => {},
                    },
                    c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                        c.SDLK_a => gb.joypad.pressButton(.start),
                        c.SDLK_s => gb.joypad.pressButton(.select),
                        c.SDLK_x => gb.joypad.pressButton(.a),
                        c.SDLK_z => gb.joypad.pressButton(.b),
                        c.SDLK_RIGHT => gb.joypad.pressButton(.right),
                        c.SDLK_LEFT => gb.joypad.pressButton(.left),
                        c.SDLK_UP => gb.joypad.pressButton(.up),
                        c.SDLK_DOWN => gb.joypad.pressButton(.down),
                        else => {},
                    },
                    c.SDL_WINDOWEVENT => {
                        if (event.window.event == c.SDL_WINDOWEVENT_CLOSE) {
                            if (event.window.windowID == c.SDL_GetWindowID(self.vram_window.window)) {
                                c.SDL_HideWindow(self.vram_window.window);
                            } else if (event.window.windowID == c.SDL_GetWindowID(self.gb_window.window)) {
                                gb.setIsRunning(false);
                            }
                        }
                    },
                    c.SDL_QUIT => gb.setIsRunning(false),
                    else => {},
                }
            }
        }
    }

    pub fn vblankCallback(self: *Self, pixels: []Pixel) void {
        const now = std.time.Instant.now() catch @panic("Could not get current time");
        defer self.last_vblank_at = now;

        self.gb_window.setPixels(pixels);

        if (self.gb) |gb| {
            // This might be a bit cleaner if done via a separate callback, but works for now
            renderVramViewer(gb, &self.vram_pixels);
            self.vram_window.setPixels(self.vram_pixels);
        }

        self.handleEvents();

        if (constants.DEBUG.DISPLAY_FPS) {
            const frame_time_ns = now.since(self.last_vblank_at);

            const one_sec_ns: f32 = 1_000_000_000.0;
            const fps = one_sec_ns / @as(f32, @floatFromInt(frame_time_ns));

            self.fps[self.fps_ix] = fps;
            self.fps_ix += 1;

            if (self.fps_ix == FPS_LEN) {
                defer self.fps_ix = 0;

                var avg_fps: f32 = 0.0;
                for (0..FPS_LEN) |i| {
                    avg_fps += self.fps[i];
                }
                avg_fps /= @floatFromInt(FPS_LEN);

                var buf: [32]u8 = undefined;
                const title = std.fmt.bufPrint(&buf, "gameboy (FPS: {d:.2})\x00", .{avg_fps}) catch @panic("buffer overflow when trying to write title");
                self.gb_window.setTitle(title);
            }
        }
    }

    pub fn audioCallback(self: *Self, sample: Sample) void {
        self.samples_buf[self.samples_buf_ix] = sample;
        self.samples_buf_ix += 1;

        if (self.samples_buf_ix == constants.AUDIO.SAMPLES_BUFFER_LEN) {
            defer self.samples_buf_ix = 0;

            const result = c.SDL_QueueAudio(
                self.audio_device,
                @ptrCast(self.samples_buf),
                @intCast(self.samples_buf.len * @sizeOf(Sample)),
            );
            if (result != 0) {
                std.debug.panic(
                    "SDL_QueueAudio failed with error: {s}\n",
                    .{c.SDL_GetError()},
                );
            }
        }
    }
};
