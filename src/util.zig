const std = @import("std");

pub fn as16(high: u8, low: u8) u16 {
    const high16: u16 = high;
    const low16: u16 = low;
    return (high16 << 8) | low16;
}
