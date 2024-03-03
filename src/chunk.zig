const std = @import("std");

pub const OpCode = enum {
    OP_CONSTANT,
    OP_RETURN,
};

const Value = f64;
const Values = std.ArrayList(Value);

// Is this type too big?
// Book has all the debugging stuff implemented externally...
pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(usize),
    values: Values,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
            .values = Values.init(allocator),
        };
    }

    pub fn writeOpCode(self: *Chunk, code: OpCode, line: usize) !void {
        // TODO: unsafe: check if there's more than 256 opcodes?
        // probably static check is fine though, not needed at runtime
        const byte: u8 = @intFromEnum(code);
        try self.writeChunk(byte, line);
    }

    pub fn writeConstantOffset(self: *Chunk, offset: usize, line: usize) !void {
        // TODO: unsafe: can't handle more than 256 values
        // book points out that we might want additional op codes for higher
        // offsets...
        try self.writeChunk(@truncate(offset), line);
    }

    fn writeChunk(self: *Chunk, value: u8, line: usize) !void {
        try self.code.append(value);
        try self.lines.append(line);
    }

    pub fn disassemble(self: Chunk, name: []const u8) void {
        std.debug.print("== {s} ==\n", .{name});

        var offset: usize = 0;
        while (offset < self.code.items.len) {
            offset = self.disassembleInstruction(offset);
        }
    }

    fn disassembleInstruction(self: Chunk, offset: usize) usize {
        std.debug.print("{d:0>4} ", .{offset});
        if (offset > 0 and self.lines.items[offset] == self.lines.items[offset - 1]) {
            std.debug.print("   | ", .{});
        } else {
            std.debug.print("{d: >4} ", .{self.lines.items[offset]});
        }

        const op: OpCode = std.meta.intToEnum(OpCode, self.code.items[offset]) catch {
            std.debug.print("unknown opcode: {d}\n", .{self.code.items[offset]});
            return offset + 1;
        };

        return switch (op) {
            OpCode.OP_RETURN => simpleInstruction(op, offset),
            OpCode.OP_CONSTANT => self.constantInstruction(op, offset),
        };
    }

    fn simpleInstruction(op: OpCode, offset: usize) usize {
        std.debug.print("{s}\n", .{@tagName(op)});
        return offset + 1;
    }

    fn constantInstruction(self: Chunk, op: OpCode, offset: usize) usize {
        const constantOffset = self.code.items[offset + 1];
        std.debug.print("{s: <16} {d: >4} '", .{
            @tagName(op),
            constantOffset,
        });

        // TODO: crack out to `printValue` per book?
        std.debug.print("{d}", .{self.values.items[constantOffset]});

        std.debug.print("'\n", .{});
        return offset + 2;
    }

    pub fn addConstant(self: *Chunk, value: Value) !usize {
        try self.values.append(value);
        return self.values.items.len - 1;
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.lines.deinit();
        self.values.deinit();
    }
};

test "chunk" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    try std.testing.expect(c.code.items.len == 0);

    try c.writeOpCode(OpCode.OP_RETURN, 123);
    try std.testing.expect(c.code.items.len == 1);
    try std.testing.expect(c.lines.items.len == 1);
}

test "chunk values" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    const offset = try c.addConstant(5.3);
    try std.testing.expect(offset == 0);

    const offset2 = try c.addConstant(3.4);
    try std.testing.expect(offset2 == 1);
}

test "disassemble" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();
    try c.writeOpCode(OpCode.OP_RETURN, 123);
    // Confusingly, printing from the test seems to partially label
    // the outcome as failure, and then again later as success...
    // But the code is untestable except via visually scanning the
    // output so...
    c.disassemble("test chunk");
}
