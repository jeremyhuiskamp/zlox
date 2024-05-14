const std = @import("std");
const c = @import("./chunk.zig");
const Value = @import("./value.zig").Value;

const STACK_MAX = 256;

pub const Stack = struct {
    // Idea: make this an ArrayList so that it can grow.
    // But each time we add, we'd need to check to see if
    // we re-allocated and if so, adjust the top pointer
    // to point to the new memory instead.
    values: [STACK_MAX]Value,
    top: [*]Value,

    pub fn init() Stack {
        return Stack{
            .values = undefined,
            .top = undefined,
        };
        // NB: we can't call reset() here because we
        // copy the struct to return it, which invalidates
        // the top pointer.  The alternative would be
        // to allocate the struct, but that requires an
        // allocation...
    }

    pub fn reset(self: *Stack) void {
        self.top = &self.values;
    }

    pub fn push(self: *Stack, value: Value) void {
        self.top[0] = value;
        self.top += 1;
    }

    pub fn pop(self: *Stack) Value {
        self.top -= 1;
        return self.top[0];
    }

    pub fn size(self: *Stack) usize {
        const top = @intFromPtr(self.top);
        const bottom = @intFromPtr(&self.values);
        return (top - bottom) / @sizeOf(Value);
    }

    pub fn print(self: *Stack) void {
        for (self.values[0..self.size()]) |value| {
            std.debug.print("[ {any} ]", .{value});
        }
    }
};

test "stack basics" {
    var stack = Stack.init();
    stack.reset();
    try std.testing.expectEqual(0, stack.size());
    stack.push(.{ .number = 5.3 });
    try std.testing.expectEqual(1, stack.size());
    stack.push(.{ .number = 1.2 });
    try std.testing.expectEqual(2, stack.size());
    try std.testing.expectEqual(Value{ .number = 1.2 }, stack.pop());
    try std.testing.expectEqual(1, stack.size());
    try std.testing.expectEqual(Value{ .number = 5.3 }, stack.pop());
    try std.testing.expectEqual(0, stack.size());
}
