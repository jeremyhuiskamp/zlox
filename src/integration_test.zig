const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const VM = @import("./vm.zig").VM;
const InterpretResult = @import("./vm.zig").InterpretResult;
const Value = @import("./value.zig").Value;
const compile = @import("./compile.zig").compile;
const debug = @import("./debug.zig");

fn evaluate(source: []const u8) !Value {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const compileOk = try compile(source, &chunk);
    if (!compileOk) {
        return error.CompileError;
    }

    var vm = VM.init();
    defer vm.deinit();
    vm.resetStack();

    if (debug.TRACE_EXECUTION) {
        std.debug.print("\n====\n", .{});
    }
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());

    return vm.stack.pop();
}

fn expect(source: []const u8, comptime expected: anytype) !void {
    const got = try evaluate(source);
    switch (@TypeOf(expected)) {
        comptime_float => try std.testing.expectEqual(Value{ .number = expected }, got),
        bool => try std.testing.expectEqual(Value{ .boolean = expected }, got),
        void => try std.testing.expectEqual(Value{ .nil = {} }, got),
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
