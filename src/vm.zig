const c = @import("./chunk.zig");
const std = @import("std");
const debug = @import("./debug.zig");
const s = @import("./stack.zig");

// Would this be more idiomatic as an error set
// with OK left out?
pub const InterpretResult = enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

const STACK_MAX = 256;

pub const VM = struct {
    chunk: ?*const c.Chunk,
    ip: ?[*]u8,
    stack: s.Stack,

    pub fn init() VM {
        return VM{
            .chunk = null,
            .ip = null,
            .stack = s.Stack.init(),
        };
    }

    fn resetStack(self: *VM) void {
        self.stack.reset();
    }

    pub fn interpret(self: *VM, chunk: *const c.Chunk) InterpretResult {
        self.chunk = chunk;
        self.ip = chunk.code.items.ptr;
        return self.run();
    }

    fn ipAsOffset(self: *VM) usize {
        return @intFromPtr(self.ip.?) - @intFromPtr(self.chunk.?.code.items.ptr);
    }

    fn run(self: *VM) InterpretResult {
        while (true) {
            if (debug.TRACE_EXECUTION) {
                std.debug.print("          stack({d}):", .{self.stack.size()});
                self.stack.print();
                std.debug.print("\n", .{});
                _ = debug.disassembleInstruction(
                    self.chunk.?.*,
                    self.ipAsOffset(),
                );
            }
            const instruction: c.OpCode = @enumFromInt(self.ip.?[0]);
            self.ip.? += 1;
            switch (instruction) {
                .RETURN => {
                    // book pops and prints here, but I want to
                    // access the value, so we'll just pop from
                    // the caller...
                    return InterpretResult.OK;
                },
                .CONSTANT => {
                    const constant_offset = self.ip.?[0];
                    self.ip.? += 1;
                    const value = self.chunk.?.constants.items[constant_offset];
                    self.stack.push(value);
                },
                .NEGATE => {
                    const p = self.stack.top - 1;
                    p[0] = -p[0];
                    // self.stack.push(-self.stack.pop());
                },
                .ADD => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a + b);
                },
                .SUBTRACT => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a - b);
                },
                .MULTIPLY => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a * b);
                },
                .DIVIDE => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a / b);
                },
            }
        }
        return InterpretResult.RUNTIME_ERROR;
    }

    pub fn deinit(_: *VM) void {}
};

// Helper to run a chunk of code in a VM.
const VMTest = struct {
    chunk: c.Chunk,
    line: usize,

    // Allocates with the test allocator for syntactic convenience.
    // You must call `run()` to clean up later.
    pub fn init() *VMTest {
        var t = std.testing.allocator.create(VMTest) catch unreachable;
        t.chunk = c.Chunk.init(std.testing.allocator);
        t.line = 0;
        return t;
    }

    pub fn val(self: *VMTest, value: c.Value) *VMTest {
        self.chunk.addNewConstant(value, self.line) catch unreachable;
        self.line += 1;
        return self;
    }

    pub fn op(self: *VMTest, operation: c.OpCode) *VMTest {
        self.chunk.writeOpCode(operation, self.line) catch unreachable;
        self.line += 1;
        return self;
    }

    // de-allocates and must be run exactly once!
    pub fn run(self: *VMTest) !c.Value {
        defer std.testing.allocator.destroy(self);
        defer self.chunk.deinit();

        try self.chunk.writeOpCode(.RETURN, self.line);

        if (debug.TRACE_EXECUTION) {
            std.debug.print("\n====\n", .{});
        }
        var vm = VM.init();
        defer vm.deinit();
        vm.resetStack();

        const result = vm.interpret(&self.chunk);
        try std.testing.expectEqual(InterpretResult.OK, result);
        try std.testing.expectEqual(1, vm.stack.size());

        return vm.stack.pop();
    }
};

test "interpret negate" {
    const r = VMTest.init()
        .val(5.3)
        .op(.NEGATE)
        .run();
    try std.testing.expectEqual(-5.3, r);
}

test "interpret add" {
    const r = VMTest.init()
        .val(5.3)
        .val(1.2)
        .op(.ADD)
        .run();
    try std.testing.expectEqual(6.5, r);
}

test "interpret subtract" {
    const r = VMTest.init()
        .val(5.3)
        .val(1.2)
        .op(.SUBTRACT)
        .run();
    try std.testing.expectEqual(4.1, r);
}

test "interpret multiply" {
    const r = VMTest.init()
        .val(2.0)
        .val(3.0)
        .op(.MULTIPLY)
        .run();
    try std.testing.expectEqual(6.0, r);
}

test "interpret divide" {
    const r = VMTest.init()
        .val(6.0)
        .val(3.0)
        .op(.DIVIDE)
        .run();
    try std.testing.expectEqual(2.0, r);
}

test "interpret longer expression" {
    const r = VMTest.init()
        .val(2.2)
        .val(3.4)
        .op(.ADD)
        .val(5.6)
        .op(.DIVIDE)
        .op(.NEGATE)
        .run();
    try std.testing.expectEqual(-1.0, r);
}
