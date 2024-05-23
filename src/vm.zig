const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");
const Stack = @import("./Stack.zig");
const Value = @import("./value.zig").Value;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VM = struct {
    chunk: ?*const Chunk,
    ip: ?[*]u8,
    stack: Stack,

    // Creates an empty VM and returns it on the stack.
    // You must call resetStack() after this, and then not copy/move the VM
    // afterwards, because the stack has a self-referential pointer.
    pub fn init() VM {
        return VM{
            .chunk = null,
            .ip = null,
            .stack = Stack.init(),
        };
    }

    pub fn resetStack(self: *VM) void {
        self.stack.reset();
    }

    pub fn interpret(self: *VM, chunk: *const Chunk) InterpretError!void {
        self.chunk = chunk;
        self.ip = chunk.code.items.ptr;
        return self.run();
    }

    fn ipAsOffset(self: *VM) usize {
        return @intFromPtr(self.ip.?) - @intFromPtr(self.chunk.?.code.items.ptr);
    }

    fn lineOfPreviousInstruction(self: *VM) usize {
        return self.chunk.?.lines.items[self.ipAsOffset() - 1];
    }

    fn run(self: *VM) InterpretError!void {
        while (true) {
            if (debug.TRACE_EXECUTION) {
                // indentation is to line up with the third column of the
                // instruction disassembler:
                std.debug.print("          stack({d}):", .{self.stack.size()});
                self.stack.print();
                std.debug.print("\n", .{});
                _ = debug.disassembleInstruction(
                    self.chunk.?.*,
                    self.ipAsOffset(),
                );
            }
            const instruction: OpCode = @enumFromInt(self.ip.?[0]);
            self.ip.? += 1;
            switch (instruction) {
                .RETURN => {
                    // book pops and prints here, but I want to
                    // access the value, so we'll just pop from
                    // the caller...
                    return;
                },
                .CONSTANT => {
                    const constant_offset = self.ip.?[0];
                    self.ip.? += 1;
                    const value = self.chunk.?.constants.items[constant_offset];
                    self.stack.push(value);
                },
                .NEGATE => {
                    const p = self.stack.top - 1;
                    switch (p[0]) {
                        .number => p[0] = .{ .number = -p[0].number },
                        else => return self.runtimeError("Operand must be a number.", .{}),
                    }
                },
                .ADD => try self.binaryOp(add),
                .SUBTRACT => try self.binaryOp(sub),
                .MULTIPLY => try self.binaryOp(mul),
                .DIVIDE => try self.binaryOp(div),
                .NIL => self.stack.push(.nil),
                .TRUE => self.stack.push(.{ .boolean = true }),
                .FALSE => self.stack.push(.{ .boolean = false }),
                .NOT => {
                    const p = self.stack.top - 1;
                    p[0] = .{ .boolean = p[0].isFalsey() };
                },
                .EQUAL => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(.{ .boolean = a.equal(b) });
                },
                .GREATER => try self.binaryOp(greater),
                .LESS => try self.binaryOp(less),
            }
        }
        return .RUNTIME_ERROR;
    }

    fn binaryOp(self: *VM, comptime BinaryFunc: anytype) InterpretError!void {
        const b = self.stack.pop();
        const a = self.stack.pop();

        if (!a.is(.number) or !b.is(.number)) {
            return self.runtimeError("Operands must be numbers.", .{});
        }

        const resultValue = BinaryFunc(a.number, b.number);
        const resultType = @TypeOf(resultValue);
        self.stack.push(if (resultType == f64) .{ .number = resultValue } else .{ .boolean = resultValue });
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) InterpretError {
        const stderr = std.io.getStdErr().writer();
        stderr.print(format, args) catch {};
        const line = self.lineOfPreviousInstruction();
        stderr.print(" [line {d}] in script\n", .{line}) catch {};
        return error.RuntimeError;
    }

    pub fn deinit(_: *VM) void {}
};

inline fn add(x: f64, y: f64) f64 {
    return x + y;
}
inline fn mul(x: f64, y: f64) f64 {
    return x * y;
}
inline fn sub(x: f64, y: f64) f64 {
    return x - y;
}
inline fn div(x: f64, y: f64) f64 {
    return x / y;
}
inline fn greater(x: f64, y: f64) bool {
    return x > y;
}
inline fn less(x: f64, y: f64) bool {
    return x < y;
}

