const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const format = std.fmt.format;

const NUM_SAMPLES = 2048;
// APU is clocked at 1048576 Hz, but audio device expects samples at 44100 Hz.
// Therefore, we divide the clockrate by 24 to get roughly 44100 Hz.
const SAMPLES_CLOCK_DIVIDER = 24;

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

pub const Apu = struct {
    on: u1,

    ch1: Ch1,
    ch2: Ch2,

    audio_device: u32,
    samples: []f32,
    samples_ix: usize,
    samples_timer: u8,

    // number of DIV_APU ticks until an event
    next_envelope_sweep_tick_in: u4,
    next_length_tick_in: u3,
    next_period_sweep_tick_in: u3,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, audio_device: u32) !Self {
        return .{
            .on = 0,
            .ch1 = Ch1.init(),
            .ch2 = Ch2.init(),
            .audio_device = audio_device,
            .samples = try alloc.alloc(f32, NUM_SAMPLES * 2),
            .samples_ix = 0,
            .samples_timer = 0,
            .next_envelope_sweep_tick_in = 8,
            .next_length_tick_in = 2,
            .next_period_sweep_tick_in = 4,
        };
    }

    pub fn printState(self: *const Self, writer: anytype) !void {
        try format(writer, "APU is {s}\n", .{if (self.on == 1) "on" else "off"});
        try format(writer, "samples_ix={}\n", .{self.samples_ix});
        try format(writer, "Next envelope sweep tick in: {}\n", .{self.next_envelope_sweep_tick_in});
        try format(writer, "Next length timer tick in: {}\n", .{self.next_length_tick_in});
        try format(writer, "Next period sweep tick in: {}\n", .{self.next_period_sweep_tick_in});
        try self.ch1.printState(writer);
        try self.ch2.printState(writer);
    }

    pub fn mix(self: *Self) void {
        const ch1_output = self.ch1.getOutput();
        const ch2_output = self.ch2.getOutput();

        const left = ch1_output.left + ch2_output.left;
        const right = ch1_output.right + ch2_output.right;

        self.samples_timer += 1;
        if (self.samples_timer < SAMPLES_CLOCK_DIVIDER) {
            return;
        }
        self.samples_timer = 0;

        self.samples[self.samples_ix] = left;
        self.samples_ix += 1;
        self.samples[self.samples_ix] = right;
        self.samples_ix += 1;

        if (self.samples_ix >= NUM_SAMPLES * 2) {
            _ = c.SDL_QueueAudio(self.audio_device, @ptrCast(self.samples), NUM_SAMPLES * 2 * 4);
            c.SDL_PauseAudioDevice(self.audio_device, 0);
            self.samples_ix = 0;
        }
    }

    pub fn step(self: *Self, div_apu_occurred: bool) void {
        if (div_apu_occurred) {
            self.next_envelope_sweep_tick_in -= 1;
            self.next_length_tick_in -= 1;
            self.next_period_sweep_tick_in -= 1;
        }

        self.ch1.step(
            self.next_period_sweep_tick_in == 0,
            self.next_envelope_sweep_tick_in == 0,
            self.next_length_tick_in == 0,
        );
        self.ch2.step(
            self.next_envelope_sweep_tick_in == 0,
            self.next_length_tick_in == 0,
        );

        if (self.next_envelope_sweep_tick_in == 0) {
            self.next_envelope_sweep_tick_in = 8;
        }
        if (self.next_length_tick_in == 0) {
            self.next_length_tick_in = 2;
        }
        if (self.next_period_sweep_tick_in == 0) {
            self.next_period_sweep_tick_in = 4;
        }
    }

    pub fn readReg(self: *const Self, comptime reg: ApuReg) u8 {
        switch (reg) {
            // Channel 1
            .NR10 => {
                const pace: u8 = self.ch1.sweep_pace;
                const dir: u8 = self.ch1.sweep_dir;
                const individual_step: u8 = self.ch1.sweep_individual_step;
                return (pace << 4) | (dir << 3) | individual_step;
            },
            .NR11 => {
                const wave_duty: u8 = self.ch1.wave_duty;
                const init_length_timer: u8 = self.ch1.init_length_timer;
                return (wave_duty << 6) | init_length_timer;
            },
            .NR12 => {
                const init_volume: u8 = self.ch1.init_volume;
                const envelope_dir: u8 = self.ch1.envelope_dir;
                const sweep_pace: u8 = self.ch1.envelope_sweep_pace;
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR13 => {
                const period_low: u8 = @truncate(self.ch1.period_setting);
                return period_low;
            },
            .NR14 => {
                const length_enable: u8 = self.ch1.length_enable;
                const period_high: u8 = @truncate(self.ch1.period_setting >> 8);
                return (length_enable << 6) | period_high;
            },
            // Channel 2
            .NR21 => {
                const wave_duty: u8 = self.ch2.wave_duty;
                const init_length_timer: u8 = self.ch2.init_length_timer;
                return (wave_duty << 6) | init_length_timer;
            },
            .NR22 => {
                const init_volume: u8 = self.ch2.init_volume;
                const envelope_dir: u8 = self.ch2.envelope_dir;
                const sweep_pace: u8 = self.ch2.envelope_sweep_pace;
                return (init_volume << 4) | (envelope_dir << 3) | sweep_pace;
            },
            .NR23 => {
                const period_low: u8 = @truncate(self.ch2.period_setting);
                return period_low;
            },
            .NR24 => {
                const length_enable: u8 = self.ch2.length_enable;
                const period_high: u8 = @truncate(self.ch2.period_setting >> 8);
                return (length_enable << 6) | period_high;
            },
            .NR30 => return 0,
            .NR31 => return 0,
            .NR32 => return 0,
            .NR33 => return 0,
            .NR34 => return 0,
            .NR41 => return 0,
            .NR42 => return 0,
            .NR43 => return 0,
            .NR44 => return 0,
            // Global
            .NR50 => return 0,
            .NR51 => {
                const ch1_right: u8 = self.ch1.mix_right;
                const ch1_left: u8 = self.ch1.mix_left;
                return (ch1_left << 4) | ch1_right;
            },
            .NR52 => {
                const apu_on: u8 = self.on;
                const ch1_on: u8 = self.ch1.on;
                return (apu_on << 7) | ch1_on;
            },
        }
    }

    pub fn writeReg(self: *Self, comptime reg: ApuReg, val: u8) void {
        switch (reg) {
            // Channel 1
            .NR10 => {
                self.ch1.sweep_pace = @truncate((val & 0b0111_0000) >> 4);
                self.ch1.sweep_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch1.sweep_individual_step = @truncate(val & 0b0000_0111);
            },
            .NR11 => {
                self.ch1.wave_duty = @truncate((val & 0b1100_0000) >> 6);
                self.ch1.init_length_timer = @truncate(val & 0b0011_1111);
            },
            .NR12 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch1.init_volume = @truncate((val & 0b1111_0000) >> 4);
                self.ch1.envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch1.envelope_sweep_pace = @truncate(val & 0b0000_0111);
                if (self.ch1.init_volume == 0 and self.ch1.envelope_dir == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch1.on = 0;
                }
            },
            .NR13 => {
                const val_u11: u11 = val;
                self.ch1.period_setting = (self.ch1.period_setting & 0b111_0000_0000) | val_u11;
            },
            .NR14 => {
                self.ch1.length_enable = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.ch1.period_setting = (self.ch1.period_setting & 0b000_1111_1111) | (val_u11 << 8);
                if (val & 0b1000_0000 > 0) {
                    self.ch1.trigger();
                }
            },
            // Channel 2
            .NR21 => {
                self.ch2.wave_duty = @truncate((val & 0b1100_0000) >> 6);
                self.ch2.init_length_timer = @truncate(val & 0b0011_1111);
            },
            .NR22 => {
                // TODO writes should not take effect until retrigger if the channel is already on
                self.ch2.init_volume = @truncate((val & 0b1111_0000) >> 4);
                self.ch2.envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch2.envelope_sweep_pace = @truncate(val & 0b0000_0111);
                if (self.ch2.init_volume == 0 and self.ch2.envelope_dir == 0) {
                    // DAC turned off, so turn the channel off as well
                    self.ch2.on = 0;
                }
            },
            .NR23 => {
                const val_u11: u11 = val;
                self.ch2.period_setting = (self.ch2.period_setting & 0b111_0000_0000) | val_u11;
            },
            .NR24 => {
                self.ch2.length_enable = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.ch2.period_setting = (self.ch2.period_setting & 0b000_1111_1111) | (val_u11 << 8);
                if (val & 0b1000_0000 > 0) {
                    self.ch2.trigger();
                }
            },
            .NR30 => {},
            .NR31 => {},
            .NR32 => {},
            .NR33 => {},
            .NR34 => {},
            .NR41 => {},
            .NR42 => {},
            .NR43 => {},
            .NR44 => {},
            // Global
            .NR50 => {},
            .NR51 => {},
            .NR52 => {
                if (val & 0b1000_0000 == 0) {
                    self.turnOff();
                } else {
                    self.turnOn();
                }
            },
        }
    }

    fn turnOff(self: *Self) void {
        self.on = 0;
        self.ch1.clearRegisters();
    }

    fn turnOn(self: *Self) void {
        self.on = 1;
    }
};

