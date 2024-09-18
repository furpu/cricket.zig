//! X.509 `SubjectPublicKeyInfo`

const der = @import("der.zig");

/// X.509 `AlgorithmIdentifier` as defined in [RFC 5280 Section 4.1.1.2].
///
/// ```text
/// AlgorithmIdentifier  ::=  SEQUENCE  {
///      algorithm               OBJECT IDENTIFIER,
///      parameters              ANY DEFINED BY algorithm OPTIONAL  }
/// ```
///
/// [RFC 5280 Section 4.1.1.2]: https://tools.ietf.org/html/rfc5280#section-4.1.1.2
pub fn AlgorithmIdentifier(comptime ParamsT: type) type {
    return struct {
        oid: der.ObjectIdentifier,
        params: ?ParamsT,
    };
}

pub fn SubjectPublicKeyInfo(comptime ParamsT: type) type {
    return struct {
        algorithm_identifier: AlgorithmIdentifier(ParamsT),
        public_key: der.BitString,
    };
}

const std = @import("std");
const Pem = @import("Pem.zig");
const ec = @import("ec.zig");

test "decode" {
    const pem_str =
        \\-----BEGIN PUBLIC KEY-----
        \\MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEVs/o5+uQbTjL3chynL4wXgUg2R9
        \\q9UU8I5mEovUf86QZ7kOBIjJwqnzD1omageEHWwHdBO6B+dFabmdT9POxg==
        \\-----END PUBLIC KEY-----
    ;

    const parsed = try Pem.parse(std.testing.allocator, pem_str);
    defer parsed.deinit();

    const spki = try der.read(SubjectPublicKeyInfo(der.Any), parsed.msg);
    try std.testing.expect(spki.algorithm_identifier.oid.matches(&ec.public_key_oid));

    const params = try spki.algorithm_identifier.params.?.cast(ec.EcParameters);
    try std.testing.expect(params.named_curve.matches(&ec.secp256r1_oid));
}
