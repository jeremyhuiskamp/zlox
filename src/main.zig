const std = @import("std");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var c = chunk.Chunk.init(arena.allocator());
    defer c.deinit();

    const constant = try c.addConstant(1.2);
    try c.writeOpCode(.CONSTANT, 123);
    try c.writeConstantOffset(constant, 123);
    try c.writeOpCode(.RETURN, 123);

    debug.disassemble(c, "test chunk");
}
