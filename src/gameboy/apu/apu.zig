const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Sample = @import("../../sample.zig").Sample;
const format = std.fmt.format;
const constants = @import("../../constants.zig");

const SAMPLES_CLOCK_DIVIDER = @as(f32, @floatFromInt(constants.GB.CLOCK_RATE)) / 2 / @as(f32, @floatFromInt(constants.AUDIO.SAMPLE_RATE));
const SAMPLES_CLOCK_DIVIDER_HIGH: i32 = @ceil(SAMPLES_CLOCK_DIVIDER);
const MAX_CYCLES_PER_SAMPLE = SAMPLES_CLOCK_DIVIDER_HIGH;

const BL_PHASES: usize = 64;
const BL_STEP_WIDTH: usize = 32;
const LOW_PASS: f32 = 0.999;
const HIGH_PASS: f32 = 0.990;

fn initBandLimitedSteps(alloc: std.mem.Allocator) !*[BL_PHASES][BL_STEP_WIDTH]f32 {
    const master = try alloc.alloc(f32, BL_PHASES * BL_STEP_WIDTH);
    @memset(master, 0.5);

    {
        var gain: f32 = 0.5 / 0.777;
        const sine_size: f32 = 256 * BL_PHASES + 2;
        const max_harmonic = sine_size / 2 / BL_PHASES;

        var h: f32 = 1.0;
        while (h <= max_harmonic) : (h += 2.0) {
            const amplitude = gain / h;
            const to_angle = std.math.tau / sine_size * h;
            for (0..master.len) |i| {
                const i_f32: f32 = @floatFromInt(i);
                const denom: f32 = @as(f32, @floatFromInt(master.len)) / 2;
                const val = std.math.sin((i_f32 - denom) * to_angle) * amplitude;
                master[i] += val;
            }
            gain *= LOW_PASS;
        }
    }

    const steps = try alloc.create([BL_PHASES][BL_STEP_WIDTH]f32);

    for (0..BL_PHASES) |phase| {
        var err: f32 = 1.0;
        var prev: f32 = 0.0;
        for (0..BL_STEP_WIDTH) |i| {
            const cur = master[i * BL_PHASES + (BL_PHASES - 1 - phase)];
            const delta = cur - prev;
            err = err - delta;
            prev = cur;
            steps[phase][i] = delta;
        }

        steps[phase][BL_STEP_WIDTH / 2 - 1] += err * 0.5;
        steps[phase][BL_STEP_WIDTH / 2] += err * 0.5;
    }

    return steps;
}

pub const ApuReg = enum {
    NR10,
    NR11,
    NR12,
    NR13,
    NR14,
    NR21,
    NR22,
    NR23,
    NR24,
    NR30,
    NR31,
    NR32,
    NR33,
    NR34,
    NR41,
    NR42,
    NR43,
    NR44,
    NR50,
    NR51,
    NR52,
};

// Linearly translates values from $0 to $f into the range [-1.0, 1.0], negative slope ($0 => 1.0).
fn toAnalog(value: u4) f32 {
    return ((2.0 / 15.0) * (15.0 - @as(f32, @floatFromInt(value)))) - 1.0;
}

const WAVEFORMS = [4][8]u1{
    [_]u1{ 1, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 0, 0, 0 },
    [_]u1{ 1, 0, 0, 0, 0, 0, 0, 1 },
};

fn calcNewSweepFreqWithOverflowCheck(shadow: u11, dir: u1, individual_step: u3) struct { u11, u1 } {
    const temp = shadow >> individual_step;
    return if (dir == 0) @addWithOverflow(shadow, temp) else @subWithOverflow(shadow, temp);
}

const CH1 = 0;
const CH2 = 1;
const CH3 = 2;
const CH4 = 3;

const BandLimited = struct {
    buffer: [BL_STEP_WIDTH]Sample,
    buffer_ix: usize,
    output: Sample,
    input: Sample,
};

const Ch1 = struct {
    const Self = @This();

    period_sweep_pace: u3,
    period_sweep_dir: u1,
    period_sweep_individual_step: u3,
    period_sweep_enabled: u1,
    period_sweep_timer: u3,
    period_sweep_shadow: u11,

    pub fn init() Self {
        return .{
            .period_sweep_pace = 0,
            .period_sweep_dir = 0,
            .period_sweep_individual_step = 0,
            .period_sweep_enabled = 0,
            .period_sweep_timer = 0,
            .period_sweep_shadow = 0,
        };
    }
};

const Ch3 = struct {
    const Self = @This();

    init_length_timer: u8,
    length_timer: u8,
    init_volume: u2,
    volume: u2,
    dac_enabled: u1,
    wav_ram_ix: u5,
    wav_ram: [32]u4,

    // Number of APU cycles until next sample
    timer: u13,

    pub fn init() Self {
        return .{
            .init_length_timer = 0,
            .length_timer = 0,
            .init_volume = 0,
            .volume = 0,
            .dac_enabled = 0,
            .wav_ram_ix = 0,
            .wav_ram = [_]u4{0} ** 32,
            .timer = 0,
        };
    }

    pub fn loadTimer(self: *Self, period_setting: u11) void {
        const timer_val = 0b111_1111_1111 - period_setting + 1;
        self.timer = timer_val;
    }
};

