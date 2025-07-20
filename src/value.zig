const std = @import("std");
const ObjType = @import("object.zig").ObjType;
const Obj = @import("object.zig").Obj;
const StringObj = @import("object.zig").StringObj;

pub const ValueType = enum { number, boolean, object, nil };

pub const Value = union(ValueType) {
    number: f64,
    boolean: bool,
    object: *Obj,
    nil: void,

    pub const NIL: Value = .{ .nil = {} };

    pub fn is(self: Value, vtype: ValueType) bool {
        return @as(ValueType, self) == vtype;
    }

    pub fn isObj(self: Value, objType: ObjType) bool {
        return self.is(.object) and self.object.is(objType);
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
            .object => |object| try writer.print("{}", .{object.formatter()}),
            .nil => try writer.print("nil", .{}),
        }
    }

    pub fn isFalsey(self: Value) bool {
        return switch (self) {
            .nil => true,
            .boolean => !self.boolean,
            .number => false,
            .object => false,
        };
    }

    pub fn equal(self: Value, other: Value) bool {
        switch (self) {
            .nil => return other.is(.nil),
            .boolean => |b| return other.is(.boolean) and b == other.boolean,
            .number => |n| return other.is(.number) and n == other.number,
            .object => |o| return other.is(.object) and o.equal(other.object),
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

test "format object value" {
    const obj = try StringObj.init(std.testing.allocator, "hello");
    defer obj.deinit(std.testing.allocator);

    const value: Value = .{ .object = obj.asObj() };
    var buf: [5]u8 = undefined;
    const actual = try std.fmt.bufPrint(&buf, "{}", .{value});
    try std.testing.expectEqualStrings("hello", actual);
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

    const obj1 = try StringObj.init(std.testing.allocator, "hello");
    defer obj1.deinit(std.testing.allocator);

    try std.testing.expect(!(Value{ .object = obj1.asObj() }).equal(Value{ .number = 1.0 }));
    try std.testing.expect(!(Value{ .object = obj1.asObj() }).equal(Value{ .boolean = true }));
    try std.testing.expect(!(Value{ .object = obj1.asObj() }).equal(Value{ .nil = {} }));

    try std.testing.expect((Value{ .object = obj1.asObj() }).equal(Value{ .object = obj1.asObj() }));

    const obj2 = try StringObj.init(std.testing.allocator, "hello");
    defer obj2.deinit(std.testing.allocator);
    try std.testing.expect((Value{ .object = obj1.asObj() }).equal(Value{ .object = obj2.asObj() }));
}
