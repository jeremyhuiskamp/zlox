const std = @import("std");
const c = @import("./chunk.zig");

const TokenType = enum {
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,

    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // literals
    IDENTIFIER,
    STRING,
    NUMBER,

    // keywords
    AND,
    CLASS,
    ELSE,
    FALSE,
    FUN,
    FOR,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    ERROR,
    EOF,
};

const Token = struct {
    type: TokenType,
    line: usize,
    value: []const u8,
};

const Scanner = struct {
    text: []const u8,
    start: usize,
    current: usize,
    line: usize,

    pub fn init(text: []const u8) Scanner {
        return Scanner{
            .text = text,
            .start = 0,
            .current = 0,
            .line = 1,
        };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) {
            return self.makeToken(.EOF);
        }

        const ch = self.advance();

        if (std.ascii.isAlphabetic(ch) or ch == '_') {
            return self.identifier();
        }

        if (std.ascii.isDigit(ch)) {
            return self.number();
        }

        switch (ch) {
            '(' => return self.makeToken(.LEFT_PAREN),
            ')' => return self.makeToken(.RIGHT_PAREN),
            '{' => return self.makeToken(.LEFT_BRACE),
            '}' => return self.makeToken(.RIGHT_BRACE),
            ',' => return self.makeToken(.COMMA),
            '.' => return self.makeToken(.DOT),
            '-' => return self.makeToken(.MINUS),
            '+' => return self.makeToken(.PLUS),
            ';' => return self.makeToken(.SEMICOLON),
            '*' => return self.makeToken(.STAR),
            '!' => return self.makeToken(if (self.match('=')) .BANG_EQUAL else .BANG),
            '=' => return self.makeToken(if (self.match('=')) .EQUAL_EQUAL else .EQUAL),
            '<' => return self.makeToken(if (self.match('=')) .LESS_EQUAL else .LESS),
            '>' => return self.makeToken(if (self.match('=')) .GREATER_EQUAL else .GREATER),
            '"' => return self.string(),

            else => {},
        }

        return self.errorToken("Unexpected character.");
    }

    fn identifier(self: *Scanner) Token {
        while (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_') {
            _ = self.advance();
        }

        return self.makeToken(self.identifierType());
    }

    fn identifierType(self: *Scanner) TokenType {
        switch (self.text[self.start]) {
            'a' => return self.checkKeyword(1, "nd", .AND),
            'c' => return self.checkKeyword(1, "lass", .CLASS),
            'e' => return self.checkKeyword(1, "lse", .ELSE),
            'f' => {
                if (self.current - self.start > 1) {
                    switch (self.text[self.start + 1]) {
                        'a' => return self.checkKeyword(2, "lse", .FALSE),
                        'o' => return self.checkKeyword(2, "r", .FOR),
                        'u' => return self.checkKeyword(2, "n", .FUN),
                        else => {},
                    }
                }
            },
            'i' => return self.checkKeyword(1, "f", .IF),
            'n' => return self.checkKeyword(1, "il", .NIL),
            'o' => return self.checkKeyword(1, "r", .OR),
            'p' => return self.checkKeyword(1, "rint", .PRINT),
            'r' => return self.checkKeyword(1, "eturn", .RETURN),
            's' => return self.checkKeyword(1, "uper", .SUPER),
            't' => {
                if (self.current - self.start > 1) {
                    switch (self.text[self.start + 1]) {
                        'h' => return self.checkKeyword(2, "is", .THIS),
                        'r' => return self.checkKeyword(2, "ue", .TRUE),
                        else => {},
                    }
                }
            },
            'v' => return self.checkKeyword(1, "ar", .VAR),
            'w' => return self.checkKeyword(1, "hile", .WHILE),
            else => {},
        }
        return .IDENTIFIER;
    }

    fn checkKeyword(self: *Scanner, consumed: usize, rest: []const u8, tokenType: TokenType) TokenType {
        const start = self.start + consumed;
        if (std.mem.eql(u8, self.text[start..self.current], rest)) {
            return tokenType;
        }
        return .IDENTIFIER;
    }

    fn number(self: *Scanner) Token {
        while (std.ascii.isDigit(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and std.ascii.isDigit(self.peekNext())) {
            _ = self.advance();
            while (std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(.NUMBER);
    }

    fn string(self: *Scanner) Token {
        // skip the opening quote
        // the book doesn't seem to do this?
        self.start += 1;

        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            return self.errorToken("Unterminated string.");
        }

        // defer to skip the closing quote
        defer _ = self.advance();

        return self.makeToken(.STRING);
    }

    fn skipWhitespace(self: *Scanner) void {
        while (!self.isAtEnd()) {
            const ch = self.peek();
            switch (ch) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                },
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd()) {
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => {
                    return;
                },
            }
        }
    }

    fn peek(self: *Scanner) u8 {
        if (self.isAtEnd()) return 0;
        return self.text[self.current];
    }

    fn peekNext(self: *Scanner) u8 {
        if (self.current + 1 >= self.text.len) return 0;
        return self.text[self.current + 1];
    }

    fn isAtEnd(self: *Scanner) bool {
        return self.current >= self.text.len;
    }

    fn makeToken(self: *Scanner, tokenType: TokenType) Token {
        return Token{
            .type = tokenType,
            .line = self.line,
            .value = self.text[self.start..self.current],
        };
    }

    fn errorToken(self: *Scanner, message: []const u8) Token {
        return Token{
            .type = .ERROR,
            .line = self.line,
            .value = message,
        };
    }

    // TODO: utf8
    fn advance(self: *Scanner) u8 {
        self.current += 1;
        return self.text[self.current - 1];
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.text[self.current] != expected) return false;
        self.current += 1;
        return true;
    }
};