const Ch4 = struct {
    const Self = @This();

    lfsr: u16,
    lfsr_timer: u32,
    clock_shift: u4,
    lfsr_width: u1,
    clock_divider: u3,

    timer: u5,
    counter: u16,

    tick_envelope: bool,
    envelope_dir: u1,
    envelope_sweep_pace: u3,
    envelope_timer: u3,

    pub fn init() Self {
        return .{
            .lfsr = 0,
            .lfsr_timer = 0,
            .clock_shift = 0,
            .lfsr_width = 0,
            .clock_divider = 0,
            .timer = 0,
            .counter = 0,
            .tick_envelope = false,
            .envelope_dir = 0,
            .envelope_sweep_pace = 0,
            .envelope_timer = 0,
        };
    }
};

const PulseChannel = struct {
    const Self = @This();

    wave_duty: u2,
    duty_step: u3,
    // Number of APU cycles until next sample
    timer: u13,

    tick_envelope: bool,
    envelope_dir: u1,
    envelope_sweep_pace: u3,
    envelope_timer: u3,

    pub fn init() Self {
        return .{
            .wave_duty = 0,
            .duty_step = 0,
            .timer = 0,
            .tick_envelope = false,
            .envelope_dir = 0,
            .envelope_sweep_pace = 0,
            .envelope_timer = 0,
        };
    }

    pub fn loadTimer(self: *Self, period_setting: u11) void {
        const period_setting_u13: u13 = period_setting;
        const timer_val = ((0b111_1111_1111 - period_setting_u13) << 1) + 1;
        self.timer = timer_val;
    }
};

