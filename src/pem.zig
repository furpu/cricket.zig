const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const ascii = std.ascii;

const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Parsed = struct {
    arena: *ArenaAllocator,
    label: []const u8,
    msg: []const u8,

    pub fn deinit(self: Parsed) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
};

pub fn parse(allocator: Allocator, input: []const u8) !Parsed {
    var p = Parser{ .input = input };
    const parsed = p.parse(allocator) catch |err| {
        // TODO: Remove this and add proper error messages to Parser.
        // I'm putting this here just to aid debugging for now.
        if (builtin.is_test) std.debug.print("{s}\n", .{p.getInput()});
        return err;
    };

    return parsed;
}

const Parser = struct {
    cursor: usize = 0,
    input: []const u8,

    const b64_decoder = std.base64.standard.Decoder;
    const preeb_start_str = "-----BEGIN ";
    const eb_end_str = "-----";

    pub fn parse(self: *Parser, allocator: Allocator) !Parsed {
        var parsed = Parsed{ .arena = undefined, .label = undefined, .msg = undefined };
        parsed.arena = try allocator.create(ArenaAllocator);
        parsed.arena.* = ArenaAllocator.init(allocator);
        errdefer parsed.deinit();

        parsed.label = try self.parsePreeb(parsed.arena.allocator());
        self.skipWhitespace();
        try self.parseEol();

        parsed.msg = try self.parseMsg(parsed.arena.allocator());

        return parsed;
    }

    fn parsePreeb(self: *Parser, allocator: Allocator) ![]const u8 {
        try self.parsePreebStart();
        const label = try self.parseLabel(allocator);
        try self.parsePreebEnd();

        return label;
    }

    fn parsePreebStart(self: *Parser) !void {
        if (!mem.startsWith(u8, self.getInput(), preeb_start_str)) return error.Parse;
        try self.consume(preeb_start_str.len);
    }

    fn parsePreebEnd(self: *Parser) !void {
        if (!mem.startsWith(u8, self.getInput(), eb_end_str)) return error.Parse;
        try self.consume(eb_end_str.len);
    }

    fn parseLabel(self: *Parser, allocator: Allocator) ![]const u8 {
        const label_slice = try self.parseMany(isLabelChar);

        // TODO: rollback cursor on error
        const label = try allocator.alloc(u8, label_slice.len);
        @memcpy(label, label_slice);

        return label;
    }

    fn parseMsg(self: *Parser, allocator: Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        while (true) {
            // Start of posteeb
            if (self.getInput()[0] == '-') break;

            const line = try self.parseMany(isBase64Char);
            const slice = try buffer.addManyAsSlice(try b64_decoder.calcSizeForSlice(line));
            try b64_decoder.decode(slice, line);

            try self.parseEol();
        }

        if (buffer.items.len == 0) return "";

        return buffer.toOwnedSlice();
    }

    fn parseEol(self: *Parser) !void {
        const input_start = self.getInput();
        if (input_start[0] != '\r' and input_start[0] != '\n') return error.Parse;

        if (self.getInput()[0] == '\r') try self.consume(1);
        if (self.getInput()[0] == '\n') try self.consume(1);
    }

    fn parseMany(self: *Parser, pred_fn: *const fn (c: u8) bool) ![]const u8 {
        var offset: usize = 0;
        while (true) : (offset += 1) {
            const input = try self.getInputOffset(offset);
            if (!pred_fn(input[0])) break;
        }

        if (offset == 0) return error.Parse;

        const parsed = self.getInput();
        try self.consume(offset);

        return parsed[0..offset];
    }

    fn skipWhitespace(self: *Parser) void {
        while (true) {
            const input = self.getInput();
            if (input[0] == '\n' or input[0] == '\r' or !ascii.isWhitespace(input[0])) {
                break;
            }
            self.consume(1) catch break;
        }
    }

    fn getInput(self: Parser) []const u8 {
        return self.getInputOffset(0) catch unreachable;
    }

    fn getInputOffset(self: Parser, offset: usize) ![]const u8 {
        const start = self.cursor + offset;
        if (start >= self.input.len) return error.EndOfInput;

        return self.input[start..];
    }

    fn consume(self: *Parser, n: usize) !void {
        const cursor_after = self.cursor + n;
        if (cursor_after >= self.input.len) return error.EndOfInput;
        self.cursor = cursor_after;
    }

    fn rollback(self: *Parser, n: usize) void {
        self.cursor -= n;
    }

    fn isLabelChar(c: u8) bool {
        return c != '-' and ascii.isPrint(c);
    }

    fn isBase64Char(c: u8) bool {
        return ascii.isAlphanumeric(c) or c == '+' or c == '/';
    }
};

test "parse" {
    const pem_str =
        \\-----BEGIN PRIVATE KEY-----
        \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2
        \\OF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r
        \\1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G
        \\-----END PRIVATE KEY-----
    ;

    const parsed = try parse(std.testing.allocator, pem_str);
    defer parsed.deinit();
}
