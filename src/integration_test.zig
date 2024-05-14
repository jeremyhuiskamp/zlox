const std = @import("std");
const c = @import("./chunk.zig");
const v = @import("./vm.zig");
const val = @import("./value.zig");
const comp = @import("./compile.zig");
const debug = @import("./debug.zig");

fn evaluate(source: []const u8) !val.Value {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const compileOk = try comp.compile(source, &chunk);
    if (!compileOk) {
        return error.CompileError;
    }

    var vm = v.VM.init();
    defer vm.deinit();
    vm.resetStack();

    if (debug.TRACE_EXECUTION) {
        std.debug.print("\n====\n", .{});
    }
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(v.InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());

    return vm.stack.pop();
}

fn expect(source: []const u8, comptime expected: anytype) !void {
    const got = try evaluate(source);
    switch (@TypeOf(expected)) {
        comptime_float => try std.testing.expectEqual(val.Value{ .number = expected }, got),
        bool => try std.testing.expectEqual(val.Value{ .boolean = expected }, got),
        void => try std.testing.expectEqual(val.Value{ .nil = {} }, got),
        else => @compileError("unsupported type"),
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
