const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const VM = @import("./vm.zig").VM;
const InterpretError = @import("./vm.zig").InterpretError;
const Value = @import("./value.zig").Value;
const compile = @import("./compile.zig").compile;
const debug = @import("./debug.zig");
const StringObj = @import("./object.zig").StringObj;

fn expect(source: []const u8, comptime expected: anytype) !void {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    try compile(source, &chunk, std.testing.allocator);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    vm.resetStack();

    if (debug.TRACE_EXECUTION) {
        std.debug.print("\n====\n", .{});
    }
    try vm.interpret(&chunk);
    try std.testing.expectEqual(1, vm.stack.size());

    // nb: if this is an object, it's only valid to use before the chunk is
    // freed.
    const got = vm.stack.pop();

    switch (@TypeOf(expected)) {
        comptime_float => try std.testing.expectEqual(Value{ .number = expected }, got),
        bool => try std.testing.expectEqual(Value{ .boolean = expected }, got),
        void => try std.testing.expectEqual(Value{ .nil = {} }, got),
        else => {
            // TODO: a better way to check if this is a literal string.
            // This bombs pretty badly if it's a different type.
            const aString: []const u8 = "a string";
            switch (@TypeOf(expected, aString)) {
                []const u8 => {
                    // TODO: is there some way that expectEqual can compare Obj types?
                    try std.testing.expect(got.is(.object));
                    try std.testing.expect(got.object.is(.String));
                    try std.testing.expectEqualStrings(expected, StringObj.from(got.object).value);
                },
                else => @compileError("unsupported type"),
            }
        },
    }
}

test "nil" {
    try expect("nil", {});
    try expect("nil == nil", true);
    try expect("nil != nil", false);
}

test "arithmetic expression" {
    try expect("1 + 2 * 3", 7.0);
}

test "boolean" {
    try expect("true", true);
    try expect("false", false);
    try expect("!false", true);
    try expect("!true", false);
}

test "complex expression" {
    try expect("!(5 - 4 >= 3 * 2 == !nil)", true);
}

test "comparisons" {
    try expect("1 < 2", true);
    try expect("1 <= 2", true);
    try expect("1 > 2", false);
    try expect("1 >= 2", false);
    try expect("2 >= 2", true);
    try expect("2 <= 2", true);
}

test "strings" {
    // TODO: need something simpler than this
    // not sure how to match the type if we put it inline
    // const expected: []const u8 = "hello";
    try expect("\"hello\"", "hello");

    try expect("\"hello\" == \"hello\"", true);
    try expect("\"hello\" != \"hello\"", false);

    try expect("\"hello\" + \" \" + \"world\"", "hello world");
}
