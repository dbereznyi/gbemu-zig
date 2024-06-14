pub fn as16(x: u8, y: u8) u16 {
    const x16: u16 = x;
    const y16: u16 = y;
    return (y16 << 8) | x16;
}
