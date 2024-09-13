const std = @import("std");

const der = @import("der.zig");

// Named curve OIDs from:
// https://datatracker.ietf.org/doc/html/rfc5480#section-2.1.1.1
const secp256r1_oid = der.ObjectIdentifier.fromArcStringComptime("1.2.840.10045.3.1.7");

// Defined in: https://datatracker.ietf.org/doc/html/rfc5480
pub const EcParameters = struct {
    named_curve: der.ObjectIdentifier,
};

// Elliptic Curve private key structure as defined in:
// https://datatracker.ietf.org/doc/html/rfc5915
pub fn EcPrivateKey(comptime key_size: usize) type {
    return struct {
        version: u8,
        private_key: [key_size]u8,
        params: ?der.ContextSpecific(EcParameters, .implicit, 0),
        public_key: ?der.ContextSpecific(der.BitString, .implicit, 1),
    };
}

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

    const pki = try der.read(EcPrivateKey(32), parsed.msg);
    try std.testing.expect(pki.params.?.value.matches(secp256r1_oid));

    _ = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(pki.private_key);
}