test "scan empty string" {
    var scanner = Scanner.init("");
    const token = scanner.scanToken();
    try std.testing.expectEqual(.EOF, token.type);
}

test "scan single char tokens" {
    var scanner = Scanner.init("(){},.-+;*");

    const token = scanner.scanToken();
    try std.testing.expectEqual(.LEFT_PAREN, token.type);
    try std.testing.expectEqualStrings("(", token.value);

    const expected = [_]TokenType{ .RIGHT_PAREN, .LEFT_BRACE, .RIGHT_BRACE, .COMMA, .DOT, .MINUS, .PLUS, .SEMICOLON, .STAR, .EOF, .EOF };
    for (expected) |tokenType| {
        try std.testing.expectEqual(tokenType, scanner.scanToken().type);
    }
}

test "scan double char tokens" {
    var scanner = Scanner.init("!!====<<=>>=");
    const expected = [_]TokenType{ .BANG, .BANG_EQUAL, .EQUAL_EQUAL, .EQUAL, .LESS, .LESS_EQUAL, .GREATER, .GREATER_EQUAL, .EOF, .EOF };
    for (expected) |tokenType| {
        try std.testing.expectEqual(tokenType, scanner.scanToken().type);
    }
}

test "scan something else" {
    var scanner = Scanner.init("@");
    const token = scanner.scanToken();
    try std.testing.expectEqual(.ERROR, token.type);
    try std.testing.expectEqual("Unexpected character.", token.value);
}

test "skip whitespace" {
    var scanner = Scanner.init(" ! != ");
    const expected = [_]TokenType{ .BANG, .BANG_EQUAL, .EOF, .EOF };
    for (expected) |tokenType| {
        try std.testing.expectEqual(tokenType, scanner.scanToken().type);
    }
}

test "skip comments" {
    var scanner = Scanner.init("< // this is a comment\n >");
    const expected = [_]TokenType{ .LESS, .GREATER, .EOF, .EOF };
    for (expected) |tokenType| {
        try std.testing.expectEqual(tokenType, scanner.scanToken().type);
    }
}

test "line numbers" {
    var scanner = Scanner.init("< // this is a comment\n >");
    try std.testing.expectEqual(@as(usize, 1), scanner.scanToken().line);
    try std.testing.expectEqual(@as(usize, 2), scanner.scanToken().line);
}

test "scan strings" {
    var scanner = Scanner.init("\"hello world\"");
    const token = scanner.scanToken();
    try std.testing.expectEqual(.STRING, token.type);
    try std.testing.expectEqualStrings("hello world", token.value);
}

test "scan numbers" {
    var scanner = Scanner.init("123");
    const token = scanner.scanToken();
    try std.testing.expectEqual(.NUMBER, token.type);
    try std.testing.expectEqualStrings("123", token.value);
}

test "scan keywords" {
    var scanner = Scanner.init("and class else false fun for if nil or print return super this true var while");
    const expected = [_]TokenType{ .AND, .CLASS, .ELSE, .FALSE, .FUN, .FOR, .IF, .NIL, .OR, .PRINT, .RETURN, .SUPER, .THIS, .TRUE, .VAR, .WHILE };

    var buf = [_]u8{0} ** 7; // long enough for any keyword
    for (expected) |tokenType| {
        const token = scanner.scanToken();

        try std.testing.expectEqual(tokenType, token.type);

        const identifier = std.ascii.lowerString(buf[0..], @tagName(tokenType));
        try std.testing.expectEqualStrings(identifier, token.value);
    }
}

test "scan identifiers" {
    var scanner = Scanner.init("hello_world");
    const token = scanner.scanToken();
    try std.testing.expectEqual(.IDENTIFIER, token.type);
    try std.testing.expectEqualStrings("hello_world", token.value);
}
