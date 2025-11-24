const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Pixel = @import("core").Pixel;
const Gb = @import("core").Gb;
const runGameboy = @import("core").runGameboy;
const runDebugger = @import("core").runDebugger;
const Sample = @import("core").Sample;
const constants = @import("constants");
const renderVramViewer = @import("core").renderVramViewer;
const Bess = @import("core").bess.Bess;
const writeBess = @import("core").bess.writeBess;
const Button = @import("core").Button;

const WINDOW_SCALE = 3;

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
    is_visible: bool,

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
            .is_visible = true,
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

    pub fn getPosition(self: *const Self) struct { x: c_int, y: c_int } {
        var x: c_int = undefined;
        var y: c_int = undefined;
        _ = c.SDL_GetWindowPosition(self.window, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn setPosition(self: *Self, x: c_int, y: c_int) void {
        c.SDL_SetWindowPosition(self.window, x, y);
    }

    pub fn toggleVisible(self: *Self) void {
        if (self.is_visible) {
            c.SDL_HideWindow(self.window);
        } else {
            c.SDL_ShowWindow(self.window);
        }

        self.is_visible = !self.is_visible;
    }

    pub fn hide(self: *Self) void {
        if (self.is_visible) {
            c.SDL_HideWindow(self.window);
            self.is_visible = false;
        }
    }
};

pub const Sdl = struct {
    const Self = @This();
    const FPS_LEN = 10;

    alloc: std.mem.Allocator,

    gb: *Gb,
    gb_window: Window,
    vram_pixels: []Pixel,
    vram_window: Window,
    audio_device: u32,
    samples_buf: []Sample,
    samples_buf_ix: usize,
    last_vblank_at: std.time.Instant,
    fps: [FPS_LEN]f32,
    fps_ix: usize,

    rom_filepath_noext: []const u8,
    controller: ?*c.SDL_GameController,

    pub fn init(alloc: std.mem.Allocator, rom_filepath_noext: []const u8, gb: *Gb) !Self {
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMECONTROLLER) != 0) {
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

        const num_joysticks: usize = @intCast(c.SDL_NumJoysticks());
        var controller: ?*c.SDL_GameController = null;
        for (0..num_joysticks) |i| {
            const joystick_ix: c_int = @intCast(i);
            if (c.SDL_IsGameController(joystick_ix) != 0) {
                controller = c.SDL_GameControllerOpen(joystick_ix);
                if (controller != null) {
                    break;
                }
            }
        }

        return .{
            .alloc = alloc,
            .gb = gb,
            .gb_window = gb_window,
            .vram_pixels = try alloc.alloc(Pixel, VRAM_WINDOW_HEIGHT * VRAM_WINDOW_WIDTH),
            .vram_window = vram_window,
            .audio_device = audio_device,
            .samples_buf = samples_buf,
            .samples_buf_ix = 0,
            .last_vblank_at = try std.time.Instant.now(),
            .fps = [_]f32{0.0} ** FPS_LEN,
            .fps_ix = 0,
            .rom_filepath_noext = rom_filepath_noext,
            .controller = controller,
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

    pub fn run(self: *Self) !void {
        const debugger_thread = try std.Thread.spawn(.{}, runDebugger, .{self.gb});
        debugger_thread.detach();

        c.SDL_PauseAudioDevice(self.audio_device, 0);

        self.gb_window.setPixels(self.gb.ppu.screen);

        renderVramViewer(self.gb, &self.vram_pixels);
        self.vram_window.setPixels(self.vram_pixels);

        self.last_vblank_at = try std.time.Instant.now();

        while (self.gb.isRunning()) {
            if (self.gb.debug.paused) {
                try self.handleEvents();
            }

            runGameboy(self.gb);
        }
    }

    fn handleEvents(self: *Self) !void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.window.windowID == c.SDL_GetWindowID(self.vram_window.window)) {
                handleVramWindowEvent(self, &event);
            } else if (event.window.windowID == c.SDL_GetWindowID(self.gb_window.window)) {
                handleGbWindowEvent(self, &event);
            }

            switch (event.type) {
                c.SDL_KEYUP, c.SDL_KEYDOWN => {
                    // GB button presses
                    const gb_button: ?Button = switch (event.key.keysym.sym) {
                        c.SDLK_x => .a,
                        c.SDLK_z => .b,
                        c.SDLK_a => .start,
                        c.SDLK_s => .select,
                        c.SDLK_UP => .up,
                        c.SDLK_DOWN => .down,
                        c.SDLK_LEFT => .left,
                        c.SDLK_RIGHT => .right,
                        else => null,
                    };
                    if (gb_button) |button| {
                        if (event.key.state == c.SDL_PRESSED) {
                            self.gb.joypad.pressButton(button);
                        } else {
                            self.gb.joypad.releaseButton(button);
                        }
                    }

                    switch (event.key.keysym.sym) {
                        // Savestates
                        c.SDLK_0, c.SDLK_1, c.SDLK_2, c.SDLK_3, c.SDLK_4, c.SDLK_6, c.SDLK_7, c.SDLK_8, c.SDLK_9 => blk: {
                            if (event.key.state != c.SDL_PRESSED) {
                                break :blk;
                            }

                            const slot: usize = @intCast(event.key.keysym.sym - c.SDLK_0);

                            if (event.key.keysym.mod & c.KMOD_CTRL != 0 and event.key.keysym.mod & c.KMOD_SHIFT == 0) {
                                loadSaveState(
                                    self.alloc,
                                    self.gb,
                                    self.rom_filepath_noext,
                                    slot,
                                ) catch |err| {
                                    std.log.err("Failed to load savestate: {}\n", .{err});
                                };
                            } else if (event.key.keysym.mod & c.KMOD_CTRL != 0 and event.key.keysym.mod & c.KMOD_SHIFT != 0) {
                                createSaveState(
                                    self.alloc,
                                    self.gb,
                                    self.rom_filepath_noext,
                                    slot,
                                ) catch |err| {
                                    std.log.err("Failed to create savestate: {}\n", .{err});
                                };
                            }
                        },
                        // Toggle VRAM viewer
                        c.SDLK_v => blk: {
                            if (event.key.state != c.SDL_PRESSED) {
                                break :blk;
                            }

                            if (event.key.keysym.mod & c.KMOD_CTRL != 0) {
                                if (!self.vram_window.is_visible) {
                                    // Reset window position to be next to the GB window
                                    const gb_pos = self.gb_window.getPosition();
                                    self.vram_window.setPosition(
                                        gb_pos.x + (constants.GB.SCREEN_WIDTH * WINDOW_SCALE),
                                        gb_pos.y,
                                    );
                                }

                                self.vram_window.toggleVisible();
                            }
                        },
                        else => {},
                    }
                },
                c.SDL_CONTROLLERBUTTONDOWN, c.SDL_CONTROLLERBUTTONUP => {
                    const gb_button: ?Button = switch (event.cbutton.button) {
                        c.SDL_CONTROLLER_BUTTON_A => .b,
                        c.SDL_CONTROLLER_BUTTON_B => .a,
                        c.SDL_CONTROLLER_BUTTON_START => .start,
                        c.SDL_CONTROLLER_BUTTON_BACK => .select,
                        c.SDL_CONTROLLER_BUTTON_DPAD_UP => .up,
                        c.SDL_CONTROLLER_BUTTON_DPAD_DOWN => .down,
                        c.SDL_CONTROLLER_BUTTON_DPAD_LEFT => .left,
                        c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT => .right,
                        else => null,
                    };
                    if (gb_button) |button| {
                        if (event.cbutton.state == c.SDL_PRESSED) {
                            self.gb.joypad.pressButton(button);
                        } else {
                            self.gb.joypad.releaseButton(button);
                        }
                    }
                },
                c.SDL_CONTROLLERDEVICEADDED => {
                    if (self.controller == null) {
                        self.controller = c.SDL_GameControllerOpen(event.cdevice.which);
                    }
                },
                c.SDL_CONTROLLERDEVICEREMOVED => {
                    c.SDL_GameControllerClose(self.controller);
                    self.controller = null;
                },
                c.SDL_QUIT => self.gb.setIsRunning(false),
                else => {},
            }
        }
    }

    pub fn vblankCallback(self: *Self, pixels: []Pixel) void {
        const now = std.time.Instant.now() catch @panic("Could not get current time");
        defer self.last_vblank_at = now;

        self.gb_window.setPixels(pixels);

        // This might be a bit cleaner if done via a separate callback, but works for now
        renderVramViewer(self.gb, &self.vram_pixels);
        self.vram_window.setPixels(self.vram_pixels);

        self.handleEvents() catch @panic("Error while handling SDL events");

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

fn handleGbWindowEvent(self: *Sdl, event: *c.SDL_Event) void {
    switch (event.type) {
        c.SDL_WINDOWEVENT => {
            if (event.window.event == c.SDL_WINDOWEVENT_CLOSE) {
                self.gb.setIsRunning(false);
            }
        },
        else => {},
    }
}

fn handleVramWindowEvent(self: *Sdl, event: *c.SDL_Event) void {
    switch (event.type) {
        c.SDL_WINDOWEVENT => {
            if (event.window.event == c.SDL_WINDOWEVENT_CLOSE) {
                self.vram_window.hide();
            }
        },
        else => {},
    }
}

fn loadSaveState(
    alloc: std.mem.Allocator,
    gb: *Gb,
    rom_filepath_noext: []const u8,
    slot: usize,
) !void {
    const bess_filepath = try std.fmt.allocPrint(
        alloc,
        "{s}.s{}",
        .{ rom_filepath_noext, slot },
    );
    defer alloc.free(bess_filepath);

    const data = std.fs.cwd().readFileAlloc(alloc, bess_filepath, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.warn("No savestate data found in slot {}.\n", .{slot});
            return;
        },
        else => {
            return err;
        },
    };
    errdefer alloc.free(data);

    const bess = try Bess.init(alloc, data);
    errdefer bess.deinit();

    std.log.info("Loading savestate in slot #{}\n", .{slot});
    gb.bess = bess;
}

fn createSaveState(
    alloc: std.mem.Allocator,
    gb: *Gb,
    rom_filepath_noext: []const u8,
    slot: usize,
) !void {
    const bess_filepath = try std.fmt.allocPrint(
        alloc,
        "{s}.s{}",
        .{ rom_filepath_noext, slot },
    );
    defer alloc.free(bess_filepath);

    const bess_file: ?std.fs.File = blk: {
        const file = std.fs.cwd().createFile(bess_filepath, .{}) catch |err| {
            std.log.err("Failed to open savestate file for writing: {}\n", .{err});
            break :blk null;
        };
        break :blk file;
    };
    defer if (bess_file) |file| file.close();

    if (bess_file) |file| {
        std.log.info("Creating savestate in slot #{}\n", .{slot});
        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        const writer = &file_writer.interface;
        writeBess(gb, writer) catch |err| {
            std.log.err("Failed to create savestate: {}\n", .{err});
        };
        try file_writer.end();
    }
}