const ChannelOutput = struct {
    left: f32,
    right: f32,
};

const WAVEFORMS = [4][8]u1{
    [_]u1{ 1, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 0, 0, 0 },
    [_]u1{ 1, 0, 0, 0, 0, 0, 0, 1 },
};

pub const Ch1 = struct {
    // Internal
    on: u1,
    value: u4,
    volume: u4,
    length_timer: u6,
    envelope_timer: u3,
    period: u11,
    mix_left: u1,
    mix_right: u1,

    // NR10
    sweep_pace: u3,
    sweep_dir: u1,
    sweep_individual_step: u3,
    // NR10 (internal)
    sweep_enabled: u1,
    sweep_timer: u4,
    sweep_shadow: u11,

    // NR11
    wave_duty: u2,
    init_length_timer: u6,
    // NR11 (internal)
    duty_step: u3,

    // NR12
    init_volume: u4,
    envelope_dir: u1,
    envelope_sweep_pace: u3,

    // NR13 + NR14
    period_setting: u11,
    length_enable: u1,

    const Self = @This();

    pub fn init() Self {
        return .{
            .on = 0,
            .value = 0,
            .volume = 0,
            .length_timer = 0,
            .envelope_timer = 0,
            .period = 0,
            .mix_left = 0,
            .mix_right = 0,
            .sweep_pace = 0,
            .sweep_dir = 0,
            .sweep_individual_step = 0,
            .sweep_enabled = 0,
            .sweep_timer = 0,
            .sweep_shadow = 0,
            .wave_duty = 0,
            .init_length_timer = 0,
            .duty_step = 0,
            .init_volume = 0,
            .envelope_dir = 0,
            .envelope_sweep_pace = 0,
            .period_setting = 0,
            .length_enable = 0,
        };
    }

    pub fn getOutput(self: *const Self) ChannelOutput {
        const output = if (self.on == 1) toAnalog(self.value) else 0.0;
        return .{
            .left = if (self.mix_left == 0) output else 0.0,
            .right = if (self.mix_right == 0) output else 0.0,
        };
    }

    pub fn step(
        self: *Self,
        period_sweep_tick: bool,
        envelope_sweep_tick: bool,
        length_tick: bool,
    ) void {
        if (self.on == 0) {
            return;
        }

        if (self.sweep_enabled != 0 and period_sweep_tick) {
            const result = calcNewSweepFreqWithOverflowCheck(
                self.sweep_shadow,
                self.sweep_dir,
                self.sweep_individual_step,
            );
            if (result[1] == 1) {
                std.debug.print("freq overflow in step, turning off\n", .{});
                self.on = 0;
                return;
            } else {
                self.sweep_shadow = result[0];
                self.period = self.sweep_shadow;
                const result2 = calcNewSweepFreqWithOverflowCheck(
                    self.sweep_shadow,
                    self.sweep_dir,
                    self.sweep_individual_step,
                );
                if (result2[1] == 1) {
                    std.debug.print("freq overflow in step (check #2), turning off\n", .{});
                    self.on = 0;
                    return;
                }
            }
        }

        if (self.envelope_sweep_pace != 0 and envelope_sweep_tick) {
            self.envelope_timer += 1;
            if (self.envelope_timer == self.envelope_sweep_pace) {
                self.envelope_timer = 0;
                if (self.envelope_dir == 1) {
                    self.volume +|= 1;
                } else {
                    self.volume -|= 1;
                }
            }
        }

        if (self.length_enable == 1 and length_tick) {
            self.length_timer +%= 1;
            if (self.length_timer == 0) {
                std.debug.print("CH1: length timer expired, turning off\n", .{});
                self.on = 0;
                return;
            }
        }

        const period_increment_result = @addWithOverflow(self.period, 1);
        self.period = period_increment_result[0];
        if (period_increment_result[1] == 1) {
            self.duty_step +%= 1;
            self.period = self.period_setting;
        }

        const new_value_u4: u4 = WAVEFORMS[self.wave_duty][self.duty_step];
        self.value = if (new_value_u4 == 0) 0 else new_value_u4 +| self.volume;
    }

    pub fn isDacOn(self: *const Self) bool {
        return self.init_volume != 0 or self.envelope_dir != 0;
    }

    pub fn trigger(self: *Self) void {
        self.on = 1;
        if (self.length_timer == 0) {
            self.length_timer = self.init_length_timer;
        }
        self.envelope_timer = 0;
        self.period = self.period_setting;
        self.volume = self.init_volume;

        self.sweep_shadow = self.period;
        self.sweep_timer = 0;
        self.sweep_enabled = if (self.sweep_pace != 0 or self.sweep_individual_step != 0) 1 else 0;
        if (self.sweep_individual_step != 0) {
            const result = calcNewSweepFreqWithOverflowCheck(
                self.sweep_shadow,
                self.sweep_dir,
                self.sweep_individual_step,
            );
            if (result[1] == 1) {
                std.debug.print("freq overflow in trigger, turning off\n", .{});
                self.on = 0;
            }
        }
    }

    pub fn clearRegisters(self: *Self) void {
        self.on = 0;
        self.value = 0;
        self.volume = 0;

        self.sweep_pace = 0;
        self.sweep_dir = 0;
        self.sweep_individual_step = 0;

        self.wave_duty = 0;
        self.init_length_timer = 0;

        self.init_volume = 0;
        self.envelope_dir = 0;
        self.envelope_sweep_pace = 0;

        self.period_setting = 0;
        self.length_enable = 0;
    }

    fn calcNewSweepFreqWithOverflowCheck(shadow: u11, dir: u1, individual_step: u3) struct { u11, u1 } {
        const temp = shadow >> individual_step;
        return if (dir == 0) @addWithOverflow(shadow, temp) else @subWithOverflow(shadow, temp);
    }

    pub fn printState(self: *const Self, writer: anytype) !void {
        try format(writer, "CH1 is {s} and DAC is {s}\n", .{
            if (self.on == 1) "on" else "off",
            if (self.isDacOn()) "on" else "off",
        });
        try format(writer, "    Current sample: ${x}\n", .{self.value});
        try format(writer, "    Volume: {}\n", .{self.volume});
        try format(writer, "    Pan: {s}\n", .{if (self.mix_left == 1 and self.mix_right == 1) "center" else if (self.mix_left == 1) "left" else "right"});
        try format(writer, "    Duty cycle: {s}\n", .{
            switch (self.wave_duty) {
                0 => "12.5%",
                1 => "25%",
                2 => "50%",
                3 => "75%",
            },
        });
        try format(writer, "    Duty step: {}\n", .{self.duty_step});
        try format(writer, "    Length timer: {s}", .{
            if (self.length_enable == 0) "disabled\n" else "",
        });
        if (self.length_enable == 1) {
            try format(writer, "set to {}; will expire in {} ticks\n", .{
                self.init_length_timer,
                0b11_1111 - self.length_timer,
            });
        }
        try format(writer, "    Initial volume: {}\n", .{self.init_volume});
        try format(writer, "    Envelope: {s}", .{
            if (self.envelope_sweep_pace == 0) "disabled\n" else "",
        });
        if (self.envelope_sweep_pace != 0) {
            try format(writer, "{s} every {} ticks\n", .{
                if (self.envelope_dir == 1) "increasing" else "decreasing",
                self.envelope_sweep_pace,
            });
        }
        try format(writer, "    Period setting: ${x}\n", .{self.period_setting});
        try format(writer, "    Current period value: ${x}\n", .{self.period});
        try format(writer, "    Period sweep: {s}", .{
            if (self.sweep_enabled == 0) "disabled\n" else "",
        });
        if (self.sweep_enabled == 1) {
            try format(writer, "{s} every {} ticks with step {}\n", .{
                if (self.sweep_dir == 1) "increasing" else "decreasing",
                self.sweep_pace,
                self.sweep_individual_step,
            });
        }
    }
};

