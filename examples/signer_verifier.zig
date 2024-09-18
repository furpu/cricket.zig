const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const cricket = @import("cricket");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = Args.parse(allocator) catch |err| {
        switch (err) {
            error.InvalidOperation => std.debug.print("invalid operation (must be either 'sign' or 'verify')\n", .{}),
            error.MissingOperation => std.debug.print("missing operation ('sign' or 'verify')\n", .{}),
            error.MissingKeyFile => std.debug.print("missing key file\n", .{}),
            error.MissingMessage => std.debug.print("missing message\n", .{}),
            else => return err,
        }

        return 1;
    };
    defer args.deinit();

    switch (args.operation) {
        .sign => {
            const sig = try sign(allocator, args.key_file, args.msg);

            var encoded_sig = std.ArrayList(u8).init(allocator);
            defer encoded_sig.deinit();
            try std.base64.url_safe_no_pad.Encoder.encodeWriter(encoded_sig.writer().any(), &sig);

            std.debug.print("Signature: {s}\n", .{encoded_sig.items});
        },
        .verify => {
            var sig: []const u8 = undefined;
            if (args.sig) |s| {
                sig = s;
            } else {
                std.debug.print("missing signature\n", .{});
                return 1;
            }

            const decoded_sig_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(sig) catch {
                std.debug.print("invalid signature encoding\n", .{});
                return 1;
            };
            const decoded_sig = try allocator.alloc(u8, decoded_sig_len);
            defer allocator.free(decoded_sig);
            try std.base64.url_safe_no_pad.Decoder.decode(decoded_sig, sig);

            const valid_or_invalid = if (try verify(allocator, args.key_file, args.msg, decoded_sig)) "valid" else "invalid";

            std.debug.print("{s} signature\n", .{valid_or_invalid});
        },
    }

    return 0;
}

// Signing and verifying
fn sign(allocator: Allocator, priv_key_file: []const u8, msg: []const u8) ![64]u8 {
    var decoded_key = try keyFromFile(allocator, priv_key_file);
    defer decoded_key.deinit();

    var key_bytes: [32]u8 = undefined;
    @memcpy(&key_bytes, decoded_key.value.bytes);
    const sk = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(key_bytes);
    const kp = try std.crypto.sign.ecdsa.EcdsaP256Sha256.KeyPair.fromSecretKey(sk);

    const signature = try kp.sign(msg, null);
    return signature.toBytes();
}

fn verify(allocator: Allocator, pub_key_file: []const u8, msg: []const u8, sig: []const u8) !bool {
    var decoded_key = try keyFromFile(allocator, pub_key_file);
    defer decoded_key.deinit();

    const pk = try std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey.fromSec1(decoded_key.value.bytes);

    var sig_bytes: [64]u8 = undefined;
    @memcpy(&sig_bytes, sig);
    const signature = std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.fromBytes(sig_bytes);

    signature.verify(msg, pk) catch |err| {
        switch (err) {
            error.SignatureVerificationFailed => return false,
            else => return err,
        }
    };

    return true;
}

fn keyFromFile(allocator: Allocator, path: []const u8) !cricket.decode.Decoded {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const key_contents = try f.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(key_contents);

    return try cricket.decode.fromPem(allocator, key_contents);
}

// CLI stuff
const Operation = enum {
    sign,
    verify,

    pub fn fromString(s: []const u8) !Operation {
        if (mem.eql(u8, s, "sign")) return .sign;
        if (mem.eql(u8, s, "verify")) return .verify;
        return error.InvalidOperation;
    }
};

const Args = struct {
    arena: *ArenaAllocator,
    operation: Operation,
    key_file: []const u8,
    msg: []const u8,
    sig: ?[]const u8,

    pub fn parse(allocator: Allocator) !Args {
        const arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);

        var self = Args{
            .arena = arena,
            .operation = undefined,
            .key_file = undefined,
            .msg = undefined,
            .sig = null,
        };
        errdefer self.deinit();

        var args_iter = try std.process.argsWithAllocator(arena.allocator());

        // Skip executable path
        _ = args_iter.next();

        if (args_iter.next()) |operation| {
            self.operation = try Operation.fromString(operation);
        } else {
            return error.MissingOperation;
        }

        if (args_iter.next()) |key_file| {
            self.key_file = key_file;
        } else {
            return error.MissingKeyFile;
        }

        if (args_iter.next()) |msg| {
            self.msg = msg;
        } else {
            return error.MissingMessage;
        }

        self.sig = args_iter.next();

        return self;
    }

    pub fn deinit(self: *Args) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
};
