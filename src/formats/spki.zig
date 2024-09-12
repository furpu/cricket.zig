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