pub const Ch2 = struct {
    // Internal
    on: u1,
    value: u4,
    volume: u4,
    length_timer: u6,
    envelope_timer: u3,
    period: u11,
    mix_left: u1,
    mix_right: u1,

    // NR21
    wave_duty: u2,
    init_length_timer: u6,
    // NR21 (internal)
    duty_step: u3,

    // NR22
    init_volume: u4,
    envelope_dir: u1,
    envelope_sweep_pace: u3,

    // NR23 + NR24
    period_setting: u11,
    length_enable: u1,

    const Self = @This();

    pub fn init() Self {
        return .{
            .on = 0,
            .value = 0,
            .volume = 0,
            .length_timer = 0,
            .envelope_timer = 0,
            .period = 0,
            .mix_left = 0,
            .mix_right = 0,
            .wave_duty = 0,
            .init_length_timer = 0,
            .duty_step = 0,
            .init_volume = 0,
            .envelope_dir = 0,
            .envelope_sweep_pace = 0,
            .period_setting = 0,
            .length_enable = 0,
        };
    }

    pub fn getOutput(self: *const Self) ChannelOutput {
        const output = if (self.on == 1) toAnalog(self.value) else 0.0;
        return .{
            .left = if (self.mix_left == 0) output else 0.0,
            .right = if (self.mix_right == 0) output else 0.0,
        };
    }

    pub fn step(
        self: *Self,
        envelope_sweep_tick: bool,
        length_tick: bool,
    ) void {
        if (self.on == 0) {
            return;
        }

        if (self.envelope_sweep_pace != 0 and envelope_sweep_tick) {
            self.envelope_timer += 1;
            if (self.envelope_timer == self.envelope_sweep_pace) {
                self.envelope_timer = 0;
                if (self.envelope_dir == 1) {
                    self.volume +|= 1;
                } else {
                    self.volume -|= 1;
                }
            }
        }

        if (self.length_enable == 1 and length_tick) {
            self.length_timer +%= 1;
            if (self.length_timer == 0) {
                std.debug.print("CH2: length timer expired, turning off\n", .{});
                self.on = 0;
                return;
            }
        }

        const period_increment_result = @addWithOverflow(self.period, 1);
        self.period = period_increment_result[0];
        if (period_increment_result[1] == 1) {
            self.duty_step +%= 1;
            self.period = self.period_setting;
        }

        const new_value_u4: u4 = WAVEFORMS[self.wave_duty][self.duty_step];
        self.value = if (new_value_u4 == 0) 0 else new_value_u4 +| self.volume;
    }

    pub fn isDacOn(self: *const Self) bool {
        return self.init_volume != 0 or self.envelope_dir != 0;
    }

    pub fn trigger(self: *Self) void {
        self.on = 1;
        if (self.length_timer == 0) {
            self.length_timer = self.init_length_timer;
        }
        self.envelope_timer = 0;
        self.period = self.period_setting;
        self.volume = self.init_volume;
    }

    pub fn clearRegisters(self: *Self) void {
        self.on = 0;
        self.value = 0;
        self.volume = 0;

        self.wave_duty = 0;
        self.init_length_timer = 0;

        self.init_volume = 0;
        self.envelope_dir = 0;
        self.envelope_sweep_pace = 0;

        self.period_setting = 0;
        self.length_enable = 0;
    }

    pub fn printState(self: *const Self, writer: anytype) !void {
        try format(writer, "CH2 is {s} and DAC is {s}\n", .{
            if (self.on == 1) "on" else "off",
            if (self.isDacOn()) "on" else "off",
        });
        try format(writer, "    Current sample: ${x}\n", .{self.value});
        try format(writer, "    Volume: {}\n", .{self.volume});
        try format(writer, "    Pan: {s}\n", .{if (self.mix_left == 1 and self.mix_right == 1) "center" else if (self.mix_left == 1) "left" else "right"});
        try format(writer, "    Duty cycle: {s}\n", .{
            switch (self.wave_duty) {
                0 => "12.5%",
                1 => "25%",
                2 => "50%",
                3 => "75%",
            },
        });
        try format(writer, "    Duty step: {}\n", .{self.duty_step});
        try format(writer, "    Length timer: {s}", .{
            if (self.length_enable == 0) "disabled\n" else "",
        });
        if (self.length_enable == 1) {
            try format(writer, "set to {}; will expire in {} ticks\n", .{
                self.init_length_timer,
                0b11_1111 - self.length_timer,
            });
        }
        try format(writer, "    Initial volume: {}\n", .{self.init_volume});
        try format(writer, "    Envelope: {s}", .{
            if (self.envelope_sweep_pace == 0) "disabled\n" else "",
        });
        if (self.envelope_sweep_pace != 0) {
            try format(writer, "{s} every {} ticks\n", .{
                if (self.envelope_dir == 1) "increasing" else "decreasing",
                self.envelope_sweep_pace,
            });
        }
        try format(writer, "    Period setting: ${x}\n", .{self.period_setting});
        try format(writer, "    Current period value: ${x}\n", .{self.period});
    }
};
