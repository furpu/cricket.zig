const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const ascii = std.ascii;

pub const der = @import("der.zig");
const Parser = @import("Parser.zig");

const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Pem = struct {
    arena: *ArenaAllocator,
    label: []const u8,
    msg: []const u8,

    pub fn deinit(self: Pem) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
};

pub fn parse(allocator: Allocator, input: []const u8) !Pem {
    var p = PemParser{ .inner = .{ .input = input } };
    const parsed = p.parse(allocator) catch |err| {
        // TODO: Remove this and add proper error messages to Parser.
        // I'm putting this here just to aid debugging for now.
        if (builtin.is_test) std.debug.print("\"{s}\"\n", .{p.inner.input[p.inner.cursor..]});
        return err;
    };

    return parsed;
}

const PemParser = struct {
    inner: Parser,

    const b64_decoder = std.base64.standard.Decoder;
    const preeb_start_str = "-----BEGIN ";
    const eb_end_str = "-----";

    pub fn parse(self: *PemParser, allocator: Allocator) !Pem {
        var parsed = Pem{ .arena = undefined, .label = undefined, .msg = undefined };
        parsed.arena = try allocator.create(ArenaAllocator);
        parsed.arena.* = ArenaAllocator.init(allocator);
        errdefer parsed.deinit();

        parsed.label = try self.parsePreeb(parsed.arena.allocator());
        self.inner.skip(isWhitespace);
        try self.parseEol();

        parsed.msg = try self.parseMsg(parsed.arena.allocator());

        return parsed;
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

        // TODO: rollback cursor on error
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

    const PrivKeyInfo = struct {
        version: i32,
        alg: struct {
            algorithm: der.Value,
            parameters: ?der.Value,
        },
        key: []const u8,
        attributes: ?der.Value, // ignored
    };

    const EccKeyInfo = struct {
        idk: i32,
        key: [32]u8,
    };

    var parser = Parser{ .input = parsed.msg };
    const pki = try der.parse(PrivKeyInfo, &parser);

    parser = .{ .input = pki.key };
    const ki = try der.parse(EccKeyInfo, &parser);

    _ = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(ki.key);
}
