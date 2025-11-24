pub const Sample = packed struct {
    left: f32,
    right: f32,

    pub fn init(left: f32, right: f32) Sample {
        return .{
            .left = left,
            .right = right,
        };
    }

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

    pub fn equals(self: Sample, other: Sample) bool {
        return self.left == other.left and self.right == other.right;
    }
};