// Helper to run a chunk of code in a VM.
const VMTest = struct {
    chunk: Chunk,
    line: usize,

    // Allocates with the test allocator for syntactic convenience.
    // You must call one of `expect*()` to clean up later.
    pub fn init() *VMTest {
        var t = std.testing.allocator.create(VMTest) catch unreachable;
        t.chunk = Chunk.init(std.testing.allocator);
        t.line = 0;
        return t;
    }

    fn constant(self: *VMTest, value: Value) *VMTest {
        self.chunk.addNewConstant(value, self.line) catch unreachable;
        self.line += 1;
        return self;
    }

    pub fn number(self: *VMTest, value: f64) *VMTest {
        return self.constant(.{ .number = value });
    }

    pub fn boolean(self: *VMTest, value: bool) *VMTest {
        return self.constant(.{ .boolean = value });
    }

    pub fn nil(self: *VMTest) *VMTest {
        return self.constant(.nil);
    }

    pub fn op(self: *VMTest, operation: OpCode) *VMTest {
        self.chunk.writeOpCode(operation, self.line) catch unreachable;
        self.line += 1;
        return self;
    }

    // de-allocates and must be run exactly once!
    fn execute(self: *VMTest) !Value {
        defer std.testing.allocator.destroy(self);
        defer self.chunk.deinit();

        try self.chunk.writeOpCode(.RETURN, self.line);

        if (debug.TRACE_EXECUTION) {
            std.debug.print("\n====\n", .{});
        }
        var vm = VM.init();
        defer vm.deinit();
        vm.resetStack();

        try vm.interpret(&self.chunk);
        try std.testing.expectEqual(1, vm.stack.size());

        return vm.stack.pop();
    }

    pub fn expectNumber(self: *VMTest, expected: f64) !void {
        const value = try self.execute();
        try std.testing.expect(value.is(.number));
        try std.testing.expectEqual(expected, value.number);
    }

    pub fn expectBool(self: *VMTest, expected: bool) !void {
        const value = try self.execute();
        try std.testing.expect(value.is(.boolean));
        try std.testing.expectEqual(expected, value.boolean);
    }

    pub fn expectNil(self: *VMTest) !void {
        const value = try self.execute();
        try std.testing.expect(value.is(.nil));
    }

    pub fn expectRuntimeError(self: *VMTest) !void {
        const result = self.execute();
        try std.testing.expectError(error.RuntimeError, result);
    }
};

test "interpret negate" {
    try VMTest.init()
        .number(5.3)
        .op(.NEGATE)
        .expectNumber(-5.3);
}

test "interpret add" {
    try VMTest.init()
        .number(5.3)
        .number(1.2)
        .op(.ADD)
        .expectNumber(6.5);
}

test "interpret subtract" {
    try VMTest.init()
        .number(5.3)
        .number(1.2)
        .op(.SUBTRACT)
        .expectNumber(4.1);
}

test "interpret multiply" {
    try VMTest.init()
        .number(2.0)
        .number(3.0)
        .op(.MULTIPLY)
        .expectNumber(6.0);
}

test "interpret divide" {
    try VMTest.init()
        .number(6.0)
        .number(3.0)
        .op(.DIVIDE)
        .expectNumber(2.0);
}

test "interpret longer expression" {
    try VMTest.init()
        .number(2.2)
        .number(3.4)
        .op(.ADD)
        .number(5.6)
        .op(.DIVIDE)
        .op(.NEGATE)
        .expectNumber(-1.0);
}

test "interpret nil" {
    try VMTest.init()
        .nil()
        .expectNil();
}

test "interpret boolean" {
    try VMTest.init()
        .boolean(true)
        .expectBool(true);

    try VMTest.init()
        .boolean(false)
        .expectBool(false);
}

test "not boolean" {
    try VMTest.init()
        .boolean(false)
        .op(.NOT)
        .expectBool(true);

    try VMTest.init()
        .boolean(true)
        .op(.NOT)
        .expectBool(false);
}

test "truthiness" {
    try VMTest.init()
        .number(5.3)
        .op(.NOT)
        .expectBool(false);

    try VMTest.init()
        .nil()
        .op(.NOT)
        .expectBool(true);
}

test "can't negate a boolean" {
    try VMTest.init()
        .boolean(false)
        .op(.NEGATE)
        .expectRuntimeError();
}

test "comparison and equality" {
    try VMTest.init()
        .number(5.3)
        .number(5.3)
        .op(.EQUAL)
        .expectBool(true);

    try VMTest.init()
        .number(5.3)
        .number(5.4)
        .op(.EQUAL)
        .expectBool(false);

    try VMTest.init()
        .number(5.3)
        .number(5.2)
        .op(.GREATER)
        .expectBool(true);

    try VMTest.init()
        .number(5.2)
        .number(5.3)
        .op(.GREATER)
        .expectBool(false);

    try VMTest.init()
        .number(5.2)
        .number(5.3)
        .op(.LESS)
        .expectBool(true);
}
