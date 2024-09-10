//! DER codec header.

const std = @import("std");

/// Header tag.
tag: Tag,
/// Header content length.
///
/// As in https://github.com/RustCrypto/formats/blob/master/der/src/length.rs,
/// I'm deciding to limit the content length in order to simplify the library.
///
/// Maximum length is 256 MiB which makes up to 28 bits.
length: u28,

/// Maximum allowed length (256 MiB).
pub const length_max = 0xfffffff;

/// ASN.1 tags.
///
/// They are described in X.690 Section 8.1.2: Identifier octets, and
/// structured as follows:
///
/// ```text
/// | Class | P/C | Tag Number |
/// ```
///
/// - Bits 8/7: [`Class`]
/// - Bit 6: primitive (0) or constructed (1)
/// - Bits 5-1: tag number
pub const Tag = union(Class) {
    /// Universal tag.
    universal: Component(UniversalTagNumber),
    /// Application specific tag.
    application: Component(u5),
    /// Context specific tag.
    context_specific: Component(u5),
    /// Private tag number.
    private: Component(u5),

    /// Component holds the actual tag data and allows customizing the tag number type.
    pub fn Component(comptime TagT: type) type {
        return struct {
            constructed: bool,
            number: TagT,
        };
    }

    pub fn rawComponentFromTagByte(byte: u8) Component(u5) {
        return .{
            .constructed = byte & 0b100000 == 0b100000,
            .number = @intCast(byte & 0b11111),
        };
    }

    /// Canonical tag numbers.
    pub const UniversalTagNumber = enum(u5) {
        boolean = 1,
        integer = 2,
        bit_string = 3,
        octet_string = 4,
        null = 5,
        object_identifier = 6,
        real = 9,
        enumerated = 10,
        utf8_string = 12,
        sequence = 16,
        set = 17,
        numeric_string = 18,
        printable_string = 19,
        teletex_string = 20,
        videotex_string = 21,
        ia5_string = 22,
        utc_time = 23,
        generalized_time = 24,
        visible_string = 26,
        general_string = 27,
        bmp_string = 30,
    };

    /// ANS.1 tag class.
    pub const Class = enum(u2) {
        universal,
        application,
        context_specific,
        private,

        /// Decodes the class from a given tag byte.
        pub fn fromTagByte(b: u8) Class {
            const class_bits: u2 = @intCast((b >> 6) & 0b11);
            return @enumFromInt(class_bits);
        }
    };

    /// Returns the tag's constructed flag.
    pub fn getConstructed(self: Tag) bool {
        return switch (self) {
            inline else => |t| t.constructed,
        };
    }

    /// Returns the tag's number.
    pub fn getNumber(self: Tag) u5 {
        return switch (self) {
            .universal => |u| @intFromEnum(u.number),
            inline else => |t| t.number,
        };
    }

    /// Returns the tag's class.
    pub fn getClass(self: Tag) Class {
        return std.meta.activeTag(self);
    }
};
