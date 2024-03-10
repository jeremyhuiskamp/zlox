const std = @import("std");
const c = @import("./chunk.zig");

pub fn disassemble(chunk: c.Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: c.Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{chunk.lines.items[offset]});
    }

    const op: c.OpCode = std.meta.intToEnum(c.OpCode, chunk.code.items[offset]) catch {
        std.debug.print("unknown opcode: {d}\n", .{chunk.code.items[offset]});
        return offset + 1;
    };

    return switch (op) {
        c.OpCode.OP_RETURN => simpleInstruction(op, offset),
        c.OpCode.OP_CONSTANT => constantInstruction(chunk, op, offset),
    };
}

fn simpleInstruction(op: c.OpCode, offset: usize) usize {
    std.debug.print("{s}\n", .{@tagName(op)});
    return offset + 1;
}

fn constantInstruction(chunk: c.Chunk, op: c.OpCode, offset: usize) usize {
    const constantOffset = chunk.code.items[offset + 1];
    std.debug.print("{s: <16} {d: >4} '", .{
        @tagName(op),
        constantOffset,
    });

    // TODO: crack out to `printValue` per book?
    std.debug.print("{d}", .{chunk.values.items[constantOffset]});

    std.debug.print("'\n", .{});
    return offset + 2;
}

test "disassemble" {
    var chunk = c.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.writeOpCode(c.OpCode.OP_RETURN, 123);
    // Confusingly, printing from the test seems to partially label
    // the outcome as failure, and then again later as success...
    // But the code is untestable except via visually scanning the
    // output so...
    disassemble(chunk, "test chunk");
}
