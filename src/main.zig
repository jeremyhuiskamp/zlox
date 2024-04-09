const std = @import("std");
const v = @import("./vm.zig");
const c = @import("./chunk.zig");
const debug = @import("./debug.zig");
const comp = @import("./compile.zig");

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
            std.os.exit(64);
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
            const result = interpret(alloc, line);
            std.debug.print("{s}\n", .{@tagName(result)});
        } else {
            std.debug.print("EOF\n", .{});
            return;
        }
    }
}

// TODO: move to vm.zig?
fn interpret(alloc: std.mem.Allocator, line: []const u8) v.InterpretResult {
    var chunk = c.Chunk.init(alloc);
    defer chunk.deinit();

    const compileOk = comp.compile(line, &chunk) catch {
        // TODO: log the error?
        return .COMPILE_ERROR;
    };
    if (!compileOk) {
        return .COMPILE_ERROR;
    }

    var vm = v.VM.init();
    defer vm.deinit();

    vm.resetStack();

    const result = vm.interpret(&chunk);
    if (result == .OK) {
        const value = vm.stack.pop();
        std.debug.print("result = '{d}'\n", .{value});
    }
    return result;
}

fn runFile(alloc: std.mem.Allocator, filename: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(alloc, filename, std.math.maxInt(usize)) catch |err| {
        try stderr.print("Could not open file: {s}\n", .{@errorName(err)});
        std.os.exit(74);
    };
    defer alloc.free(source);
    const result = interpret(alloc, source);

    switch (result) {
        .OK => {},
        .COMPILE_ERROR => std.os.exit(65),
        .RUNTIME_ERROR => std.os.exit(70),
    }
}
