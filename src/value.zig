const std = @import("std");

pub const ValueType = enum { number, boolean, nil };

pub const Value = union(ValueType) {
    number: f64,
    boolean: bool,
    nil: void,

    pub fn is(self: Value, vtype: ValueType) bool {
        return @as(ValueType, self) == vtype;
    }

    pub fn format(
        value: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (value) {
            .number => |number| try writer.print("{d}", .{number}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .nil => try writer.print("nil", .{}),
        }
    }

    pub fn isFalsey(self: Value) bool {
        return switch (self) {
            .nil => true,
            .boolean => !self.boolean,
            .number => false,
        };
    }

    pub fn equal(self: Value, other: Value) bool {
        switch (self) {
            .nil => return other.is(.nil),
            .boolean => |b| return other.is(.boolean) and b == other.boolean,
            .number => |n| return other.is(.number) and n == other.number,
        }
    }
};

test "value type" {
    const v: Value = .{ .number = 1.0 };
    try std.testing.expect(v.is(.number));
    try std.testing.expect(!v.is(.boolean));
    try std.testing.expect(!v.is(.nil));
}

test "format number value" {
    const value: Value = .{ .number = 1.0 };

    var buf: [32]u8 = undefined;
    const actual = try std.fmt.bufPrint(&buf, "{}", .{value});

    try std.testing.expectEqualStrings("1", actual);
}

test "falsey" {
    try std.testing.expect((Value{ .boolean = false }).isFalsey());
    try std.testing.expect((Value{ .nil = {} }).isFalsey());

    try std.testing.expect(!(Value{ .boolean = true }).isFalsey());
    try std.testing.expect(!(Value{ .number = 0.0 }).isFalsey());
    try std.testing.expect(!(Value{ .number = 1.0 }).isFalsey());
}

test "equality" {
    try std.testing.expect((Value{ .number = 1.0 }).equal(Value{ .number = 1.0 }));
    try std.testing.expect((Value{ .boolean = true }).equal(Value{ .boolean = true }));
    try std.testing.expect((Value{ .nil = {} }).equal(Value{ .nil = {} }));

    try std.testing.expect(!(Value{ .number = 1.0 }).equal(Value{ .number = 2.0 }));
    try std.testing.expect(!(Value{ .boolean = true }).equal(Value{ .boolean = false }));

    try std.testing.expect(!(Value{ .nil = {} }).equal(Value{ .boolean = false }));
    try std.testing.expect(!(Value{ .nil = {} }).equal(Value{ .number = 0.0 }));
    try std.testing.expect(!(Value{ .boolean = true }).equal(Value{ .number = 0.0 }));
}
