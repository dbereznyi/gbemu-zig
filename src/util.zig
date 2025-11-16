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
        const L = std.DoublyLinkedList;
        const Node = struct {
            data: T,
            node: L.Node = .{},
        };

        list: L,
        nodes: [capacity]Node,
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
                self.nodes[self.len] = Node{ .data = value };
                self.list.prepend(&self.nodes[self.len].node);
                self.len += 1;
            } else {
                const last = self.list.last orelse unreachable;
                self.list.remove(last);
                var node: *Node = @fieldParentPtr("node", last);
                node.data = value;
                self.list.prepend(last);
            }
        }

        pub fn top(self: *const Self) ?Node {
            const item = self.list.first orelse return null;
            const node: *Node = @fieldParentPtr("node", item);
            return node.*;
        }

        pub fn bottom(self: *const Self) ?Node {
            const item = self.list.last orelse return null;
            const node: *Node = @fieldParentPtr("node", item);
            return node.*;
        }

        pub fn up(_: *const Self, node: Node) ?Node {
            const item = node.node.prev orelse return null;
            const node_above: *Node = @fieldParentPtr("node", item);
            return node_above.*;
        }

        pub fn down(_: *const Self, node: Node) ?Node {
            const item = node.node.next orelse return null;
            const node_below: *Node = @fieldParentPtr("node", item);
            return node_below.*;
        }

        pub fn size(self: *const Self) usize {
            return self.len;
        }

        pub fn getItems(self: *const Self, items_buf: []T) []T {
            var it = self.list.first;
            var index: usize = 0;
            while (it) |node| : (it = node.next) {
                items_buf[index] = node.data;
                index += 1;
            }
            return items_buf[0..index];
        }

        pub fn getItemsReversed(self: *const Self, items_buf: []T) []T {
            var it = self.list.last;
            var index: usize = 0;
            while (it) |node| : (it = node.prev) {
                const node_with_data: *Node = @fieldParentPtr("node", node);
                items_buf[index] = node_with_data.data;
                index += 1;
            }
            return items_buf[0..index];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            while (self.len > 0) {
                _ = self.list.pop();
                self.len -= 1;
            }
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
