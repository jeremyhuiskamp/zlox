const std = @import("std");

const StringObj = @import("./object.zig").StringObj;

pub const OpCode = enum {
    CONSTANT,
    NIL,
    TRUE,
    FALSE,
    NOT,
    EQUAL,
    GREATER,
    LESS,
    ADD,
    SUBTRACT,
    NEGATE,
    MULTIPLY,
    DIVIDE,
    RETURN,
};

const Code = std.ArrayList(u8);
const Lines = std.ArrayList(usize);
const Value = @import("./value.zig").Value;
const Values = std.ArrayList(Value);

pub const Chunk = struct {
    code: Code,
    lines: Lines,
    constants: Values,

    pub const Error = std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = Code.init(allocator),
            .lines = Lines.init(allocator),
            .constants = Values.init(allocator),
        };
    }

    pub fn writeOpCode(self: *Chunk, code: OpCode, line: usize) Error!void {
        // TODO: unsafe: check if there's more than 256 opcodes?
        // probably static check is fine though, not needed at runtime
        try self.writeChunk(@intFromEnum(code), line);
    }

    pub fn writeConstantOffset(self: *Chunk, offset: usize, line: usize) Error!void {
        // TODO: unsafe: can't handle more than 256 values
        // book points out that we might want additional op codes for higher
        // offsets...
        try self.writeChunk(@truncate(offset), line);
    }

    fn writeChunk(self: *Chunk, value: u8, line: usize) Error!void {
        try self.code.append(value);
        try self.lines.append(line);
    }

    pub fn addConstant(self: *Chunk, value: Value) Error!usize {
        try self.constants.append(value);
        return self.constants.items.len - 1;
    }

    // This is a wrapper to call a bunch of the other public functions.
    // Are those other ones really needed?
    pub fn addNewConstant(self: *Chunk, value: Value, line: usize) Error!void {
        const offset = try self.addConstant(value);
        try self.writeOpCode(.CONSTANT, line);
        try self.writeConstantOffset(offset, line);
    }

    // Free any objects in the chunk's constant pool.
    // This is an intermediate step until garbage collection is implemented.
    // The book does this all in the VM, but that relies on having a global
    // vm instance available when the constants are defined.  In my implementation
    // it seems simpler to handle these ones here.
    fn deinitConstantObjects(self: *Chunk) void {
        // There's not really a guarantee that the constant objects were allocated
        // by the same allocator that we've been using for the list itself.
        // We'll just make the assumption for now and hope it gets cleaner when
        // gc is implemented...
        const alloc = self.constants.allocator;
        for (self.constants.items) |constant| {
            switch (constant) {
                .object => |obj| {
                    switch (obj.type) {
                        .String => StringObj.from(obj).deinit(alloc),
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.lines.deinit();

        self.deinitConstantObjects();
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

    const offset = try c.addConstant(.{ .number = 5.3 });
    try std.testing.expect(offset == 0);

    const offset2 = try c.addConstant(.{ .number = 3.4 });
    try std.testing.expect(offset2 == 1);
}
