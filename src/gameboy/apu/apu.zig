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

pub const Apu = struct {
    on: u1,
    ch1: Ch1,

    // number of DIV_APU ticks until an event
    next_envelope_sweep_tick_in: u4,
    next_length_tick_in: u3,
    next_freq_sweep_tick_in: u3,

    const Self = @This();

    pub fn init() Self {
        return .{
            .on = 0,
            .ch1 = Ch1.init(),
            .next_envelope_sweep_tick_in = 8,
            .next_length_tick_in = 2,
            .next_freq_sweep_tick_in = 4,
        };
    }

    pub fn step(self: *Self, div_apu_occurred: bool) void {
        if (div_apu_occurred) {
            self.next_envelope_sweep_tick_in -= 1;
            self.next_length_tick_in -= 1;
            self.next_freq_sweep_tick_in -= 1;
        }

        self.ch1.step(self.next_envelope_sweep_tick_in == 0, self.next_length_tick_in == 0);

        if (self.next_envelope_sweep_tick_in == 0) {
            self.next_envelope_sweep_tick_in = 8;
        }
        if (self.next_length_tick_in == 0) {
            self.next_length_tick_in = 2;
        }
        if (self.next_freq_sweep_tick_in == 0) {
            self.next_freq_sweep_tick_in = 4;
        }
    }

    pub fn readReg(self: *const Self, comptime reg: ApuReg) u8 {
        switch (reg) {
            .NR10 => {
                const pace: u8 = self.ch1.sweep_pace;
                const dir: u8 = self.ch1.sweep_dir;
                const individual_step: u8 = self.ch1.sweep_individual_step;
                return (pace << 4) | (dir << 3) | individual_step;
            },
            .NR11 => return 0,
            .NR12 => return 0,
            .NR13 => return 0,
            .NR14 => return 0,
            .NR21 => return 0,
            .NR22 => return 0,
            .NR23 => return 0,
            .NR24 => return 0,
            .NR30 => return 0,
            .NR31 => return 0,
            .NR32 => return 0,
            .NR33 => return 0,
            .NR34 => return 0,
            .NR41 => return 0,
            .NR42 => return 0,
            .NR43 => return 0,
            .NR44 => return 0,
            .NR50 => return 0,
            .NR51 => return 0,
            .NR52 => {
                const apu_on: u8 = self.on;
                const ch1_on: u8 = self.ch1.on;
                return (apu_on << 7) | ch1_on;
            },
        }
    }

    pub fn writeReg(self: *Self, comptime reg: ApuReg, val: u8) void {
        switch (reg) {
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
                // TODO writes should be delayed until retrigger if the channel is already on
                self.ch1.init_volume = @truncate((val & 0b1111_0000) >> 4);
                self.ch1.envelope_dir = @truncate((val & 0b0000_1000) >> 3);
                self.ch1.envelope_sweep_pace = @truncate(val & 0b0000_0111);
            },
            .NR13 => {
                const val_u11: u11 = val;
                self.ch1.period_setting = (self.ch1.period_setting & 0b111_0000_0000) | val_u11;
            },
            .NR14 => {
                self.ch1.length_enable = @truncate((val & 0b0100_0000) >> 6);
                const val_u11: u11 = val;
                self.ch1.period_setting = (self.ch1.period_setting & 0b000_1111_1111) | (val_u11 << 8);
            },
            .NR21 => {},
            .NR22 => {},
            .NR23 => {},
            .NR24 => {},
            .NR30 => {},
            .NR31 => {},
            .NR32 => {},
            .NR33 => {},
            .NR34 => {},
            .NR41 => {},
            .NR42 => {},
            .NR43 => {},
            .NR44 => {},
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

const WAVEFORMS = [4][16]u1{
    [_]u1{ 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0 },
    [_]u1{ 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0 },
    [_]u1{ 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1 },
};

pub const Ch1 = struct {
    // Internal
    on: u1,
    val: u4,
    volume: u4,
    length_timer: u7,
    envelope_timer: u3,
    period: u11,

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
    duty_step: u4,

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
            .val = 0,
            .volume = 0,
            .length_timer = 0,
            .envelope_timer = 0,
            .period = 0,
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

    pub fn step(self: *Self, envelope_tick: bool, length_tick: bool) void {
        if (self.on == 0) {
            return;
        }

        if (self.envelope_sweep_pace != 0 and envelope_tick) {
            self.envelope_timer += 1;
            if (self.envelope_timer == self.envelope_sweep_pace) {
                self.envelope_timer = 0;
                self.volume -|= 1;
            }
        }

        if (self.length_enable and length_tick) {
            self.length_timer += 1;
            if (self.length_timer == 64) {
                self.on = 0;
            }
        }

        self.val = WAVEFORMS[self.wave_duty][self.duty_step];
    }

    pub fn isDacEnabled(self: *const Self) bool {
        return self.init_volume != 0 or self.envelope_dir != 0;
    }

    pub fn trigger(self: *Self) void {
        self.on = 1;
        if (self.length_timer == 64) {
            self.length_timer = 0;
        }
        self.envelope_timer = 0;
        self.period = self.period_setting;
        self.volume = self.init_volume;

        self.sweep_shadow = self.period;
        self.sweep_timer = 0;
        self.sweep_enabled = if (self.sweep_pace != 0 or self.sweep_individual_step != 0) 1 else 0;
        if (self.sweep_individual_step != 0) {
            self.performSweepFreqCalc();
        }
    }

    pub fn clearRegisters(self: *Self) void {
        self.on = 0;
        self.val = 0;
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

    fn performSweepFreqCalc(self: *Self) void {
        var temp = self.sweep_shadow >> self.sweep_individual_step;
        if (self.sweep_direction == 1) {
            temp = ~temp +% 1;
        }
        const new_freq = self.sweep_shadow + temp;

        // overflow check
        if (new_freq > 0x7ff) {
            self.on = 0;
        } else {
            self.sweep_shadow = new_freq;
        }
    }
};
