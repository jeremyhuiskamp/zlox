const std = @import("std");

pub const ObjType = enum {
    // Placeholder, until we get more types.
    // Otherwise ObjType ends up being 0 bytes, which isn't realistic.
    Unknown,
    String,
};

pub const Obj = struct {
    type: ObjType,

    pub fn is(self: *Obj, objType: ObjType) bool {
        return self.type == objType;
    }

    pub fn equal(self: *Obj, other: *Obj) bool {
        if (self.type != other.type) return false;
        switch (self.type) {
            .String => {
                return std.mem.eql(
                    u8,
                    StringObj.from(self).value,
                    StringObj.from(other).value,
                );
            },
            // Unknowns are never equal, I guess?
            else => return false,
        }
    }

    fn internal_format(
        self: *const Obj,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.type) {
            .String => {
                const strObj = StringObj.from(self);
                try writer.print("{s}", .{strObj.value});
            },
            else => try writer.print("{s}", .{@tagName(self.type)}),
        }
    }

    // Create a thing with a format method that can be called by std.fmt.format()
    pub fn formatter(self: *const Obj) std.fmt.Formatter(internal_format) {
        // The whole point here is to add a temporary layer of indirection so
        // that std.fmt doesn't make a copy of our Obj, which would otherwise
        // remove it from the context of the surrounding StringObj or other
        // wrapper.
        return .{ .data = self };
    }
};

pub const StringObj = struct {
    obj: Obj,
    value: []u8,

    pub fn init(alloc: std.mem.Allocator, value: []const u8) !*StringObj {
        const ref = try alloc.create(StringObj);
        errdefer alloc.destroy(ref);

        ref.obj = .{ .type = .String };
        ref.value = try alloc.dupe(u8, value);

        return ref;
    }

    pub fn init2(alloc: std.mem.Allocator, value1: []const u8, value2: []const u8) !*StringObj {
        const ref = try alloc.create(StringObj);
        errdefer alloc.destroy(ref);

        ref.obj = .{ .type = .String };

        const buf = try alloc.alloc(u8, value1.len + value2.len);
        @memcpy(buf[0..value1.len], value1);
        @memcpy(buf[value1.len..], value2);

        ref.value = buf;

        return ref;
    }

    pub fn from(obj: *const Obj) *const StringObj {
        std.debug.assert(obj.type == .String);

        return @fieldParentPtr(StringObj, "obj", obj);
    }

    pub fn asObj(self: *StringObj) *Obj {
        return &self.obj;
    }

    pub fn deinit(self: *const StringObj, alloc: std.mem.Allocator) void {
        // should we hang on to the allocator from init()?
        // It would be convenient, but this struct is supposed to be as small
        // as possible for performance reasons.
        alloc.free(self.value);
        alloc.destroy(self);
    }
};

test "round-trip a reference to StringObj and the underlying Obj" {
    const strObj = try StringObj.init(std.testing.allocator, "hello");
    defer strObj.deinit(std.testing.allocator);

    const obj = strObj.asObj();
    try std.testing.expect(obj.is(.String));

    const strObj2 = StringObj.from(obj);
    try std.testing.expectEqualStrings("hello", strObj2.value);
}

test "format string value" {
    const strObj = try StringObj.init(std.testing.allocator, "hello string");
    defer strObj.deinit(std.testing.allocator);

    const obj = strObj.asObj();
    try std.testing.expectFmt("hello string", "{}", .{obj.formatter()});
}

test "string equality" {
    const strObj = try StringObj.init(std.testing.allocator, "hello");
    defer strObj.deinit(std.testing.allocator);

    const strObj2 = try StringObj.init(std.testing.allocator, "hello");
    defer strObj2.deinit(std.testing.allocator);

    try std.testing.expect(strObj.asObj().equal(strObj2.asObj()));
    // equal to self:
    try std.testing.expect(strObj.asObj().equal(strObj.asObj()));
}

test "concatenation" {
    const strObj = try StringObj.init2(std.testing.allocator, "hello", " world");
    defer strObj.deinit(std.testing.allocator);

    const strObj2 = try StringObj.init(std.testing.allocator, "hello world");
    defer strObj2.deinit(std.testing.allocator);

    try std.testing.expect(strObj.asObj().equal(strObj2.asObj()));
}
