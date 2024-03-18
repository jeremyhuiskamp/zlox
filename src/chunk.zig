const std = @import("std");

pub const OpCode = enum {
    CONSTANT,
    ADD,
    SUBTRACT,
    NEGATE,
    MULTIPLY,
    DIVIDE,
    RETURN,
};

const Code = std.ArrayList(u8);
const Lines = std.ArrayList(usize);
pub const Value = f64;
const Values = std.ArrayList(Value);

pub const Chunk = struct {
    code: Code,
    lines: Lines,
    constants: Values,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = Code.init(allocator),
            .lines = Lines.init(allocator),
            .constants = Values.init(allocator),
        };
    }

    pub fn writeOpCode(self: *Chunk, code: OpCode, line: usize) !void {
        // TODO: unsafe: check if there's more than 256 opcodes?
        // probably static check is fine though, not needed at runtime
        try self.writeChunk(@intFromEnum(code), line);
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
        try self.constants.append(value);
        return self.constants.items.len - 1;
    }

    // This is a wrapper to call a bunch of the other public functions.
    // Are those other ones really needed?
    pub fn addNewConstant(self: *Chunk, value: Value, line: usize) !void {
        const offset = try self.addConstant(value);
        try self.writeOpCode(.CONSTANT, line);
        try self.writeConstantOffset(offset, line);
    }

    pub fn deinit(self: *const Chunk) void {
        self.code.deinit();
        self.lines.deinit();
        self.constants.deinit();
    }
};

test "chunk" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    try std.testing.expect(c.code.items.len == 0);

    try c.writeOpCode(.RETURN, 123);
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
