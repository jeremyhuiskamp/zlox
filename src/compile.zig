const std = @import("std");
const Allocator = std.mem.Allocator;

const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Scanner = @import("./scanner.zig").Scanner;
const Token = @import("./scanner.zig").Token;
const TokenType = @import("./scanner.zig").TokenType;
const debug = @import("./debug.zig");
const Value = @import("./value.zig").Value;
const StringObj = @import("./object.zig").StringObj;

const CompileError = Parser.Error || error{CompileError};

pub fn compile(source: []const u8, chunk: *Chunk, allocator: Allocator) CompileError!void {
    var scanner = Scanner.init(source);
    var parser = Parser.init(&scanner, chunk, allocator);
    parser.advance();
    try parser.expression();
    parser.consume(.EOF, "Expect end of expression.");
    try parser.endCompilation();

    if (parser.hasError) return error.CompileError;
}

const Precedence = enum {
    NONE,
    ASSIGNMENT,
    CONDITIONAL,
    OR,
    AND,
    EQUALITY,
    COMPARISON,
    TERM, // + -
    FACTOR, // * /
    UNARY, // - !
    CALL, // . ()
    PRIMARY,

    fn ord(self: Precedence) u8 {
        return @intFromEnum(self);
    }

    fn higher(self: Precedence) Precedence {
        // TODO: what happens if we do this from .PRIMARY?
        // Do we need a no-op value on the high end?
        return @enumFromInt(self.ord() + 1);
    }
};

const ParseFn = *const fn (*Parser) Parser.Error!void;

const ParseRule = struct {
    prefix: ?ParseFn = null,
    infix: ?ParseFn = null,
    precedence: Precedence = .NONE,
};

const rules = std.enums.directEnumArrayDefault(TokenType, ParseRule, ParseRule{}, 0, .{
    // zig fmt: off
    .LEFT_PAREN = .{ .prefix = Parser.grouping, },
    .MINUS =      .{ .prefix = Parser.unary,    .infix = Parser.binary, .precedence = .TERM },
    .PLUS =       .{                            .infix = Parser.binary, .precedence = .TERM },
    .SLASH =      .{                            .infix = Parser.binary, .precedence = .FACTOR },
    .STAR =       .{                            .infix = Parser.binary, .precedence = .FACTOR },
    .NUMBER =     .{ .prefix = Parser.number,   },
    .FALSE =      .{ .prefix = Parser.literal,  },
    .TRUE =       .{ .prefix = Parser.literal,  },
    .BANG =       .{ .prefix = Parser.unary,    },
    .NIL =        .{ .prefix = Parser.literal,  },
    .EQUAL_EQUAL = .{                           .infix = Parser.binary, .precedence = .EQUALITY },
    .BANG_EQUAL = .{                            .infix = Parser.binary, .precedence = .EQUALITY },
    .GREATER =    .{                            .infix = Parser.binary, .precedence = .COMPARISON },
    .GREATER_EQUAL = .{                         .infix = Parser.binary, .precedence = .COMPARISON },
    .LESS =       .{                            .infix = Parser.binary, .precedence = .COMPARISON },
    .LESS_EQUAL = .{                            .infix = Parser.binary, .precedence = .COMPARISON },
    .STRING =     .{ .prefix = Parser.string,   },
    // zig fmt: on
});

fn parseRuleFor(tokenType: TokenType) *const ParseRule {
    return &rules[@intFromEnum(tokenType)];
}

