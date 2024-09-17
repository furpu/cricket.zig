const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const formats = @import("formats.zig");

pub const KeyKind = enum {
    ecdsa_private_key,
    ecdsa_public_key,
};

pub const Value = struct {
    kind: KeyKind,
    bytes: []const u8,
};

pub const Decoded = struct {
    arena: *ArenaAllocator,
    value: Value,

    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
};

pub fn fromPem(allocator: Allocator, input: []const u8) !Decoded {
    var parsed_pem = try formats.Pem.parse(allocator, input);
    errdefer parsed_pem.deinit();

    const value = try valueFromPem(parsed_pem);
    return .{ .arena = parsed_pem.arena, .value = value };
}

fn valueFromPem(pem: formats.Pem) !Value {
    if (mem.eql(u8, pem.label, "PRIVATE KEY")) {
        const ki = try formats.der.read(formats.pkcs8.PrivateKeyInfo(formats.der.Any), pem.msg);
        if (ki.private_key_algorithm.oid.matches(&formats.ecdsa.public_key_oid)) {
            const ec = try ki.private_key.value.cast(formats.ecdsa.EcPrivateKey);
            return .{ .kind = .ecdsa_private_key, .bytes = ec.private_key };
        } else {
            return error.UnsupportedAlgorithm;
        }
    } else if (mem.eql(u8, pem.label, "EC PRIVATE KEY")) {
        const ki = try formats.der.read(formats.ecdsa.EcPrivateKey, pem.msg);
        return .{ .kind = .ecdsa_private_key, .bytes = ki.private_key };
    } else if (mem.eql(u8, pem.label, "PUBLIC KEY")) {
        const ki = try formats.der.read(formats.spki.SubjectPublicKeyInfo(formats.der.Any), pem.msg);
        if (ki.algorithm_identifier.oid.matches(&formats.ecdsa.public_key_oid)) {
            return .{ .kind = .ecdsa_public_key, .bytes = ki.public_key.bytes };
        }

        return error.UnsupportedAlgorithm;
    }

    return error.UnknownEncoding;
}

test fromPem {
    {
        const pem_str =
            \\-----BEGIN PRIVATE KEY-----
            \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg5fO+1/F+4LjfbyZt
            \\SoxLYv9FT0g+d3Xy4BJC5OUtuoOhRANCAAS7f9EGs8aM7kv1i32chypBpWdqnp7B
            \\aRZfEo9iTtP+URSVZMoHB61NVi3GPnzFdluC2bZE9Pp1LcekFHXuJZLk
            \\-----END PRIVATE KEY-----"
        ;

        var decoded = try fromPem(std.testing.allocator, pem_str);
        defer decoded.deinit();

        try std.testing.expect(decoded.value.kind == .ecdsa_private_key);
    }

    {
        const pem_str =
            \\-----BEGIN EC PRIVATE KEY-----
            \\MHcCAQEEIBezuGPLhf9lbyjSueaDsHAqhtVdkidIOGA0hGSAQWpxoAoGCCqGSM49
            \\AwEHoUQDQgAERCLP+nS0QlG7w+IpnlDkv4GgbrKZy5GYY7Bnt0NIMDR9hvx75Q55
            \\1B3XrGcpzF3lzG2EUsjdYsc8kMEiP2OEJg==
            \\-----END EC PRIVATE KEY-----
        ;

        var decoded = try fromPem(std.testing.allocator, pem_str);
        defer decoded.deinit();

        try std.testing.expect(decoded.value.kind == .ecdsa_private_key);
    }

    {
        const pem_str =
            \\-----BEGIN PUBLIC KEY-----
            \\MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEVs/o5+uQbTjL3chynL4wXgUg2R9
            \\q9UU8I5mEovUf86QZ7kOBIjJwqnzD1omageEHWwHdBO6B+dFabmdT9POxg==
            \\-----END PUBLIC KEY-----
        ;

        var decoded = try fromPem(std.testing.allocator, pem_str);
        defer decoded.deinit();

        try std.testing.expect(decoded.value.kind == .ecdsa_public_key);
    }
}
