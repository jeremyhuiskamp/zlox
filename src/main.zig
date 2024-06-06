const std = @import("std");
const VM = @import("./vm.zig").VM;
const InterpretError = @import("./vm.zig").InterpretError;
const Chunk = @import("./chunk.zig").Chunk;
const debug = @import("./debug.zig");
const compile = @import("./compile.zig").compile;

const ExitReason = enum(u8) {
    OutOfMemory = 1,
    Unknown = 10,
    BadInvocation = 64,
    CompileError = 65,
    RuntimeError = 70,
};

fn die(reason: ExitReason) noreturn {
    std.os.exit(@intFromEnum(reason));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    switch (std.os.argv.len) {
        1 => {
            try repl(arena.allocator());
        },
        2 => {
            const filename = std.mem.span(std.os.argv[1]);
            try runFile(arena.allocator(), filename);
        },
        else => {
            std.debug.print("usage: zlox [script]\n", .{});
            die(.BadInvocation);
        },
    }
}

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

fn repl(alloc: std.mem.Allocator) !void {
    var buf: [1024]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        const maybeLine = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        if (maybeLine) |line| {
            if (interpret(alloc, line)) |_| {
                std.debug.print("OK\n", .{});
            } else |err| {
                std.debug.print("{s}\n", .{@errorName(err)});
            }
        } else {
            std.debug.print("\nEOF\n", .{});
            return;
        }
    }
}

// TODO: move to vm.zig?
fn interpret(alloc: std.mem.Allocator, line: []const u8) InterpretError!void {
    var chunk = Chunk.init(alloc);
    defer chunk.deinit();

    try compile(line, &chunk, alloc);

    var vm = VM.init(alloc);
    defer vm.deinit();

    vm.resetStack();

    try vm.interpret(&chunk);

    const value = vm.stack.pop();
    std.debug.print("result = '{any}'\n", .{value});
}

fn runFile(alloc: std.mem.Allocator, filename: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(alloc, filename, std.math.maxInt(usize)) catch |err| {
        try stderr.print("Could not open file: {s}\n", .{@errorName(err)});
        std.os.exit(74);
    };
    defer alloc.free(source);
    interpret(alloc, source) catch |err| {
        stderr.print("{s}\n", .{@errorName(err)}) catch {};
        const reason: ExitReason = switch (err) {
            error.CompileError => .CompileError,
            error.RuntimeError => .RuntimeError,
            error.OutOfMemory => .OutOfMemory,
        };
        die(reason);
    };
}
