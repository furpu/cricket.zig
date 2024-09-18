const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const ascii = std.ascii;
const Allocator = mem.Allocator;
const Parser = @import("Pem/Parser.zig");

const Self = @This();

allocator: Allocator,
label: []const u8,
msg: []const u8,

pub fn deinit(self: Self) void {
    self.allocator.free(self.label);
    self.allocator.free(self.msg);
}

pub fn parse(allocator: Allocator, input: []const u8) !Self {
    var p = PemParser{ .inner = .{ .input = input } };
    return p.parse(allocator);
}

const PemParser = struct {
    inner: Parser,

    const b64_decoder = std.base64.standard.Decoder;
    const preeb_start_str = "-----BEGIN ";
    const eb_end_str = "-----";

    pub fn parse(self: *PemParser, allocator: Allocator) !Self {
        const label = try self.parsePreeb(allocator);
        errdefer allocator.free(label);
        self.inner.skip(isWhitespace);
        try self.parseEol();

        const msg = try self.parseMsg(allocator);

        return .{ .allocator = allocator, .label = label, .msg = msg };
    }

    fn parsePreeb(self: *PemParser, allocator: Allocator) ![]const u8 {
        try self.inner.parseString(preeb_start_str);
        const label = try self.parseLabel(allocator);
        try self.inner.parseString(eb_end_str);

        return label;
    }

    fn parseLabel(self: *PemParser, allocator: Allocator) ![]const u8 {
        const cursor_start = self.inner.cursor;
        errdefer self.inner.cursor = cursor_start;

        const label_slice = try self.inner.parseMany1(isLabelChar);
        const label = try allocator.alloc(u8, label_slice.len);
        @memcpy(label, label_slice);

        return label;
    }

    fn parseMsg(self: *PemParser, allocator: Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        while (self.inner.peek()) |c| {
            // Start of posteeb
            if (c == '-') break;

            const line = try self.inner.parseMany1(isBase64Char);
            const slice = try buffer.addManyAsSlice(try b64_decoder.calcSizeForSlice(line));
            try b64_decoder.decode(slice, line);

            try self.parseEol();
        }

        if (buffer.items.len == 0) return "";

        return buffer.toOwnedSlice();
    }

    fn parseEol(self: *PemParser) !void {
        const c = try self.inner.parseOneOf("\r\n");
        if (c == '\r') _ = self.inner.parseMaybe('\n');
    }

    fn isWhitespace(c: u8) bool {
        return c != '\n' and c != '\r' and ascii.isWhitespace(c);
    }

    fn isLabelChar(c: u8) bool {
        return c != '-' and ascii.isPrint(c);
    }

    fn isBase64Char(c: u8) bool {
        return ascii.isAlphanumeric(c) or c == '+' or c == '/' or c == '=';
    }
};

test parse {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testParseAllocations, .{});
}

fn testParseAllocations(allocator: Allocator) !void {
    const pem_str =
        \\-----BEGIN THELABEL-----
        \\-----END THELABEL-----
    ;

    const parsed = try parse(allocator, pem_str);
    defer parsed.deinit();
}
