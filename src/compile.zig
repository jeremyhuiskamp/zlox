const std = @import("std");
const c = @import("./chunk.zig");

pub fn compile(alloc: std.mem.Allocator, source: []const u8) !c.Chunk {
    _ = alloc;
    _ = source;
    @panic("TODO");
}
