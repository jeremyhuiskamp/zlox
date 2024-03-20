const std = @import("std");
const vm = @import("./vm.zig");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    switch (std.os.argv.len) {
        1 => {
            try repl();
        },
        2 => {
            const filename = std.mem.span(std.os.argv[1]);
            try runFile(arena.allocator(), filename);
        },
        else => {
            std.debug.print("usage: zlox [script]\n", .{});
            std.os.exit(64);
        },
    }
}

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

fn repl() !void {
    var buf: [1024]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        const maybeLine = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        if (maybeLine) |line| {
            _ = try interpret(line);
        } else {
            break;
        }
    }
}

fn interpret(line: []const u8) !vm.InterpretResult {
    try stdout.print("{s}\n", .{line});
    return .OK;
}

fn runFile(alloc: std.mem.Allocator, filename: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(alloc, filename, std.math.maxInt(usize)) catch |err| {
        try stderr.print("Could not open file: {s}\n", .{@errorName(err)});
        std.os.exit(74);
    };
    defer alloc.free(source);
    const result = try interpret(source);

    switch (result) {
        .OK => {},
        .COMPILE_ERROR => std.os.exit(65),
        .RUNTIME_ERROR => std.os.exit(70),
    }
}
