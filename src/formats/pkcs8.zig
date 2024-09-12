//! PKCS#8

const std = @import("std");

const der = @import("der.zig");
const Pem = @import("Pem.zig");
const spki = @import("spki.zig");

/// PKCS#8 `PrivateKeyInfo`.
///
/// ASN.1 structure containing an `AlgorithmIdentifier`, private key
/// data in an algorithm specific format, and optional attributes.
///
/// Supports PKCS#8 v1 as described in [RFC 5208] and PKCS#8 v2 as described
/// in [RFC 5958]. PKCS#8 v2 keys include an additional public key field.
///
/// # PKCS#8 v1 `PrivateKeyInfo`
///
/// Described in [RFC 5208 Section 5]:
///
/// ```text
/// PrivateKeyInfo ::= SEQUENCE {
///         version                   Version,
///         privateKeyAlgorithm       PrivateKeyAlgorithmIdentifier,
///         privateKey                PrivateKey,
///         attributes           [0]  IMPLICIT Attributes OPTIONAL }
///
/// Version ::= INTEGER
///
/// PrivateKeyAlgorithmIdentifier ::= AlgorithmIdentifier
///
/// PrivateKey ::= OCTET STRING
///
/// Attributes ::= SET OF Attribute
/// ```
///
/// # PKCS#8 v2 `OneAsymmetricKey`
///
/// PKCS#8 `OneAsymmetricKey` as described in [RFC 5958 Section 2]:
///
/// ```text
/// PrivateKeyInfo ::= OneAsymmetricKey
///
/// OneAsymmetricKey ::= SEQUENCE {
///     version                   Version,
///     privateKeyAlgorithm       PrivateKeyAlgorithmIdentifier,
///     privateKey                PrivateKey,
///     attributes            [0] Attributes OPTIONAL,
///     ...,
///     [[2: publicKey        [1] PublicKey OPTIONAL ]],
///     ...
///   }
///
/// Version ::= INTEGER { v1(0), v2(1) } (v1, ..., v2)
///
/// PrivateKeyAlgorithmIdentifier ::= AlgorithmIdentifier
///
/// PrivateKey ::= OCTET STRING
///
/// Attributes ::= SET OF Attribute
///
/// PublicKey ::= BIT STRING
/// ```
///
/// [RFC 5208]: https://tools.ietf.org/html/rfc5208
/// [RFC 5958]: https://datatracker.ietf.org/doc/html/rfc5958
/// [RFC 5208 Section 5]: https://tools.ietf.org/html/rfc5208#section-5
/// [RFC 5958 Section 2]: https://datatracker.ietf.org/doc/html/rfc5958#section-2
pub fn PrivateKeyInfo(comptime ParamsT: type, comptime PrivKeyT: type) type {
    return struct {
        version: u8,
        private_key_algorithm: spki.AlgorithmIdentifier(ParamsT),
        private_key: der.types.OctetString.Nested(PrivKeyT),
        attributes: ?der.ContextSpecific(der.Any, .implicit, 0),
        public_key: ?der.ContextSpecific(der.BitString, .implicit, 1),

        const Self = @This();

        pub inline fn decode(input: []const u8) !Self {
            return der.read(Self, input);
        }
    };
}

test "parse" {
    const pem_str =
        \\-----BEGIN PRIVATE KEY-----
        \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2
        \\OF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r
        \\1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G
        \\-----END PRIVATE KEY-----
    ;

    const parsed = try Pem.parse(std.testing.allocator, pem_str);
    defer parsed.deinit();

    const EccKeyInfo = struct {
        version: i32,
        key: [32]u8,
    };

    const pki = try PrivateKeyInfo(der.Any, EccKeyInfo).decode(parsed.msg);

    // var buffer: [17]u8 = .{0} ** 17;
    // var stream = std.io.fixedBufferStream(&buffer);
    // try pki.alg.algorithm.print(stream.writer().any());
    // try std.testing.expectEqualStrings("1.2.840.10045.2.1", stream.buffer);

    _ = try std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey.fromBytes(pki.private_key.value.key);
}
