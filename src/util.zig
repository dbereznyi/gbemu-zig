const std = @import("std");

pub fn as16(high: u8, low: u8) u16 {
    const high16: u16 = high;
    const low16: u16 = low;
    return (high16 << 8) | low16;
}

pub fn sleepPrecise(durationNanos: u64) !void {
    const start = try std.time.Instant.now();
    while (true) {
        const now = try std.time.Instant.now();
        if (now.since(start) >= durationNanos) {
            return;
        }
    }
}
