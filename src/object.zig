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
    hash: u32,

    // Allocate space for a StringObj plus a value, and point the value slice
    // to the memory right after the StringObj.  This is meant to function a bit
    // like c's flexible array members, and saves us from needing to do a
    // separate allocation for the value.
    fn make(alloc: std.mem.Allocator, valueSize: usize) !*StringObj {
        const totalBytesRequired = @sizeOf(StringObj) + valueSize;
        const mem = try alloc.alignedAlloc(u8, @alignOf(StringObj), totalBytesRequired);
        const stringObj: *StringObj = @ptrCast(mem);

        stringObj.obj = .{ .type = .String };
        stringObj.value = mem[@sizeOf(StringObj)..];

        return stringObj;
    }

    pub fn init(alloc: std.mem.Allocator, value: []const u8) !*StringObj {
        const ref = try make(alloc, value.len);

        @memcpy(ref.value, value);
        ref.hash = hash(ref.value);

        return ref;
    }

    pub fn init2(alloc: std.mem.Allocator, value1: []const u8, value2: []const u8) !*StringObj {
        const ref = try make(alloc, value1.len + value2.len);

        @memcpy(ref.value[0..value1.len], value1);
        @memcpy(ref.value[value1.len..], value2);
        ref.hash = hash(ref.value);

        return ref;
    }

    fn hash(value: []const u8) u32 {
        var result: u32 = 0x811c9dc5;
        for (value) |c| {
            result ^= c;
            result *%= 0x01000193;
        }
        return result;
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

        // In safe mode (see std.heap.general_purpose_allocator.Config.safety),
        // we need to free a pointer with the same underlying size and alignment
        // as we allocated.
        // Casting magic copied from Allocator.destroy and std.hash_map.HashMapUnmanaged.deallocate
        const ptr = @as([*]align(@alignOf(StringObj)) u8, @ptrCast(@constCast(self)));
        const mem = ptr[0 .. @sizeOf(StringObj) + self.value.len];
        alloc.free(mem);
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

test "hash" {
    // some sampling copied from http://www.isthe.com/chongo/src/fnv/test_fnv.c
    // hashes specified in decimal because that's how the zig test runner prints
    // them on mismatches, and we have no other way to trace back to the test case.
    const tests = .{
        .{ "hello", 1335831723 },
        .{ "", 2166136261 },
        .{ "foobar", 3214735720 },
        .{ "héllö", 4130253622 }, // assume utf-8
        .{ &[_]u8{ 0x68, 0xc3, 0xa9, 0x6c, 0x6c, 0xc3, 0xb6 }, 4130253622 }, // explicit utf-8
    };
    inline for (tests) |t| {
        const strObj = try StringObj.init(std.testing.allocator, t[0]);
        defer strObj.deinit(std.testing.allocator);
        try std.testing.expectEqual(t[1], strObj.hash);
    }
}