const Parser = struct {
    scanner: *Scanner,
    current: Token,
    previous: Token,
    hasError: bool,
    panicMode: bool,
    compilingChunk: *Chunk,
    allocator: Allocator,

    const Error = Chunk.Error;

    fn init(scanner: *Scanner, chunk: *Chunk, allocator: Allocator) Parser {
        return Parser{
            .scanner = scanner,
            .current = undefined,
            .previous = undefined,
            .hasError = false,
            .panicMode = false,
            .compilingChunk = chunk,
            .allocator = allocator,
        };
    }

    fn advance(self: *Parser) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.scanToken();

            if (self.current.type != .ERROR) break;

            // for a .ERROR, the value is a message rather than a token:
            self.errorAt(self.current, self.current.value);
        }
    }

    fn consume(self: *Parser, tokenType: TokenType, message: []const u8) void {
        if (self.current.type == tokenType) {
            self.advance();
            return;
        }
        self.errorAt(self.current, message);
    }

    fn errorAt(self: *Parser, token: Token, message: []const u8) void {
        if (self.panicMode) return;
        self.panicMode = true;

        const stderr = std.io.getStdErr().writer();
        stderr.print("[line {}] Error", .{token.line}) catch {};
        if (token.type == .EOF) {
            stderr.print(" at end", .{}) catch unreachable;
        } else if (token.type == .ERROR) {
            // nothing
        } else {
            stderr.print(" at '{s}'", .{token.value}) catch {};
        }
        stderr.print(": {s}\n", .{message}) catch {};
        self.hasError = true;
    }

    fn emitOpCode(self: *Parser, code: OpCode) Error!void {
        // NB: previous is undefined if there was no code and we're just emiting
        // a RETURN here.  Relying on the parser not accepting empty source.
        try self.compilingChunk.writeOpCode(code, self.previous.line);
    }

    fn emitConstant(self: *Parser, value: Value) Error!void {
        // TODO: the book didn't supply this addNewConstant wrapper
        // do we need to do something at a lower level?
        // Ah, in this spot, the book detects running out of space for constants
        // and makes it a parser error.  Need to detect that error in chunk,
        // return a specific error, and check it here.
        // NB, other errors could come from allocation issues.  The book exits
        // early on allocation errors.  We're passing it on up, but it seems a
        // bit tricky to know when we should try to handle particular types
        // of errors.  Time to learn about error unions...
        try self.compilingChunk.addNewConstant(value, self.previous.line);
    }

    fn endCompilation(self: *Parser) Error!void {
        try self.emitOpCode(.RETURN);

        if (debug.PRINT_CODE) {
            // Unlike book, we print even if there was a compilation error.
            // Seems useful to see what we had before the error.
            // Would be nice to draw a marker of some sort where the error
            // happened...
            debug.disassemble(self.compilingChunk.*, "code");
        }
    }

    fn number(self: *Parser) Error!void {
        if (std.fmt.parseFloat(f64, self.previous.value)) |value| {
            try self.emitConstant(.{ .number = value });
        } else |_| {
            self.errorAt(self.previous, "Compiler error: expected number.");
        }
    }

    fn expression(self: *Parser) Error!void {
        try self.parsePrecedence(.ASSIGNMENT);
    }

    fn grouping(self: *Parser) Error!void {
        try self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after expression.");
    }

    fn unary(self: *Parser) Error!void {
        const operator = self.previous;
        try self.parsePrecedence(.UNARY);
        switch (operator.type) {
            .MINUS => try self.emitOpCode(.NEGATE),
            .BANG => try self.emitOpCode(.NOT),
            else => self.errorAt(operator, "Compiler error: unexpected operator."),
        }
    }

    fn binary(self: *Parser) Error!void {
        const operator = self.previous;
        const rule = parseRuleFor(operator.type);
        // TODO: assert that there is a precedence?
        try self.parsePrecedence(rule.precedence.higher());

        switch (operator.type) {
            .PLUS => try self.emitOpCode(.ADD),
            .MINUS => try self.emitOpCode(.SUBTRACT),
            .STAR => try self.emitOpCode(.MULTIPLY),
            .SLASH => try self.emitOpCode(.DIVIDE),
            .BANG_EQUAL => {
                try self.emitOpCode(.EQUAL);
                try self.emitOpCode(.NOT);
            },
            .EQUAL_EQUAL => try self.emitOpCode(.EQUAL),
            .GREATER => try self.emitOpCode(.GREATER),
            .GREATER_EQUAL => {
                try self.emitOpCode(.LESS);
                try self.emitOpCode(.NOT);
            },
            .LESS => try self.emitOpCode(.LESS),
            .LESS_EQUAL => {
                try self.emitOpCode(.GREATER);
                try self.emitOpCode(.NOT);
            },
            else => self.errorAt(operator, "Compiler error: unexpected operator."),
        }
    }

    fn literal(self: *Parser) Error!void {
        switch (self.previous.type) {
            .FALSE => try self.emitOpCode(.FALSE),
            .TRUE => try self.emitOpCode(.TRUE),
            .NIL => try self.emitOpCode(.NIL),
            else => self.errorAt(self.previous, "Compiler error: unexpected literal."),
        }
    }

    fn string(self: *Parser) Error!void {
        const strObj = try StringObj.init(self.allocator, self.previous.value);
        try self.emitConstant(.{ .object = strObj.asObj() });
    }

    fn parsePrecedence(self: *Parser, precedence: Precedence) Error!void {
        self.advance();
        const prefixRule = parseRuleFor(self.previous.type).prefix;
        if (prefixRule == null) {
            self.errorAt(self.previous, "Expect expression.");
            return;
        }
        try prefixRule.?(self);

        while (precedence.ord() <= parseRuleFor(self.current.type).precedence.ord()) {
            self.advance();
            const infixRule = parseRuleFor(self.previous.type).infix;
            if (infixRule == null) {
                self.errorAt(self.previous, "Expect expression.");
                return;
            }
            try infixRule.?(self);
        }
    }
};

