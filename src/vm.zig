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

    fn push(self: *VM, value: c.Value) void {
        self.stackTop.?.* = value;
        self.stackTop = self.stackTop.?.add(1);
    }

    fn pop(self: *VM) c.Value {
        self.stackTop = self.stackTop.?.sub(1);
        return self.stackTop.?.*;
    }

    pub fn interpret(self: *VM, chunk: *const c.Chunk) InterpretResult {
        self.chunk = chunk;
        self.ip = chunk.code.items.ptr;
        return self.run();
    }

    fn ipAsOffset(self: *VM) usize {
        return @intFromPtr(self.ip.?) - @intFromPtr(self.chunk.?.code.items.ptr);
    }

    fn stackOffset(self: *VM) usize {
        return @intFromPtr(self.stackTop) - @intFromPtr(&self.stack);
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
            var instruction: c.OpCode = undefined;
            instruction = @enumFromInt(self.ip.?[0]);
            self.ip.? += 1;
            switch (instruction) {
                c.OpCode.RETURN => {
                    // book pops and prints here, but I want to
                    // access the value, so we'll just pop from
                    // the caller...
                    return InterpretResult.OK;
                },
                c.OpCode.CONSTANT => {
                    const constant_offset = self.ip.?[0];
                    self.ip.? += 1;
                    const value = self.chunk.?.constants.items[constant_offset];
                    self.stack.push(value);
                },
                c.OpCode.NEGATE => {
                    const p = self.stack.top - 1;
                    p[0] = -p[0];
                    // self.stack.push(-self.stack.pop());
                },
                c.OpCode.ADD => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a + b);
                },
                c.OpCode.SUBTRACT => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a - b);
                },
                c.OpCode.MULTIPLY => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a * b);
                },
                c.OpCode.DIVIDE => {
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

test "do an interpret" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    const constant_offset = try chunk.addConstant(5.3);
    try chunk.writeOpCode(c.OpCode.CONSTANT, 1);
    try chunk.writeConstantOffset(constant_offset, 1);

    try chunk.writeOpCode(c.OpCode.NEGATE, 2);
    try chunk.writeOpCode(c.OpCode.RETURN, 3);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(-5.3, vm.stack.pop());
}

test "interpret add" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    try chunk.addNewConstant(5.3, 1);
    try chunk.addNewConstant(1.2, 2);
    try chunk.writeOpCode(c.OpCode.ADD, 3);
    try chunk.writeOpCode(c.OpCode.RETURN, 4);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(6.5, vm.stack.pop());
}

test "interpret subtract" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    try chunk.addNewConstant(5.3, 1);
    try chunk.addNewConstant(1.2, 2);
    try chunk.writeOpCode(c.OpCode.SUBTRACT, 3);
    try chunk.writeOpCode(c.OpCode.RETURN, 4);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(4.1, vm.stack.pop());
}

test "interpret multiply" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    try chunk.addNewConstant(2.0, 1);
    try chunk.addNewConstant(3.0, 2);
    try chunk.writeOpCode(c.OpCode.MULTIPLY, 3);
    try chunk.writeOpCode(c.OpCode.RETURN, 4);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(6.0, vm.stack.pop());
}

test "interpret divide" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    try chunk.addNewConstant(6.0, 1);
    try chunk.addNewConstant(3.0, 2);
    try chunk.writeOpCode(c.OpCode.DIVIDE, 3);
    try chunk.writeOpCode(c.OpCode.RETURN, 4);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(2.0, vm.stack.pop());
}

test "interpret longer expression" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    var vm = VM.init();
    vm.resetStack();
    defer vm.deinit();

    try chunk.addNewConstant(2.2, 1);
    try chunk.addNewConstant(3.4, 2);
    try chunk.writeOpCode(c.OpCode.ADD, 3);
    try chunk.addNewConstant(5.6, 4);
    try chunk.writeOpCode(c.OpCode.DIVIDE, 5);
    try chunk.writeOpCode(c.OpCode.NEGATE, 6);
    try chunk.writeOpCode(c.OpCode.RETURN, 7);

    std.debug.print("====\n", .{});
    const result = vm.interpret(&chunk);
    try std.testing.expectEqual(InterpretResult.OK, result);
    try std.testing.expectEqual(1, vm.stack.size());
    try std.testing.expectEqual(-1.0, vm.stack.pop());
}
