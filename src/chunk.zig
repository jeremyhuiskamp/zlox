const std = @import("std");

pub const OpCode = enum {
    OP_CONSTANT,
    OP_RETURN,
};

const Value = f64;
const Values = std.ArrayList(Value);

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
