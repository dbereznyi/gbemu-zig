const std = @import("std");
const expect = std.testing.expect;

pub fn as16(high: u8, low: u8) u16 {
    const high16: u16 = high;
    const low16: u16 = low;
    return (high16 << 8) | low16;
}

pub fn incAs16(high: u8, low: u8, new_high: *u8, new_low: *u8) void {
    const inc = as16(high, low) +% 1;
    new_high.* = @truncate(inc >> 8);
    new_low.* = @truncate(inc);
}

/// A fixed-capacity stack.
/// Pushing an item when the stack size is at capacity causes the item
/// at the bottom to be discarded.
pub fn BoundedStack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const L = std.DoublyLinkedList(T);

        list: L,
        nodes: [capacity]L.Node,
        len: usize,

        pub fn init() Self {
            return .{
                .list = L{},
                .nodes = undefined,
                .len = 0,
            };
        }

        pub fn push(self: *Self, value: T) void {
            if (self.len < capacity) {
                self.nodes[self.len] = L.Node{ .data = value };
                self.list.prepend(&self.nodes[self.len]);
                self.len += 1;
            } else {
                const last = self.list.last orelse unreachable;
                self.list.remove(last);
                last.*.data = value;
                self.list.prepend(last);
            }
        }

        pub fn top(self: *const Self) ?T {
            const first = self.list.first orelse return null;
            return first.data;
        }

        pub fn size(self: *const Self) usize {
            return self.len;
        }

        pub fn getItems(self: *const Self, items_buf: *[capacity]T) []T {
            var it = self.list.first;
            var index: usize = 0;
            while (it) |node| : (it = node.next) {
                items_buf[index] = node.data;
                index += 1;
            }
            return items_buf[0..index];
        }

        pub fn getItemsReversed(self: *const Self, items_buf: *[capacity]T) []T {
            var it = self.list.last;
            var index: usize = 0;
            while (it) |node| : (it = node.prev) {
                items_buf[index] = node.data;
                index += 1;
            }
            return items_buf[0..index];
        }
    };
}

test "BoundedStack" {
    var stack = BoundedStack(u32, 3).init();
    try expect(stack.len == 0);

    stack.push(1);
    try expect(stack.size() == 1);
    try expect(stack.top() == 1);

    stack.push(2);
    try expect(stack.size() == 2);
    try expect(stack.top() == 2);

    stack.push(3);
    try expect(stack.size() == 3);
    try expect(stack.top() == 3);

    stack.push(4);
    try expect(stack.size() == 3);
    try expect(stack.top() == 4);

    var items_buf: [3]u32 = undefined;
    const items = stack.getItems(&items_buf);
    try expect(std.mem.eql(u32, items, &[_]u32{ 4, 3, 2 }));
}
