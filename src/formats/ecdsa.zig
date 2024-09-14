const std = @import("std");

const der = @import("der.zig");

// Named curve OIDs from:
// https://datatracker.ietf.org/doc/html/rfc5480#section-2.1.1.1
pub const secp256r1_oid = der.ObjectIdentifier.fromArcStringComptime("1.2.840.10045.3.1.7");

/// Supported curves.
pub const Curve = enum {
    secp256r1,
};

/// Defined in: https://datatracker.ietf.org/doc/html/rfc5480
pub const EcParameters = union(enum) {
    named_curve: der.ObjectIdentifier,
};

/// Elliptic Curve private key structure as defined in:
/// https://datatracker.ietf.org/doc/html/rfc5915
pub const EcPrivateKey = struct {
    version: u8,
    private_key: []const u8,
    params: ?der.ContextSpecific(EcParameters, .explicit, 0),
    public_key: ?der.ContextSpecific(der.BitString, .explicit, 1),
};

const Pem = @import("Pem.zig");

test "decode" {
    const pem_str =
        \\-----BEGIN EC PRIVATE KEY-----
        \\MHcCAQEEIBezuGPLhf9lbyjSueaDsHAqhtVdkidIOGA0hGSAQWpxoAoGCCqGSM49
        \\AwEHoUQDQgAERCLP+nS0QlG7w+IpnlDkv4GgbrKZy5GYY7Bnt0NIMDR9hvx75Q55
        \\1B3XrGcpzF3lzG2EUsjdYsc8kMEiP2OEJg==
        \\-----END EC PRIVATE KEY-----
    ;

    const parsed = try Pem.parse(std.testing.allocator, pem_str);
    defer parsed.deinit();

    const pki = try der.read(EcPrivateKey, parsed.msg);
    try std.testing.expect(pki.params.?.value.named_curve.matches(&secp256r1_oid));

    var key_buf: [32]u8 = undefined;
    @memcpy(&key_buf, pki.private_key);
    _ = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(key_buf);
}
