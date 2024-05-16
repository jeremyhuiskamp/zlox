const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;

pub const TRACE_EXECUTION = false;
pub const PRINT_CODE = false;

pub fn disassemble(chunk: Chunk, name: []const u8) void {
    std.debug.print("--8<-- {s} --8<--\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }

    std.debug.print("-->8-- {s} -->8--\n", .{name});
}

pub fn disassembleInstruction(chunk: Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{chunk.lines.items[offset]});
    }

    const op: OpCode = std.meta.intToEnum(OpCode, chunk.code.items[offset]) catch {
        std.debug.print("unknown opcode: {d}\n", .{chunk.code.items[offset]});
        return offset + 1;
    };

    return switch (op) {
        .CONSTANT => constantInstruction(chunk, op, offset),
        .RETURN,
        .NEGATE,
        .NIL,
        .TRUE,
        .FALSE,
        .NOT,
        .ADD,
        .SUBTRACT,
        .MULTIPLY,
        .DIVIDE,
        .EQUAL,
        .GREATER,
        .LESS,
        => simpleInstruction(op, offset),
    };
}

fn simpleInstruction(op: OpCode, offset: usize) usize {
    std.debug.print("{s}\n", .{@tagName(op)});
    return offset + 1;
}

fn constantInstruction(chunk: Chunk, op: OpCode, offset: usize) usize {
    const constantOffset = chunk.code.items[offset + 1];
    std.debug.print("{s: <16} {d: >4} '{}'\n", .{
        @tagName(op),
        constantOffset,
        chunk.constants.items[constantOffset],
    });

    return offset + 2;
}

test "disassemble" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.writeOpCode(.RETURN, 123);
    // Confusingly, printing from the test seems to partially label
    // the outcome as failure, and then again later as success...
    // But the code is untestable except via visually scanning the
    // output so...
    if (TRACE_EXECUTION) {
        disassemble(chunk, "test chunk");
    }
}
