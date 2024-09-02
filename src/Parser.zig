const std = @import("std");
const mem = std.mem;

input: []const u8,
cursor: usize = 0,

pub const Predicate = *const fn (c: u8) bool;

const Self = @This();

pub fn peek(self: Self) ?u8 {
    if (self.cursor >= self.input.len) return null;
    return self.input[self.cursor];
}

pub fn parseAny(self: *Self) !u8 {
    if (self.peek()) |c| {
        self.consume(1);
        return c;
    }
    return error.EndOfInput;
}

pub fn parseAnyN(self: *Self, n: usize) ![]const u8 {
    const start = self.getInput();
    for (0..n) |_| {
        _ = try self.parseAny();
    }
    return start[0..n];
}

pub fn parseMaybe(self: *Self, b: u8) bool {
    if (self.peek()) |c| {
        if (c == b) {
            self.consume(1);
            return true;
        }
    }
    return false;
}

pub fn parseOneOf(self: *Self, bs: []const u8) !u8 {
    if (self.peek()) |c| {
        for (bs) |b| {
            if (c == b) {
                self.consume(1);
                return b;
            }
        }
        return error.Parse;
    } else {
        return error.EndOfInput;
    }
}

pub fn parseString(self: *Self, s: []const u8) !void {
    if (!mem.startsWith(u8, self.getInput(), s)) return error.Parse;
    self.consume(s.len);
}

pub fn parseMany1(self: *Self, pred: Predicate) ![]const u8 {
    const at = self.getInput();

    var offset: usize = 0;
    while (self.peek()) |c| {
        if (!pred(c)) break;
        self.consume(1);
        offset += 1;
    }
    if (offset == 0) return error.Parse;

    return at[0..offset];
}

pub fn skip(self: *Self, pred: Predicate) void {
    while (self.peek()) |c| {
        if (!pred(c)) break;
        self.consume(1);
    }
}

inline fn getInput(self: Self) []const u8 {
    return self.input[self.cursor..];
}

inline fn consume(self: *Self, n: usize) void {
    self.cursor += n;
}

test "peek" {
    const input = "ab";

    var p = Self{ .input = input };
    try std.testing.expectEqual('a', p.peek());

    p.consume(1);
    try std.testing.expectEqual('b', p.peek());

    p.consume(1);
    try std.testing.expectEqual(null, p.peek());
}

test "parseMaybe" {
    const input = "ab";

    var p = Self{ .input = input };

    // Should not consume if doesn't match.
    try std.testing.expectEqual('a', p.peek());
    try std.testing.expect(!p.parseMaybe('b'));
    try std.testing.expectEqual('a', p.peek());

    // Should consume if matches
    try std.testing.expect(p.parseMaybe('a'));
    try std.testing.expectEqual('b', p.peek());
}

test "parseAny" {
    const input = "kab";

    var p = Self{ .input = input };
    try std.testing.expectEqual('k', try p.parseAny());
    try std.testing.expectEqual('a', p.peek());
}

test "parseAnyN" {
    const input = "abcdefg";

    var p = Self{ .input = input };
    try std.testing.expectEqualStrings("abcd", try p.parseAnyN(4));
    try std.testing.expectEqualStrings("efg", try p.parseAnyN(3));
    try std.testing.expectEqual(null, p.peek());
}

test "parseOneOf" {
    const input = "ab";

    var p = Self{ .input = input };
    try std.testing.expectEqual('a', try p.parseOneOf("kpa"));
    try std.testing.expectError(error.Parse, p.parseOneOf("acd"));
}

test "parseString" {
    const input = "somestrX to parse";

    var p = Self{ .input = input };
    try p.parseString("somestr");
    try std.testing.expectEqual('X', p.peek());
}

fn isAb(c: u8) bool {
    return c == 'a' or c == 'b';
}

test "parseMany1" {
    const input = "ababaabcde";

    var p = Self{ .input = input };

    try std.testing.expectEqualStrings("ababaab", try p.parseMany1(isAb));
    try p.parseString("cde");
}

test "skip" {
    const input = "ababaabcde";

    var p = Self{ .input = input };

    p.skip(isAb);
    try p.parseString("cde");
}
