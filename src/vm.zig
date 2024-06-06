const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const debug = @import("./debug.zig");
const Stack = @import("./Stack.zig");
const Value = @import("./value.zig").Value;
const StringObj = @import("./object.zig").StringObj;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
    OutOfMemory,
};

pub const VM = struct {
    chunk: ?*const Chunk,
    ip: ?[*]u8,
    stack: Stack,

    alloc: std.mem.Allocator,
    // Unlike the book:
    // - only the dynamically calculated strings (the constant
    //   ones are handled by Chunk)
    // - we're allocating memory for a container rather than
    //   inlining a linked list.  This seems cleaner, and we're
    //   not worried about performance before we get the real
    //   gc implemented.
    strings: std.ArrayList(*StringObj),

    // Creates an empty VM and returns it on the stack.
    // You must call resetStack() after this, and then not copy/move the VM
    // afterwards, because the stack has a self-referential pointer.
    pub fn init(alloc: std.mem.Allocator) VM {
        return VM{
            .chunk = null,
            .ip = null,
            .stack = Stack.init(),
            .alloc = alloc,
            .strings = std.ArrayList(*StringObj).init(alloc),
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
                .ADD => try self.add(),
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

    fn add(self: *VM) InterpretError!void {
        const b = self.stack.pop();
        const a = self.stack.pop();
        if (a.isObj(.String) and b.isObj(.String)) {
            const concat = try StringObj.init2(
                self.alloc,
                StringObj.from(a.object).value,
                StringObj.from(b.object).value,
            );
            try self.strings.append(concat);
            self.stack.push(.{ .object = concat.asObj() });
        } else if (a.is(.number) and b.is(.number)) {
            self.stack.push(.{ .number = a.number + b.number });
        } else {
            return self.runtimeError("Operands must be two numbers or two strings.", .{});
        }
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

    pub fn deinit(self: *VM) void {
        for (self.strings.items) |string| {
            string.deinit(self.alloc);
        }
        self.strings.deinit();
    }
};

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
    vm: VM,
    line: usize,

    // Allocates with the test allocator for syntactic convenience.
    // You must call one of `expect*()` to clean up later.
    pub fn init() *VMTest {
        var t = std.testing.allocator.create(VMTest) catch unreachable;
        t.chunk = Chunk.init(std.testing.allocator);
        t.line = 0;
        t.vm = VM.init(std.testing.allocator);
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

    pub fn string(self: *VMTest, value: []const u8) *VMTest {
        const strObj = StringObj.init(std.testing.allocator, value) catch unreachable;
        return self.constant(.{ .object = strObj.asObj() });
    }

    pub fn op(self: *VMTest, operation: OpCode) *VMTest {
        self.chunk.writeOpCode(operation, self.line) catch unreachable;
        self.line += 1;
        return self;
    }

    fn execute(self: *VMTest) !Value {
        try self.chunk.writeOpCode(.RETURN, self.line);

        if (debug.TRACE_EXECUTION) {
            std.debug.print("\n====\n", .{});
        }
        self.vm.resetStack();
        try self.vm.interpret(&self.chunk);
        try std.testing.expectEqual(1, self.vm.stack.size());

        return self.vm.stack.pop();
    }

    fn deinit(self: *VMTest) void {
        self.vm.deinit();
        self.chunk.deinit();
        std.testing.allocator.destroy(self);
    }

    pub fn expectNumber(self: *VMTest, expected: f64) !void {
        defer self.deinit();

        const value = try self.execute();
        try std.testing.expect(value.is(.number));
        try std.testing.expectEqual(expected, value.number);
    }

    pub fn expectBool(self: *VMTest, expected: bool) !void {
        defer self.deinit();

        const value = try self.execute();
        try std.testing.expect(value.is(.boolean));
        try std.testing.expectEqual(expected, value.boolean);
    }

    pub fn expectNil(self: *VMTest) !void {
        defer self.deinit();

        const value = try self.execute();
        try std.testing.expect(value.is(.nil));
    }

    pub fn expectString(self: *VMTest, expected: []const u8) !void {
        defer self.deinit();

        const value = try self.execute();
        try std.testing.expect(value.isObj(.String));
        try std.testing.expectEqualStrings(expected, StringObj.from(value.object).value);
    }

    pub fn expectRuntimeError(self: *VMTest) !void {
        defer self.deinit();

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

test "concatenate strings" {
    try VMTest.init()
        .string("hello")
        .string("world")
        .op(.ADD)
        .expectString("helloworld");
}

test "string equality" {
    try VMTest.init()
        .string("hello")
        .string("hello")
        .op(.EQUAL)
        .expectBool(true);

    try VMTest.init()
        .string("hello")
        .string("world")
        .op(.EQUAL)
        .expectBool(false);
}
