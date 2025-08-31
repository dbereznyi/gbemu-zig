const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const format = std.fmt.format;

const NUM_SAMPLES = 512;

const SAMPLES_CLOCK_DIVIDER: usize = @round(2097152.0 / 48000.0);

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

fn calcNewSweepFreqWithOverflowCheck(
    shadow: u11, 
    dir: u1, 
    individual_step: u3
) struct { u11, u1 } {
    const temp = shadow >> individual_step;
    return if (dir == 0) @addWithOverflow(shadow, temp) else @subWithOverflow(shadow, temp);
}

const CH1 = 0;
const CH2 = 1;
const CH3 = 2;
const CH4 = 3;

const Sample = packed struct {
    left: f32,
    right: f32,

    pub fn add(self: Sample, other: Sample) Sample {
        return .{
            .left = self.left + other.left,
            .right = self.right + other.right,
        };
    }

    pub fn subtract(self: Sample, other: Sample) Sample {
        return .{
            .left = self.left - other.left,
            .right = self.right - other.right,
        };
    }
};

pub const Apu = struct {
    on: u1,
    volume_left: u3,
    volume_right: u3,

    ch_on: [4]u1,
    current_sample: [4]u4,
    output_left: [4]u1,
    output_right: [4]u1,
    length_enable: [4]u1,
    init_length_timer: [4]u6,
    length_timer: [4]u6,
    ch_init_volume: [4]u4,
    ch_volume: [4]u4,
    envelope_timer: [4]u4,
    envelope_dir: [4]u1,
    envelope_sweep_pace: [4]u3,
    period_setting: [4]u11,
    period: [4]u11,

    wave_duty: [2]u2,
    duty_step: [2]u3,

    ch1_period_sweep_pace: u3,
    ch1_period_sweep_dir: u1,
    ch1_period_sweep_individual_step: u3,
    ch1_period_sweep_enabled: u1,
    ch1_period_sweep_timer: u4,
    ch1_period_sweep_shadow: u11,

    ch3_init_length_timer: u8,
    ch3_length_timer: u8,
    ch3_init_volume: u2,
    ch3_volume: u2,
    ch3_dac_enabled: u1,
    ch3_wav_ram_ix: u5,
    ch3_wav_ram: [32]u4,

    ch4_lfsr: u16,
    ch4_lfsr_timer: u32,
    ch4_clock_shift: u4,
    ch4_lfsr_width: u1,
    ch4_clock_divider: u3,

    audio_device: u32,
    ch_samples: [4][]Sample,
    samples: []Sample,
    samples_ix: usize,
    samples_timer: u8,

    div_apu_counter: usize,
    next_lfsr_tick_in: u4,
    is_1mhz_tick: bool,

    files: [4]std.fs.File,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, audio_device: u32) !Self {
        const files = [_]std.fs.File{ 
            try std.fs.cwd().createFile("apu_1.dat", .{}),
            try std.fs.cwd().createFile("apu_2.dat", .{}),
            try std.fs.cwd().createFile("apu_3.dat", .{}),
            try std.fs.cwd().createFile("apu_4.dat", .{}),
        };

        const ch_samples = [_][]Sample{
            try alloc.alloc(Sample, NUM_SAMPLES),
            try alloc.alloc(Sample, NUM_SAMPLES),
            try alloc.alloc(Sample, NUM_SAMPLES),
            try alloc.alloc(Sample, NUM_SAMPLES),
        };

        return .{
            .on = 0,
            .volume_left = 0,
            .volume_right = 0,
            .ch_on = [_]u1{0} ** 4,
            .current_sample = [_]u4{0} ** 4,
            .output_left = [_]u1{0} ** 4,
            .output_right = [_]u1{0} ** 4,
            .length_enable = [_]u1{0} ** 4,
            .init_length_timer = [_]u6{0} ** 4,
            .length_timer = [_]u6{0} ** 4,
            .ch_init_volume = [_]u4{0} ** 4,
            .ch_volume = [_]u4{0} ** 4,
            .envelope_timer = [_]u4{0} ** 4,
            .envelope_dir = [_]u1{0} ** 4,
            .envelope_sweep_pace = [_]u3{0} ** 4,
            .period_setting = [_]u11{0} ** 4,
            .period = [_]u11{0} ** 4,
            .wave_duty = [_]u2{0} ** 2,
            .duty_step = [_]u3{0} ** 2,
            .ch1_period_sweep_pace = 0,
            .ch1_period_sweep_dir = 0,
            .ch1_period_sweep_individual_step = 0,
            .ch1_period_sweep_enabled = 0,
            .ch1_period_sweep_timer = 0,
            .ch1_period_sweep_shadow = 0,
            .ch3_init_length_timer = 0,
            .ch3_length_timer = 0,
            .ch3_init_volume = 0,
            .ch3_volume = 0,
            .ch3_dac_enabled = 0,
            .ch3_wav_ram_ix = 0,
            .ch3_wav_ram = [_]u4{0} ** 32,
            .ch4_lfsr = 0,
            .ch4_lfsr_timer = 0,
            .ch4_clock_shift = 0,
            .ch4_lfsr_width = 0,
            .ch4_clock_divider = 0,
            .audio_device = audio_device,
            .ch_samples = ch_samples,
            .samples = try alloc.alloc(Sample, NUM_SAMPLES),
            .samples_ix = 0,
            .samples_timer = 0,
            .div_apu_counter = 0,
            .next_lfsr_tick_in = 8,
            .is_1mhz_tick = false,
            .files = files,
        };
    }

    fn isDacOn(self: *const Self, ch_ix: usize) bool {
        if (ch_ix == CH3) {
            return self.ch3_dac_enabled;
        } else {
            return self.init_volume[ch_ix] != 0 or self.envelope_dir[ch_ix] != 0;
        }
    }

    fn triggerChannel(self: *Self, ch_ix: usize) void {
        self.ch_on[ch_ix] = 1;

        if (ch_ix == CH3) {
            self.ch3_length_timer = self.ch3_init_length_timer;
            self.ch3_volume = self.ch3_init_volume;
        } else {
            self.length_timer[ch_ix] = self.init_length_timer[ch_ix];
            self.ch_volume[ch_ix] = self.ch_init_volume[ch_ix];
        }

        if (ch_ix == CH4) {
            self.ch4_lfsr = 0;
        } else {
            self.period[ch_ix] = self.period_setting[ch_ix];
        }

        if (ch_ix == CH1) {
            self.ch1_period_sweep_shadow = self.period[ch_ix];
            self.ch1_period_sweep_timer = 0;
            self.ch1_period_sweep_enabled = if (self.ch1_period_sweep_pace != 0 or self.ch1_period_sweep_individual_step != 0) 1 else 0;
            if (self.ch1_period_sweep_individual_step != 0) {
                const result = calcNewSweepFreqWithOverflowCheck(
                    self.ch1_period_sweep_shadow,
                    self.ch1_period_sweep_dir,
                    self.ch1_period_sweep_individual_step,
                );
                if (result[1] == 1) {
                    std.debug.print("freq overflow in trigger, turning off\n", .{});
                    self.ch_on[ch_ix] = 0;
                }
            }
        }
    }

    fn getSample(self: *const Self, ch_ix: usize) Sample {
        if (self.ch_on[ch_ix] == 0) {
            return .{ .left = 0, .right = 0 };
        }

        const val = toAnalog(self.current_sample[ch_ix]);

        //std.debug.print("{} => {}\n", .{self.current_sample[ch_ix], val});
        
        const vol_left = @as(f32, @floatFromInt(self.volume_left)) / @as(f32, @floatFromInt(0b111111));
        const vol_right = @as(f32, @floatFromInt(self.volume_right)) / @as(f32, @floatFromInt(0b111111));

        return .{
            .left = if (self.output_left[ch_ix] == 1) val * vol_left else 0.0,
            .right = if (self.output_right[ch_ix] == 1) val * vol_right else 0.0,
        };
    }

    pub fn mix(self: *Self) void {
        self.samples_timer += 1;
        if (self.samples_timer < SAMPLES_CLOCK_DIVIDER) {
            return;
        }
        self.samples_timer = 0;

        for (0..4) |ch_ix| {
            self.ch_samples[ch_ix][self.samples_ix] = self.getSample(ch_ix);
        }
        self.samples_ix += 1;

        if (self.samples_ix >= NUM_SAMPLES) {
            for (0..NUM_SAMPLES) |i| {
                var sample = Sample{ .left = 0, .right = 0 };
                for (0..4) |ch_ix| {
                    sample = sample.add(self.ch_samples[ch_ix][i]);
                }
                self.samples[i] = sample;
            }

            const queue_result = c.SDL_QueueAudio(
                self.audio_device,
                @ptrCast(self.samples),
                @intCast(NUM_SAMPLES * @sizeOf(Sample)),
            );
            if (queue_result != 0) {
                std.debug.panic(
                    "SDL_QueueAudio failed with error: {s}\n",
                    .{c.SDL_GetError()},
                );
            }
            
            if (true) {
                for (0..4) |i| {
                    _ = self.files[i].write(
                        std.mem.sliceAsBytes(self.ch_samples[i][0..self.samples_ix])
                    ) catch @panic("failed to write to file");
                }
            }

            //_ = self.file.write(std.mem.sliceAsBytes(self.samples[0..self.samples_ix])) catch @panic("failed to write to file");

            self.samples_ix = 0;
        }
    }

    pub fn step(self: *Self, div_apu_occurred: bool) void {
        if (div_apu_occurred) {
            self.div_apu_counter += 1;
        }
        const tick_256hz = self.div_apu_counter / 2 > 0;
        const tick_128hz = self.div_apu_counter / 4 > 0;
        const tick_64hz = self.div_apu_counter == 8;
        if (self.div_apu_counter == 8) {
            self.div_apu_counter = 0;
        }
        defer self.is_1mhz_tick = !self.is_1mhz_tick;
        defer {
            // TODO there is a bug where this underflows somehow.
            self.next_lfsr_tick_in -|= 1;
        }

        // CH1 period sweep
        if (self.ch1_period_sweep_enabled != 0 and tick_128hz) {
            const result = calcNewSweepFreqWithOverflowCheck(
                self.ch1_period_sweep_shadow,
                self.ch1_period_sweep_dir,
                self.ch1_period_sweep_individual_step,
            );
            if (result[1] == 1) {
                //std.debug.print("freq overflow in step, turning off\n", .{});
                self.ch_on[CH1] = 0;
                return;
            } else {
                self.ch1_period_sweep_shadow = result[0];
                self.period[CH1] = self.ch1_period_sweep_shadow;
                const result2 = calcNewSweepFreqWithOverflowCheck(
                    self.ch1_period_sweep_shadow,
                    self.ch1_period_sweep_dir,
                    self.ch1_period_sweep_individual_step,
                );
                if (result2[1] == 1) {
                    std.debug.print("freq overflow in step (check #2), turning off\n", .{});
                    self.ch_on[CH1] = 0;
                    return;
                }
            }
        }

        for (0..4) |ch_ix| {
            if (self.length_enable[ch_ix] == 1 and tick_256hz) {
                const add_result = @addWithOverflow(self.length_timer[ch_ix], 1);
                self.length_timer[ch_ix] = add_result[0];
                if (add_result[1] == 1) {
                    //std.debug.print("CH{}: length timer expired, turning off\n", .{ch_ix});
                    self.ch_on[ch_ix] = 0;
                }
            }

            if (ch_ix != CH3 and self.envelope_sweep_pace[ch_ix] != 0 and tick_64hz) {
                self.envelope_timer[ch_ix] += 1;
                if (self.envelope_timer[ch_ix] >= self.envelope_sweep_pace[ch_ix]) {
                    self.envelope_timer[ch_ix] = 0;
                    if (self.envelope_dir[ch_ix] == 1) {
                        self.ch_volume[ch_ix] +|= 1;
                    } else {
                        //std.debug.print("CH{}: decrementing volume ({} -> {})\n", .{ ch_ix, self.ch_volume[ch_ix], self.ch_volume[ch_ix] -| 1 });
                        self.ch_volume[ch_ix] -|= 1;
                    }
                }
            }
        }

        // Pulse channels
        if (self.is_1mhz_tick) {
            for (0..2) |ch_ix| {
                const period_inc = @addWithOverflow(self.period[ch_ix], 1);
                self.period[ch_ix] = period_inc[0];
                if (period_inc[1] == 1) {
                    self.period[ch_ix] = self.period_setting[ch_ix];
                    self.duty_step[ch_ix] +%= 1;
                }
                self.current_sample[ch_ix] = WAVEFORMS[self.wave_duty[ch_ix]][self.duty_step[ch_ix]] * self.ch_volume[ch_ix];
            }
        }

        // Wave channel
        {
            const period_inc = @addWithOverflow(self.period[CH3], 1);
            self.period[CH3] = period_inc[0];
            if (period_inc[1] == 1) {
                self.period[CH3] = self.period_setting[CH3];
                self.ch3_wav_ram_ix +%= 1;
            }
            const val = self.ch3_wav_ram[self.ch3_wav_ram_ix];
            self.current_sample[CH3] = switch (self.ch3_volume) {
                0 => 0,
                1 => val,
                2 => val >> 1,
                3 => val >> 2,
            };
        }

        // Noise channel
        if (self.next_lfsr_tick_in == 0) {
            self.next_lfsr_tick_in = 8;

            self.ch4_lfsr_timer += 1;
            const divider: u32 = self.ch4_clock_divider;
            const lfsr_timer_max: u32 =
                if (divider > 0) divider * (@as(u32, 1) << self.ch4_clock_shift)
                else (@as(u32, 1) << (self.ch4_clock_shift -| 1));
            if (self.ch4_lfsr_timer >= lfsr_timer_max) {
                self.ch4_lfsr_timer = 0;

                const next_lfsr_bit = 0x0001 & (~(self.ch4_lfsr & 0x0001) ^ ((self.ch4_lfsr & 0x0002) >> 1));
                self.ch4_lfsr = (self.ch4_lfsr & 0x7fff) | (next_lfsr_bit << 15);
                if (self.ch4_lfsr_width == 1) {
                    self.ch4_lfsr = (self.ch4_lfsr & 0xff7f) | (next_lfsr_bit << 7);
                }
                const bit_0 = self.ch4_lfsr & 0x0001;
                self.ch4_lfsr >>= 1;
                self.current_sample[CH4] = if (bit_0 == 0) 0 else self.ch_volume[CH4];
            }
        }
    }

    pub fn readReg(self: *const Self, comptime reg: ApuReg) u8 {
        switch (reg) {
            // Channel 1
            .NR10 => {
                const pace: u8 = self.ch1_period_sweep_pace;
                const dir: u8 = self.ch1_period_sweep_dir;
                const individual_step: u8 = self.ch1_period_sweep_individual_step;
                return (pace << 4) | (dir << 3) | individual_step;
            },
            .NR11 => {
                const wave_duty: u8 = self.wave_duty[CH1];
                return wave_duty << 6;
            },
            .NR12 => {
                const init_volume: u8 = self.ch_init_volume[CH1];
                const envelope_dir: u8 = self.envelope_dir[CH1];
                const sweep_pace: u8 = self.envelope_sweep_pace[CH1];
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR13 => return 0xff,
            .NR14 => {
                const length_enable: u8 = self.length_enable[CH1];
                return length_enable << 6;
            },
            // Channel 2
            .NR21 => {
                const wave_duty: u8 = self.wave_duty[CH2];
                return wave_duty << 6;
            },
            .NR22 => {
                const init_volume: u8 = self.ch_init_volume[CH2];
                const envelope_dir: u8 = self.envelope_dir[CH2];
                const sweep_pace: u8 = self.envelope_sweep_pace[CH2];
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR23 => return 0xff,
            .NR24 => {
                const length_enable: u8 = self.length_enable[CH2];
                return length_enable << 6;
            },
            // Channel 3
            .NR30 => {
                const dac_enable: u8 = self.ch3_dac_enabled;
                return dac_enable << 7;
            },
            .NR31 => return 0xff,
            .NR32 => {
                const output_level_setting: u8 = self.ch3_init_volume;
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
                const envelope_dir: u8 = self.envelope_dir[CH4];
                const sweep_pace: u8 = self.envelope_sweep_pace[CH4];
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR43 => {
                const clock_shift: u8 = self.ch4_clock_shift;
                const lfsr_width: u8 = self.ch4_lfsr_width;
                const clock_divider: u8 = self.ch4_clock_divider;
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
        switch (reg) {
            // Channel 1
            .NR10 => {
                self.ch1_period_sweep_pace = @truncate((val & 0b0111_0000) >> 4);
                self.ch1_period_sweep_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch1_period_sweep_individual_step = @truncate(val & 0b0000_0111);
            },
            .NR11 => {
                self.wave_duty[CH1] = @truncate((val & 0b1100_0000) >> 6);
                self.init_length_timer[CH1] = @truncate(val & 0b0011_1111);
            },
            .NR12 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch_init_volume[CH1] = @truncate((val & 0b1111_0000) >> 4);
                self.envelope_dir[CH1] = @truncate((val & 0b0000_1000) >> 3);
                self.envelope_sweep_pace[CH1] = @truncate(val & 0b0000_0111);
                if (self.ch_init_volume[CH1] == 0 and self.envelope_dir[CH1] == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH1] = 0;
                }
            },
            .NR13 => {
                const val_u11: u11 = val;
                self.period_setting[CH1] = (self.period_setting[CH1] & 0b111_0000_0000) | val_u11;
            },
            .NR14 => {
                self.length_enable[CH1] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH1] = (self.period_setting[CH1] & 0b000_1111_1111) | (val_u11 << 8);
                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH1);
                }
            },
            // Channel 2
            .NR21 => {
                self.wave_duty[CH2] = @truncate((val & 0b1100_0000) >> 6);
                self.init_length_timer[CH2] = @truncate(val & 0b0011_1111);
            },
            .NR22 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch_init_volume[CH2] = @truncate((val & 0b1111_0000) >> 4);
                self.envelope_dir[CH2] = @truncate((val & 0b0000_1000) >> 3);
                self.envelope_sweep_pace[CH2] = @truncate(val & 0b0000_0111);
                if (self.ch_init_volume[CH2] == 0 and self.envelope_dir[CH2] == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH2] = 0;
                }
            },
            .NR23 => {
                const val_u11: u11 = val;
                self.period_setting[CH2] = (self.period_setting[CH2] & 0b111_0000_0000) | val_u11;
            },
            .NR24 => {
                self.length_enable[CH2] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH2] = (self.period_setting[CH2] & 0b000_1111_1111) | (val_u11 << 8);
                if (val & 0b1000_0000 > 0) {
                    self.triggerChannel(CH2);
                }
            },
            // Channel 3
            .NR30 => {
                self.ch3_dac_enabled = @truncate(val >> 7);
                if (self.ch3_dac_enabled == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH3] = 0;
                }
            },
            .NR31 => {
                self.ch3_length_timer = val;
            },
            .NR32 => {
                self.ch3_init_volume = @truncate(val >> 5);
            },
            .NR33 => {
                const val_u11: u11 = val;
                self.period_setting[CH3] = (self.period_setting[CH3] & 0b111_0000_0000) | val_u11;
            },
            .NR34 => {
                self.length_enable[CH3] = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.period_setting[CH3] = (self.period_setting[CH3] & 0b000_1111_1111) | (val_u11 << 8);
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
                self.envelope_dir[CH4] = @truncate((val & 0b0000_1000) >> 3);
                self.envelope_sweep_pace[CH4] = @truncate(val & 0b0000_0111);
                if (self.ch_init_volume[CH4] == 0 and self.envelope_dir[CH4] == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch_on[CH4] = 0;
                }
            },
            .NR43 => {
                self.ch4_clock_shift = @truncate(val >> 4);
                self.ch4_lfsr_width = @truncate(val >> 3);
                self.ch4_clock_divider = @truncate(val);
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
        const upper: u8 = self.ch3_wav_ram[wav_ram_ix];
        const lower: u8 = self.ch3_wav_ram[wav_ram_ix + 1];
        return (upper << 4) | lower;
    }

    pub fn writeWavRam(self: *Self, ix: usize, val: u8) void {
        std.debug.assert(ix < 16);

        if (self.ch_on[CH3] == 1) {
            // TODO if this is the cycle that CH3 is accessing WAV RAM, allow the write
            return;
        }

        const wav_ram_ix = ix * 2;
        self.ch3_wav_ram[wav_ram_ix] = @truncate(val >> 4);
        self.ch3_wav_ram[wav_ram_ix + 1] = @truncate(val);
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
        //try format(writer, "Next envelope sweep tick in: {}\n", .{self.next_envelope_sweep_tick_in});
        //try format(writer, "Next length timer tick in: {}\n", .{self.next_tick_256hz_in});
        //try format(writer, "Next period sweep tick in: {}\n", .{self.next_tick_128hz_in});
        for (0..4) |ch_ix| {
            try format(writer, "CH{} is {s}\n", .{
                ch_ix + 1,
                if (self.ch_on[ch_ix] == 1) "on" else "off",
            });
            try format(writer, "    Current sample: {}\n", .{self.current_sample[ch_ix]});

            try format(writer, "    Pan: L={} R={} ~ {s}\n", .{
                self.output_left[ch_ix],
                self.output_right[ch_ix],
                if (self.output_left[ch_ix] == 1 and self.output_right[ch_ix] == 1) "center" else if (self.output_left[ch_ix] == 1) "left" else if (self.output_right[ch_ix] == 1) "right" else "muted",
            });

            if (ch_ix == CH3) {
                try format(writer, "    Volume: {s}\n", .{
                    switch (self.ch3_volume) {
                        0 => "0% (muted)",
                        1 => "100%",
                        2 => "50%",
                        3 => "25%",
                    },
                });
                try format(writer, "    Wave: ", .{});
                for (0..16) |i| {
                    try format(writer, "{x:0>1}{x:0>1} ", .{ self.ch3_wav_ram[i * 2], self.ch3_wav_ram[i * 2 + 1] });
                }
                try format(writer, "\n", .{});
                try format(writer, "    Current position: {}\n", .{self.ch3_wav_ram_ix});
            } else {
                try format(writer, "    Volume: {}\n", .{self.ch_volume[ch_ix]});
                try format(writer, "    Initial volume: {}\n", .{self.ch_init_volume[ch_ix]});
                try format(writer, "    Envelope: {s}", .{
                    if (self.envelope_sweep_pace[ch_ix] == 0) "disabled\n" else "",
                });
                if (self.envelope_sweep_pace[ch_ix] != 0) {
                    try format(writer, "{s} every {} ticks\n", .{
                        if (self.envelope_dir[ch_ix] == 1) "increasing" else "decreasing",
                        self.envelope_sweep_pace[ch_ix],
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
                    switch (self.wave_duty[ch_ix]) {
                        0 => "12.5%",
                        1 => "25%",
                        2 => "50%",
                        3 => "75%",
                    },
                });
                try format(writer, "    Duty step: {}\n", .{self.duty_step[ch_ix]});
            }

            if (ch_ix == CH4) {
                try format(writer, "    Frequency: {} Hz (divider: {}, shift: {})\n", .{
                    if (self.ch4_clock_divider > 0) 262144 / (self.ch4_clock_divider * (@as(u32, 1) << self.ch4_clock_shift)) else (262144 * 2) / (@as(u32, 1) << self.ch4_clock_shift),
                    self.ch4_clock_divider,
                    self.ch4_clock_shift,
                });
                try format(writer, "    LFSR: {b:0>16}\n", .{self.ch4_lfsr});
                try format(writer, "    LFSR width: {}\n", .{if (self.ch4_lfsr_width == 1) @as(usize, 7) else 15});
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
                    if (self.ch1_period_sweep_enabled == 0) "disabled\n" else "",
                });
                if (self.ch1_period_sweep_enabled == 1) {
                    try format(writer, "{s} every {} ticks with step {}\n", .{
                        if (self.ch1_period_sweep_dir == 1) "increasing" else "decreasing",
                        self.ch1_period_sweep_pace,
                        self.ch1_period_sweep_individual_step,
                    });
                }
            }
        }

        // try format(writer, "samples_ix={}\n", .{self.samples_ix});
        // try format(writer, "Samples: ", .{});
        // for (0..self.samples_ix) |i| {
        //     //try format(writer, "{},{} ", .{ self.samples[i].left, self.samples[i].right });
        //     try format(writer, "{} ", .{ self.samples[i].left });
        // }
        // try format(writer, "\n", .{});
    }
};