pub const Apu = struct {
    const Self = @This();

    pub const AudioCallback = struct {
        context: *anyopaque,
        callback: *const fn (context: *anyopaque, sample: Sample) void,
    };

    on: u1,
    volume_left: u3,
    volume_right: u3,

    // Common channel registers
    ch_on: [4]u1,
    output_left: [4]u1,
    output_right: [4]u1,
    length_enable: [4]u1,
    init_length_timer: [4]u6,
    length_timer: [4]u6,
    ch_init_volume: [4]u4,
    ch_volume: [4]u4,
    period_setting: [4]u11,
    period: [4]u11,

    ch1: Ch1,
    ch3: Ch3,
    ch4: Ch4,
    pulse: [2]PulseChannel,

    band_limited_steps: *[BL_PHASES][BL_STEP_WIDTH]f32,
    ch_samples: [4][]Sample,
    ch_samples_ix: usize,
    band_limited: [4]BandLimited,
    samples_timer: u8,
    samples_clock_divider_ix: usize,

    audio_callback: ?AudioCallback,
    audio_files: ?[4]std.fs.File,

    div_apu_counter: u8,

    // This counts 2 MHz cycles
    cycles: i32,
    sample_cycles: u32,

    cycles_since_last_render: i32,

    pub fn init(alloc: std.mem.Allocator, audio_callback: ?AudioCallback) !Self {
        const ch_samples = [_][]Sample{
            try alloc.alloc(Sample, constants.AUDIO.SAMPLES_BUFFER_LEN),
            try alloc.alloc(Sample, constants.AUDIO.SAMPLES_BUFFER_LEN),
            try alloc.alloc(Sample, constants.AUDIO.SAMPLES_BUFFER_LEN),
            try alloc.alloc(Sample, constants.AUDIO.SAMPLES_BUFFER_LEN),
        };

        const audio_files = blk: {
            if (constants.DEBUG.OUTPUT_AUDIO_FILES) {
                const dir = std.fs.cwd();

                break :blk [_]std.fs.File{
                    try dir.createFile("apu_1.dat", .{}),
                    try dir.createFile("apu_2.dat", .{}),
                    try dir.createFile("apu_3.dat", .{}),
                    try dir.createFile("apu_4.dat", .{}),
                };
            } else {
                break :blk null;
            }
        };

        return .{
            .on = 0,
            .volume_left = 0,
            .volume_right = 0,
            .ch_on = [_]u1{0} ** 4,
            .output_left = [_]u1{0} ** 4,
            .output_right = [_]u1{0} ** 4,
            .length_enable = [_]u1{0} ** 4,
            .init_length_timer = [_]u6{0} ** 4,
            .length_timer = [_]u6{0} ** 4,
            .ch_init_volume = [_]u4{0} ** 4,
            .ch_volume = [_]u4{0} ** 4,
            .period_setting = [_]u11{0} ** 4,
            .period = [_]u11{0} ** 4,
            .ch1 = Ch1.init(),
            .ch3 = Ch3.init(),
            .ch4 = Ch4.init(),
            .pulse = [_]PulseChannel{PulseChannel.init()} ** 2,
            .audio_callback = audio_callback,
            .band_limited_steps = try initBandLimitedSteps(alloc),
            .band_limited = [_]BandLimited{.{
                .buffer = [_]Sample{Sample.init(0, 0)} ** BL_STEP_WIDTH,
                .buffer_ix = 0,
                .output = Sample.init(0, 0),
                .input = Sample.init(0, 0),
            }} ** 4,
            .ch_samples = ch_samples,
            .ch_samples_ix = 0,
            .samples_timer = 0,
            .samples_clock_divider_ix = 0,
            .div_apu_counter = 0,
            .cycles = 0,
            .sample_cycles = 0,
            .cycles_since_last_render = 0,
            .audio_files = audio_files,
        };
    }

    fn isDacOn(self: *const Self, ch_ix: usize) bool {
        if (ch_ix == CH3) {
            return self.ch3.dac_enabled;
        } else {
            return self.init_volume[ch_ix] != 0 or self.envelope_dir[ch_ix] != 0;
        }
    }

    fn triggerChannel(self: *Self, ch_ix: usize) void {
        self.ch_on[ch_ix] = 1;

        if (ch_ix == CH3) {
            self.ch3.length_timer = self.ch3.init_length_timer;
            self.ch3.volume = self.ch3.init_volume;
        } else {
            self.length_timer[ch_ix] = self.init_length_timer[ch_ix];
            self.ch_volume[ch_ix] = self.ch_init_volume[ch_ix];
        }

        if (ch_ix == CH4) {
            self.ch4.lfsr = 0;
        } else {
            self.period[ch_ix] = self.period_setting[ch_ix];
        }

        if (ch_ix == CH1) {
            self.ch1.period_sweep_shadow = self.period[ch_ix];
            self.ch1.period_sweep_timer = 0;
            self.ch1.period_sweep_enabled = if (self.ch1.period_sweep_pace != 0 or self.ch1.period_sweep_individual_step != 0) 1 else 0;
            if (self.ch1.period_sweep_individual_step != 0) {
                const result = calcNewSweepFreqWithOverflowCheck(
                    self.ch1.period_sweep_shadow,
                    self.ch1.period_sweep_dir,
                    self.ch1.period_sweep_individual_step,
                );
                if (result[1] == 1) {
                    std.debug.print("freq overflow in trigger, turning off\n", .{});
                    self.ch_on[ch_ix] = 0;
                }
            }
        }
    }

    fn updateSample(self: *Self, ch_ix: usize, val: u4, phase: usize) void {
        const val_f32 = toAnalog(val);
        const input = Sample{
            .left = if (self.output_left[ch_ix] == 1) val_f32 else 0,
            .right = if (self.output_right[ch_ix] == 1) val_f32 else 0,
        };
        const bl: *BandLimited = &self.band_limited[ch_ix];
        if (input.equals(bl.input)) {
            return;
        }

        const delta = input.subtract(bl.input);
        bl.input = input;

        for (0..BL_STEP_WIDTH) |i| {
            const offset = (bl.buffer_ix + i) % bl.buffer.len;
            const step_val = self.band_limited_steps[phase][i];
            self.band_limited[ch_ix].buffer[offset].left += delta.left * step_val;
            self.band_limited[ch_ix].buffer[offset].right += delta.right * step_val;
        }
    }

    fn readSample(self: *Self, ch_ix: usize) Sample {
        const bl: *BandLimited = &self.band_limited[ch_ix];
        bl.output.left += bl.buffer[bl.buffer_ix].left * HIGH_PASS;
        bl.output.right += bl.buffer[bl.buffer_ix].right * HIGH_PASS;

        bl.buffer[bl.buffer_ix].left = 0;
        bl.buffer[bl.buffer_ix].right = 0;
        bl.buffer_ix = (bl.buffer_ix + 1) % bl.buffer.len;

        const vol_left = @as(f32, @floatFromInt(self.volume_left)) / @as(f32, @floatFromInt(0b111111));
        const vol_right = @as(f32, @floatFromInt(self.volume_right)) / @as(f32, @floatFromInt(0b111111));

        return .{
            .left = bl.output.left * vol_left,
            .right = bl.output.right * vol_right,
        };
    }

    pub fn render(self: *Self) void {
        defer self.cycles_since_last_render = 0;

        var output = Sample.init(0, 0);
        for (0..4) |ch_ix| {
            const ch_output = self.readSample(ch_ix);
            self.ch_samples[ch_ix][self.ch_samples_ix] = ch_output;
            output = output.add(ch_output);
        }
        defer self.ch_samples_ix = (self.ch_samples_ix + 1) % constants.AUDIO.SAMPLES_BUFFER_LEN;

        if (self.audio_callback) |audio_callback| {
            audio_callback.callback(audio_callback.context, output);
        }

        if (self.audio_files) |audio_files| {
            if (self.ch_samples_ix == constants.AUDIO.SAMPLES_BUFFER_LEN - 1) {
                for (0..4) |i| {
                    _ = audio_files[i].write(
                        std.mem.sliceAsBytes(self.ch_samples[i][0..self.ch_samples_ix]),
                    ) catch @panic("failed to write to file");
                }
            }
        }
    }

    pub fn run(self: *Self, force: bool) void {
        var cycles = self.cycles;

        const should_run = force or (cycles + self.cycles_since_last_render >= MAX_CYCLES_PER_SAMPLE) or (self.sample_cycles >= constants.GB.CLOCK_RATE);
        if (!should_run) {
            return;
        }

        while (cycles + self.cycles_since_last_render > MAX_CYCLES_PER_SAMPLE) {
            self.cycles = MAX_CYCLES_PER_SAMPLE - self.cycles_since_last_render;

            if (self.cycles > 0) {
                cycles -= self.cycles;
                self.run(true);

                if (!force) {
                    self.cycles = cycles;
                    return self.run(false);
                }
                continue;
            }

            if (self.sample_cycles >= constants.GB.CLOCK_RATE) {
                self.sample_cycles -= constants.GB.CLOCK_RATE;
                self.render();
            }

            break;
        }

        self.cycles = 0;

        // Pulse channels
        for (0..2) |ch_ix| {
            if (self.ch_on[ch_ix] == 0) {
                continue;
            }

            var cycles_rem = cycles;

            while (cycles_rem > self.pulse[ch_ix].timer) {
                cycles_rem -= self.pulse[ch_ix].timer + 1;
                self.pulse[ch_ix].loadTimer(self.period_setting[ch_ix]);

                self.pulse[ch_ix].duty_step +%= 1;
                const val = if (WAVEFORMS[self.pulse[ch_ix].wave_duty][self.pulse[ch_ix].duty_step] != 0) self.ch_volume[ch_ix] else 0;
                self.updateSample(ch_ix, val, @intCast(cycles - cycles_rem));
            }

            if (cycles_rem > 0) {
                self.pulse[ch_ix].timer -= @intCast(cycles_rem);
            }
        }

        // Wave channel
        if (self.ch_on[CH3] != 0) {
            var cycles_rem = cycles;

            while (cycles_rem > self.ch3.timer) {
                cycles_rem -= self.ch3.timer;
                self.ch3.loadTimer(self.period_setting[CH3]);

                self.ch3.wav_ram_ix +%= 1;
                const val_raw = self.ch3.wav_ram[self.ch3.wav_ram_ix];
                const val = switch (self.ch3.volume) {
                    0 => 0,
                    1 => val_raw,
                    2 => val_raw >> 1,
                    3 => val_raw >> 2,
                };
                self.updateSample(CH3, val, @intCast(cycles - cycles_rem));
            }

            if (cycles_rem > 0) {
                self.ch3.timer -= @intCast(cycles_rem);
            }
        }

        // Noise channel
        {
            var cycles_rem = cycles;

            const divider = @as(u5, @intCast(self.ch4.clock_divider)) << 2;
            const timer_reload = if (divider > 0) divider else 2;

            if (self.ch4.timer == 0) {
                self.ch4.timer = timer_reload;
            }

            while (cycles_rem >= self.ch4.timer) {
                cycles_rem -= self.ch4.timer;
                self.ch4.timer = timer_reload;

                const old_bit = (self.ch4.counter >> self.ch4.clock_shift) & 1;
                self.ch4.counter +%= 1;
                self.ch4.counter &= 0x3fff;
                const new_bit = (self.ch4.counter >> self.ch4.clock_shift) & 1;

                if (new_bit == 1 and old_bit == 0) {
                    const bit0_bit1_xor = self.ch4.lfsr ^ (self.ch4.lfsr >> 1);
                    const next_lfsr_bit = 0x0001 & ~bit0_bit1_xor;
                    self.ch4.lfsr >>= 1;

                    const high_bit_mask: u16 = if (self.ch4.lfsr_width == 1) 0x4040 else 0x4000;

                    if (next_lfsr_bit != 0) {
                        self.ch4.lfsr |= high_bit_mask;
                    } else {
                        self.ch4.lfsr &= ~high_bit_mask;
                    }

                    if (self.ch_on[CH4] != 0) {
                        const bit_0 = self.ch4.lfsr & 0x0001;
                        const val = if (bit_0 == 0) 0 else self.ch_volume[CH4];
                        self.updateSample(CH4, val, @intCast(cycles - cycles_rem));
                    }
                }
            }

            if (cycles_rem > 0) {
                self.ch4.timer -= @intCast(cycles_rem);
            }
        }

        self.cycles_since_last_render += cycles;
        if (self.sample_cycles >= constants.GB.CLOCK_RATE) {
            self.sample_cycles -= constants.GB.CLOCK_RATE;
            self.render();
        }
    }

    fn tickPulseEnvelope(self: *Self, ch_ix: usize) void {
        self.pulse[ch_ix].tick_envelope = false;
        if (self.pulse[ch_ix].envelope_sweep_pace == 0) {
            return;
        }

        if (self.pulse[ch_ix].envelope_dir == 1) {
            self.ch_volume[ch_ix] +|= 1;
        } else {
            self.ch_volume[ch_ix] -|= 1;
        }

        if (self.ch_on[ch_ix] != 0) {
            const val = if (WAVEFORMS[self.pulse[ch_ix].wave_duty][self.pulse[ch_ix].duty_step] != 0) self.ch_volume[ch_ix] else 0;
            self.updateSample(ch_ix, val, 0);
        }
    }

    fn tickNoiseEnvelope(self: *Self) void {
        self.ch4.tick_envelope = false;
        if (self.ch4.envelope_sweep_pace == 0) {
            return;
        }

        if (self.ch4.envelope_dir == 1) {
            self.ch_volume[CH4] +|= 1;
        } else {
            self.ch_volume[CH4] -|= 1;
        }

        if (self.ch_on[CH4] != 0) {
            const bit_0 = self.ch4.lfsr & 0x0001;
            const val = if (bit_0 == 0) 0 else self.ch_volume[CH4];
            self.updateSample(CH4, val, 0);
        }
    }

    pub fn handleDivEvent(self: *Self) void {
        self.run(true);

        if (self.on == 0) {
            return;
        }

        self.div_apu_counter +%= 1;

        const tick_256hz = self.div_apu_counter & 1 == 1;
        const tick_128hz = self.div_apu_counter & 3 == 3;
        const tick_64hz = self.div_apu_counter & 7 == 7;

        if (tick_64hz) {
            for (0..2) |ch_ix| {
                if (!self.pulse[ch_ix].tick_envelope) {
                    self.pulse[ch_ix].envelope_timer -%= 1;
                }
            }

            if (!self.ch4.tick_envelope) {
                self.ch4.envelope_timer -%= 1;
            }
        }

        for (0..2) |ch_ix| {
            if (self.pulse[ch_ix].tick_envelope) {
                self.tickPulseEnvelope(ch_ix);
            }
        }

        if (self.ch4.tick_envelope) {
            self.tickNoiseEnvelope();
        }

        if (tick_256hz) {
            for (0..4) |ch_ix| {
                // Length timer
                if (self.length_enable[ch_ix] == 1 and tick_256hz) {
                    if (ch_ix != CH3) {
                        const add_result = @addWithOverflow(self.length_timer[ch_ix], 1);
                        self.length_timer[ch_ix] = add_result[0];
                        if (add_result[1] == 1) {
                            self.ch_on[ch_ix] = 0;
                            self.updateSample(ch_ix, 0, 0);
                        }
                    } else {
                        const add_result = @addWithOverflow(self.ch3.length_timer, 1);
                        self.ch3.length_timer = add_result[0];
                        if (add_result[1] == 1) {
                            self.ch_on[CH3] = 0;
                            self.updateSample(CH3, 0, 0);
                        }
                    }
                }
            }
        }

        // CH1 period sweep
        if (tick_128hz) {
            self.ch1.period_sweep_timer +%= 1;

            if (self.ch1.period_sweep_enabled != 0 and self.ch1.period_sweep_timer == 7) {
                self.ch1.period_sweep_timer = 0;

                const result = calcNewSweepFreqWithOverflowCheck(
                    self.ch1.period_sweep_shadow,
                    self.ch1.period_sweep_dir,
                    self.ch1.period_sweep_individual_step,
                );
                if (result[1] == 1) {
                    self.ch_on[CH1] = 0;
                    self.updateSample(CH1, 0, 0);
                    return;
                } else {
                    self.ch1.period_sweep_shadow = result[0];
                    self.period_setting[CH1] = self.ch1.period_sweep_shadow;
                    self.pulse[CH1].loadTimer(self.period_setting[CH1]);
                    const result2 = calcNewSweepFreqWithOverflowCheck(
                        self.ch1.period_sweep_shadow,
                        self.ch1.period_sweep_dir,
                        self.ch1.period_sweep_individual_step,
                    );
                    if (result2[1] == 1) {
                        self.ch_on[CH1] = 0;
                        self.updateSample(CH1, 0, 0);
                        return;
                    }
                }
            }
        }
    }

    pub fn handleSecondaryDivEvent(self: *Self) void {
        self.run(true);

        if (self.on == 0) {
            return;
        }

        for (0..2) |ch_ix| {
            if (self.ch_on[ch_ix] != 0 and self.pulse[ch_ix].envelope_timer == 0) {
                self.pulse[ch_ix].tick_envelope = self.pulse[ch_ix].envelope_sweep_pace != 0;
                self.pulse[ch_ix].envelope_timer = self.pulse[ch_ix].envelope_sweep_pace;
            }
        }

        if (self.ch_on[CH4] != 0 and self.ch4.envelope_timer == 0) {
            self.ch4.tick_envelope = self.ch4.envelope_sweep_pace != 0;
            self.ch4.envelope_timer = self.ch4.envelope_sweep_pace;
        }
    }

    pub fn readReg(self: *const Self, comptime reg: ApuReg) u8 {
        switch (reg) {
            // Channel 1
            .NR10 => {
                const pace: u8 = self.ch1.period_sweep_pace;
                const dir: u8 = self.ch1.period_sweep_dir;
                const individual_step: u8 = self.ch1.period_sweep_individual_step;
                return (pace << 4) | (dir << 3) | individual_step;
            },
            .NR11 => {
                const wave_duty: u8 = self.pulse[CH1].wave_duty;
                return wave_duty << 6;
            },
            .NR12 => {
                const init_volume: u8 = self.ch_init_volume[CH1];
                const envelope_dir: u8 = self.pulse[CH1].envelope_dir;
                const sweep_pace: u8 = self.pulse[CH1].envelope_sweep_pace;
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR13 => return 0xff,
            .NR14 => {
                const length_enable: u8 = self.length_enable[CH1];
                return length_enable << 6;
            },
            // Channel 2
            .NR21 => {
                const wave_duty: u8 = self.pulse[CH2].wave_duty;
                return wave_duty << 6;
            },
            .NR22 => {
                const init_volume: u8 = self.ch_init_volume[CH2];
                const envelope_dir: u8 = self.pulse[CH2].envelope_dir;
                const sweep_pace: u8 = self.pulse[CH2].envelope_sweep_pace;
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR23 => return 0xff,
            .NR24 => {
                const length_enable: u8 = self.length_enable[CH2];
                return length_enable << 6;
            },
            // Channel 3
            .NR30 => {
                const dac_enable: u8 = self.ch3.dac_enabled;
                return dac_enable << 7;
            },
            .NR31 => return 0xff,
            .NR32 => {
                const output_level_setting: u8 = self.ch3.init_volume;
                return output_level_setting << 5;
            },
            .NR33 => return 0xff,
            .NR34 => {
                const length_enable: u8 = self.length_enable[CH3];
                return length_enable << 6;
            },
            // Channel 4
            .NR41 => return 0xff,
            .NR42 => {
                const init_volume: u8 = self.ch_init_volume[CH4];
                const envelope_dir: u8 = self.ch4.envelope_dir;
                const sweep_pace: u8 = self.ch4.envelope_sweep_pace;
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR43 => {
                const clock_shift: u8 = self.ch4.clock_shift;
                const lfsr_width: u8 = self.ch4.lfsr_width;
                const clock_divider: u8 = self.ch4.clock_divider;
                return (clock_shift << 4) | (lfsr_width << 3) | clock_divider;
            },
            .NR44 => {
                const length_enable: u8 = self.length_enable[CH4];
                return length_enable << 6;
            },
            // Global
            .NR50 => {
                const volume_left: u8 = self.volume_left;
                const volume_right: u8 = self.volume_right;
                return (volume_left << 4) | volume_right;
            },
            .NR51 => {
                var result: u8 = 0;
                for (0..4) |ch_ix| {
                    const left: u8 = self.output_left[ch_ix];
                    const right: u8 = self.output_right[ch_ix];
                    const shift: u3 = @truncate(ch_ix);
                    result |= left << (shift + 4);
                    result |= right << shift;
                }
                return result;
            },
            .NR52 => {
                const apu_on: u8 = self.on;
                var channel_on: u8 = 0;
                for (0..4) |ch_ix| {
                    const on: u8 = self.ch_on[ch_ix];
                    channel_on |= on << @truncate(ch_ix);
                }
                return (apu_on << 7) | channel_on;
            },
        }
    }

    pub fn writeReg(self: *Self, comptime reg: ApuReg, val: u8) void {
        self.run(true);

        switch (reg) {
            // Channel 1
            .NR10 => {
                self.ch1.period_sweep_pace = @truncate((val & 0b0111_0000) >> 4);
                self.ch1.period_sweep_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch1.period_sweep_individual_step = @truncate(val & 0b0000_0111);
            },
            .NR11 => {
                self.pulse[CH1].wave_duty = @truncate((val & 0b1100_0000) >> 6);
                self.init_length_timer[CH1] = @truncate(val & 0b0011_1111);
            },
            .NR12 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch_init_volume[CH1] = @truncate((val & 0b1111_0000) >> 4);
                self.pulse[CH1].envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.pulse[CH1].envelope_sweep_pace = @truncate(val & 0b0000_0111);
                self.pulse[CH1].envelope_timer = self.pulse[CH1].envelope_sweep_pace;
                if (self.ch_init_volume[CH1] == 0 and self.pulse[CH1].envelope_dir == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH1] = 0;
                    self.updateSample(CH1, 0, 0);
                }
            },
            .NR13 => {
                const val_u11: u11 = val;
                self.period_setting[CH1] = (self.period_setting[CH1] & 0b111_0000_0000) | val_u11;

                self.pulse[CH1].loadTimer(self.period_setting[CH1]);
            },
            .NR14 => {
                self.length_enable[CH1] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH1] = (self.period_setting[CH1] & 0b000_1111_1111) | (val_u11 << 8);
                self.pulse[CH1].loadTimer(self.period_setting[CH1]);
                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH1);
                }
            },
            // Channel 2
            .NR21 => {
                self.pulse[CH2].wave_duty = @truncate((val & 0b1100_0000) >> 6);
                self.init_length_timer[CH2] = @truncate(val & 0b0011_1111);
            },
            .NR22 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch_init_volume[CH2] = @truncate((val & 0b1111_0000) >> 4);
                self.pulse[CH2].envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.pulse[CH2].envelope_sweep_pace = @truncate(val & 0b0000_0111);
                self.pulse[CH2].envelope_timer = self.pulse[CH2].envelope_sweep_pace;
                if (self.ch_init_volume[CH2] == 0 and self.pulse[CH2].envelope_dir == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH2] = 0;
                    self.updateSample(CH2, 0, 0);
                }
            },
            .NR23 => {
                const val_u11: u11 = val;
                self.period_setting[CH2] = (self.period_setting[CH2] & 0b111_0000_0000) | val_u11;

                self.pulse[CH2].loadTimer(self.period_setting[CH1]);
            },
            .NR24 => {
                self.length_enable[CH2] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH2] = (self.period_setting[CH2] & 0b000_1111_1111) | (val_u11 << 8);
                self.pulse[CH2].loadTimer(self.period_setting[CH2]);
                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH2);
                }
            },
            // Channel 3
            .NR30 => {
                self.ch3.dac_enabled = @truncate(val >> 7);
                if (self.ch3.dac_enabled == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH3] = 0;
                    self.updateSample(CH3, 0, 0);
                }
            },
            .NR31 => {
                self.ch3.length_timer = val;
            },
            .NR32 => {
                self.ch3.init_volume = @truncate(val >> 5);
            },
            .NR33 => {
                const val_u11: u11 = val;
                self.period_setting[CH3] = (self.period_setting[CH3] & 0b111_0000_0000) | val_u11;

                self.ch3.loadTimer(self.period_setting[CH3]);
            },
            .NR34 => {
                self.length_enable[CH3] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH3] = (self.period_setting[CH3] & 0b000_1111_1111) | (val_u11 << 8);
                self.ch3.loadTimer(self.period_setting[CH3]);
                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH3);
                }
            },
            // Channel 4
            .NR41 => {
                self.init_length_timer[CH4] = @truncate(val);
            },
            .NR42 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch_init_volume[CH4] = @truncate((val & 0b1111_0000) >> 4);
                self.ch4.envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch4.envelope_sweep_pace = @truncate(val & 0b0000_0111);
                self.ch4.envelope_timer = self.ch4.envelope_sweep_pace;
                if (self.ch_init_volume[CH4] == 0 and self.ch4.envelope_dir == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH4] = 0;
                    self.updateSample(CH4, 0, 0);
                }
            },
            .NR43 => {
                self.ch4.clock_shift = @truncate(val >> 4);
                self.ch4.lfsr_width = @truncate(val >> 3);
                self.ch4.clock_divider = @truncate(val);
            },
            .NR44 => {
                self.length_enable[CH4] = @truncate((val & 0b0100_0000) >> 6);

                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH4);
                }
            },
            // Global
            .NR50 => {
                self.volume_left = @truncate(val >> 4);
                self.volume_right = @truncate(val);
            },
            .NR51 => {
                for (0..4) |ch_ix| {
                    const shift: u3 = @truncate(ch_ix);
                    const mask_left = @as(u8, 1) << (shift + 4);
                    self.output_left[ch_ix] = @truncate((val & mask_left) >> (shift + 4));
                    const mask_right = @as(u8, 1) << shift;
                    self.output_right[ch_ix] = @truncate((val & mask_right) >> shift);
                }
            },
            .NR52 => {
                if (val & 0b1000_0000 == 0) {
                    self.turnOff();
                } else {
                    self.turnOn();
                }
            },
        }
    }

    pub fn readWavRam(self: *const Self, ix: usize) u8 {
        std.debug.assert(ix < 16);

        if (self.ch_on[CH3] == 1) {
            // TODO if this is the cycle that CH3 is accessing WAV RAM, allow the read
            return 0xff;
        }

        const wav_ram_ix = ix * 2;
        const upper: u8 = self.ch3.wav_ram[wav_ram_ix];
        const lower: u8 = self.ch3.wav_ram[wav_ram_ix + 1];
        return (upper << 4) | lower;
    }

    pub fn writeWavRam(self: *Self, ix: usize, val: u8) void {
        std.debug.assert(ix < 16);

        if (self.ch_on[CH3] == 1) {
            // TODO if this is the cycle that CH3 is accessing WAV RAM, allow the write
            return;
        }

        const wav_ram_ix = ix * 2;
        self.ch3.wav_ram[wav_ram_ix] = @truncate(val >> 4);
        self.ch3.wav_ram[wav_ram_ix + 1] = @truncate(val);
    }

    fn turnOff(self: *Self) void {
        self.on = 0;

        // TODO
    }

    fn turnOn(self: *Self) void {
        self.on = 1;
    }

    pub fn printState(self: *const Self, writer: anytype) !void {
        try format(writer, "APU is {s}\n", .{if (self.on == 1) "on" else "off"});

        for (0..4) |ch_ix| {
            try format(writer, "CH{} is {s}\n", .{
                ch_ix + 1,
                if (self.ch_on[ch_ix] == 1) "on" else "off",
            });
            try format(writer, "    Current sample: {}\n", .{self.band_limited[ch_ix].buffer[self.band_limited[ch_ix].buffer_ix]});
            if (ch_ix != CH4) {
                try format(writer, "    Next sample in {} APU ticks (sample length: {} APU ticks)\n", .{
                    if (ch_ix < 2) self.pulse[ch_ix].timer else self.ch3.timer,
                    if (ch_ix < 2) ((0b111_1111_1111 - @as(u13, @intCast(self.period_setting[ch_ix]))) << 1) + 1 else (0b111_1111_1111 - @as(u13, @intCast(self.period_setting[CH3]))) + 1,
                });
            }

            try format(writer, "    Pan: L={} R={} ~ {s}\n", .{
                self.output_left[ch_ix],
                self.output_right[ch_ix],
                if (self.output_left[ch_ix] == 1 and self.output_right[ch_ix] == 1) "center" else if (self.output_left[ch_ix] == 1) "left" else if (self.output_right[ch_ix] == 1) "right" else "muted",
            });

            if (ch_ix == CH3) {
                try format(writer, "    Volume: {s}\n", .{
                    switch (self.ch3.volume) {
                        0 => "0% (muted)",
                        1 => "100%",
                        2 => "50%",
                        3 => "25%",
                    },
                });
                try format(writer, "    Wave: ", .{});
                for (0..16) |i| {
                    try format(writer, "{x:0>1}{x:0>1} ", .{ self.ch3.wav_ram[i * 2], self.ch3.wav_ram[i * 2 + 1] });
                }
                try format(writer, "\n", .{});
                try format(writer, "    Current position: {}\n", .{self.ch3.wav_ram_ix});
            } else {
                try format(writer, "    Volume: {}\n", .{self.ch_volume[ch_ix]});
                try format(writer, "    Initial volume: {}\n", .{self.ch_init_volume[ch_ix]});
                const envelope_sweep_pace = if (ch_ix == CH4) self.ch4.envelope_sweep_pace else self.pulse[ch_ix].envelope_sweep_pace;
                try format(writer, "    Envelope: {s}", .{
                    if (envelope_sweep_pace == 0) "disabled\n" else "",
                });
                const envelope_timer = if (ch_ix == CH4) self.ch4.envelope_timer else self.pulse[ch_ix].envelope_timer;
                if (envelope_sweep_pace != 0) {
                    const envelope_dir = if (ch_ix == CH4) self.ch4.envelope_dir else self.pulse[ch_ix].envelope_dir;
                    try format(writer, "{s} every {} ticks, next change in {} ticks\n", .{
                        if (envelope_dir == 1) "increasing" else "decreasing",
                        envelope_sweep_pace,
                        envelope_timer,
                    });
                }
            }

            try format(writer, "    Length timer: {s}", .{
                if (self.length_enable[ch_ix] == 0) "disabled\n" else "",
            });
            if (self.length_enable[ch_ix] == 1) {
                try format(writer, "set to {}; will expire in {} ticks\n", .{
                    self.init_length_timer[ch_ix],
                    0b11_1111 - self.length_timer[ch_ix],
                });
            }

            if (ch_ix == CH1 or ch_ix == CH2) {
                try format(writer, "    Duty cycle: {s}\n", .{
                    switch (self.pulse[ch_ix].wave_duty) {
                        0 => "12.5%",
                        1 => "25%",
                        2 => "50%",
                        3 => "75%",
                    },
                });
                try format(writer, "    Duty step: {}\n", .{self.pulse[ch_ix].duty_step});
            }

            if (ch_ix == CH4) {
                try format(writer, "    Frequency: {} Hz (divider: {}, shift: {})\n", .{
                    if (self.ch4.clock_divider > 0) 262144 / (self.ch4.clock_divider * (@as(u32, 1) << self.ch4.clock_shift)) else (262144 * 2) / (@as(u32, 1) << self.ch4.clock_shift),
                    self.ch4.clock_divider,
                    self.ch4.clock_shift,
                });
                try format(writer, "    LFSR: {b:0>16}\n", .{self.ch4.lfsr});
                try format(writer, "    LFSR width: {}\n", .{if (self.ch4.lfsr_width == 1) @as(usize, 7) else 15});
            } else {
                const period_setting: usize = self.period_setting[ch_ix];
                try format(writer, "    Period setting: ${x} (sample rate: {} Hz, tone: {} Hz)\n", .{
                    self.period_setting[ch_ix],
                    if (ch_ix == CH3) 2097152 / (2048 - period_setting) else 1048576 / (2048 - period_setting),
                    if (ch_ix == CH3) 65536 / (2048 - period_setting) else 131072 / (2048 - period_setting),
                });
                try format(writer, "    Current period value: ${x}\n", .{self.period[ch_ix]});
            }

            if (ch_ix == CH1) {
                try format(writer, "    Period sweep: {s}", .{
                    if (self.ch1.period_sweep_enabled == 0) "disabled\n" else "",
                });
                if (self.ch1.period_sweep_enabled == 1) {
                    try format(writer, "{s} every {} ticks with step {}\n", .{
                        if (self.ch1.period_sweep_dir == 1) "increasing" else "decreasing",
                        self.ch1.period_sweep_pace,
                        self.ch1.period_sweep_individual_step,
                    });
                }
            }
        }
    }
};