fn expectCompilationFailure(comptime source: []const u8) !void {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try std.testing.expectError(error.CompileError, compile(source, &chunk, std.testing.allocator));
}

test "parse empty content" {
    // expression required:
    try expectCompilationFailure("");
}

test "parse constant" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("1", &chunk, std.testing.allocator);
}

test "parse with scanner error" {
    try expectCompilationFailure("~");
}

test "rules lookup" {
    // a configured case:
    const lparenRule = rules[@intFromEnum(TokenType.LEFT_PAREN)];
    try std.testing.expect(lparenRule.prefix != null);
    try std.testing.expect(lparenRule.infix == null);
    try std.testing.expect(lparenRule.precedence == .NONE);

    // a default case:
    const rparenRule = parseRuleFor(.RIGHT_PAREN);
    try std.testing.expect(rparenRule.prefix == null);
    try std.testing.expect(rparenRule.infix == null);
    try std.testing.expect(rparenRule.precedence == .NONE);
}

test "parse non-trival expression" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("1 + 2 * (3 + 4)", &chunk, std.testing.allocator);

    // Seems too invasive to assert on the full format of the compiled
    // code.  We could execute it to get the result, but this is just a
    // parser test, not and end-to-end test.
    // 4 constants + 4 values, 3 operators and 1 return:
    try std.testing.expectEqual(12, chunk.code.items.len);
}

test "parse error" {
    try expectCompilationFailure("1 +");
}

test "parse another non-trivial expression" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("(-1 + 2) * 3 - -4", &chunk, std.testing.allocator);
    // 4 constants + 4 values, 5 operators and 1 return:
    try std.testing.expectEqual(14, chunk.code.items.len);
}

test "parse boolean" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("true", &chunk, std.testing.allocator);
    // constant and return:
    try std.testing.expectEqual(2, chunk.code.items.len);
}

test "parse nil" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("nil", &chunk, std.testing.allocator);
    // constant and return:
    try std.testing.expectEqual(2, chunk.code.items.len);
}

test "parse equality and comparison" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try compile("1 < 2 == 3 >= 4", &chunk, std.testing.allocator);
    // 4 constants + 4 values, 2 single operators, 1 double operator and 1 return:
    try std.testing.expectEqual(13, chunk.code.items.len);
}

test "parse string" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    try compile("\"hello compiler\"", &chunk, std.testing.allocator);
    // constant, value and return:
    try std.testing.expectEqual(3, chunk.code.items.len);
}
