const std = @import("std");
const mem = std.mem;

const Header = @import("Header.zig");
const Reader = @import("Reader.zig");
const internal = @import("internal.zig");

pub const ReadError = error{
    NonCanonical,
    Empty,
    MaxUnusedBitsExceeded,
    OidTooLong,
} || Reader.ReadError;

pub const CastError = error{Overflow};

pub const Any = struct {
    tag: ?Header.Tag,
    bytes: []const u8,

    pub fn read(reader: *Reader) ReadError!Any {
        const header = try reader.readHeader();
        const bytes = try reader.readBytes(header.length);

        return .{ .tag = header.tag, .bytes = bytes };
    }

    pub fn readValue(reader: *Reader, length: u28) ReadError!Any {
        const bytes = try reader.readBytes(length);
        return .{ .tag = null, .bytes = bytes };
    }
};

/// Signed arbitrary precision ASN.1 `INTEGER` type.
pub const Integer = struct {
    /// Bytes representing the signed integer in two's complement representation.
    bytes: []const u8,

    /// Reads an integer from the given reader.
    /// Expects class bits to be UNIVERSAL.
    ///
    /// Caller is responsible for saving and restoring the reader's position.
    pub fn read(reader: *Reader) ReadError!Integer {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.integer), .universal);
        return readValue(reader, header.length);
    }

    /// Reads an integer value of the given length from the given reader.
    pub fn readValue(reader: *Reader, length: u28) ReadError!Integer {
        const bytes = try reader.readBytes(length);
        try validateCanonical(bytes);

        return .{ .bytes = bytes };
    }

    /// Tries to cast the integer to the given Zig integer type.
    ///
    /// Returns error.Overflow if the integer doesn't fit in the requested type.
    pub fn cast(self: Integer, comptime IntT: type) CastError!IntT {
        const type_info = @typeInfo(IntT).Int;
        if (type_info.bits / 8 < self.bytes.len) return error.Overflow;

        var val = mem.readVarInt(IntT, self.bytes, .big);

        // If we got a negative number we must extend the sign bit if IntT is bigger
        // than the Integer.
        //
        // TODO: find a better algorithm.
        if (self.bytes[0] & 0x80 == 0x80 and type_info.signedness == .signed) {
            const num_bits = self.bytes.len * 8;
            for (num_bits..type_info.bits) |b| {
                val = val | (@as(IntT, 1) << @intCast(b));
            }
        }

        return val;
    }

    fn validateCanonical(bytes: []const u8) ReadError!void {
        if (bytes.len == 0) return error.NonCanonical;
        if (bytes.len == 1) return;
        const not_valid = (bytes[0] == 0 and bytes[1] < 0x80) or (bytes[0] == 0xFF and bytes[1] >= 0x80);
        if (not_valid) return error.NonCanonical;
    }
};

/// ASN.1 `BIT STRING` type.
pub const BitString = struct {
    /// Bytes representing the bit string.
    bytes: []const u8,
    /// Number of unused bits in the final octet.
    unused_bits_count: u3,

    pub fn read(reader: *Reader) ReadError!BitString {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.bit_string), .universal);
        return readValue(reader, header.length);
    }

    pub fn readValue(reader: *Reader, length: u28) ReadError!BitString {
        if (length < 1) return error.Empty;

        const unused_bits_byte = try reader.readByte();
        if (unused_bits_byte > 7) return error.MaxUnusedBitsExceeded;

        const bytes = try reader.readBytes(length - 1);

        return .{
            .bytes = bytes,
            .unused_bits_count = @intCast(unused_bits_byte),
        };
    }
};

/// ASN.1 `OCTET STRING` type.
pub const OctetString = struct {
    /// Octet string bytes.
    bytes: []const u8,

    pub fn read(reader: *Reader) ReadError!OctetString {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.octet_string), .universal);
        return readValue(reader, header.length);
    }

    pub fn readValue(reader: *Reader, length: u28) ReadError!OctetString {
        const bytes = try reader.readBytes(length);

        return .{ .bytes = bytes };
    }

    /// Models a type that is DER encoded inside the bytes of an `OCTET STRING` value.
    pub fn Nested(comptime T: type) type {
        return struct {
            value: T,

            pub const __der_oc_str_nested: void = {};

            const Self = @This();

            pub fn read(reader: *Reader) !Self {
                const octet_string = try OctetString.read(reader);
                var bytes_reader = Reader.init(octet_string.bytes);
                const value = try internal.read(T, &bytes_reader, .{});

                return .{ .value = value };
            }
        };
    }
};

/// ASN.1 `NULL` type.
pub const Null = struct {
    pub fn read(reader: *Reader) ReadError!Null {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.null), .universal);
        return readValue(reader, header.length);
    }

    pub fn readValue(_: *Reader, length: u28) ReadError!Null {
        if (length > 0) return error.NonCanonical;
        return .{};
    }
};

/// ASN.1 `OBJECT IDENTIFIER` type.
pub const ObjectIdentifier = struct {
    /// Bytes representing the OID.
    bytes: []const u8,

    /// Taken from https://github.com/RustCrypto/formats/blob/master/const-oid/src/lib.rs#L51.
    /// Limits the length of OIDs.
    const max_length = 39;

    pub fn read(reader: *Reader) ReadError!ObjectIdentifier {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.object_identifier), .universal);
        return readValue(reader, header.length);
    }

    pub fn readValue(reader: *Reader, length: u28) ReadError!ObjectIdentifier {
        if (length > max_length) return error.OidTooLong;
        const bytes = try reader.readBytes(length);

        return .{ .bytes = bytes };
    }
};

/// ASN.1 `SEQUENCE` type.
pub const Sequence = struct {
    /// Bytes containing data of the sequence's elements.
    bytes: []const u8,

    pub fn read(reader: *Reader) ReadError!Sequence {
        const header = try reader.readHeaderExact(@intFromEnum(Header.Tag.UniversalTagNumber.sequence), .universal);
        if (!header.tag.getConstructed()) return error.NonCanonical;
        return readValue(reader, header.length);
    }

    pub fn readValue(reader: *Reader, length: u28) ReadError!Sequence {
        const bytes = try reader.readBytes(length);
        return .{ .bytes = bytes };
    }

    pub fn der_reader(self: Sequence) Reader {
        return Reader.init(self.bytes);
    }
};

pub const TagMode = enum(u1) {
    implicit,
    explicit,
};

/// Wrapper type for reading context specific values.
pub fn ContextSpecific(comptime T: type, comptime M: TagMode, tag_number: comptime_int) type {
    return switch (M) {
        .implicit => struct {
            value: T,

            const Self = @This();
            pub const __der_ctx_spc: void = {};

            // TODO: should return error.NonCanonical if the inner value requires the constructed flag to be set.
            pub fn read(reader: *Reader) !Self {
                const header = try reader.readHeaderExact(tag_number, .context_specific);
                const bytes = try reader.readBytes(header.length);

                var bytes_reader = Reader.init(bytes);
                const value = try internal.read(T, &bytes_reader, .{ .value_only = @intCast(bytes.len) });

                return .{ .value = value };
            }
        },
        .explicit => struct {
            value: T,

            const Self = @This();
            pub const __der_ctx_spc: void = {};

            pub fn read(reader: *Reader) ReadError!Self {
                // TODO: verify lengths provided by headers?
                const header = try reader.readHeaderExact(tag_number, .context_specific);
                const bytes = try reader.readBytes(header.length);

                var bytes_reader = Reader.init(bytes);
                const value = try internal.read(T, &bytes_reader, .{});

                return .{ .value = value };
            }
        },
    };
}

inline fn universalTagNumber(num: Header.Tag.UniversalTagNumber) u5 {
    return @intFromEnum(num);
}

test "Integer.read" {
    // Happy path
    var reader = Reader.init(&.{ 2, 1, 5 });
    try std.testing.expectEqualDeep(Integer{ .bytes = &.{5} }, try Integer.read(&reader));

    try testAcceptsCorrectTagClass(
        Integer,
        &.{4},
        .{ .bytes = &.{4} },
        .{ .tag = universalTagNumber(.integer) },
    );
}

test "Integer.cast" {
    // Canonical reprs work
    const test_cases_canonical = [_]struct { bytes: []const u8, expected: i32 }{
        .{ .bytes = &.{ 2, 1, 1 }, .expected = 1 },
        .{ .bytes = &.{ 2, 2, 0, 0x80 }, .expected = 128 },
        .{ .bytes = &.{ 2, 1, 0x80 }, .expected = -128 },
        .{ .bytes = &.{ 2, 2, 0xFF, 0x7F }, .expected = -129 },
    };
    for (test_cases_canonical) |test_case| {
        var r = Reader.init(test_case.bytes);
        const i = try Integer.read(&r);
        const fixed_i = try i.cast(i32);
        try std.testing.expectEqual(test_case.expected, fixed_i);
    }

    // Non-canonical reprs fail with error
    const test_cases_noncanonical = [_][]const u8{
        &.{ 2, 2, 0xFF, 0xF0 }, // Negative with leading ones byte
        &.{ 2, 2, 0x00, 0x03 }, // Positive with leading zeroes byte
    };
    for (test_cases_noncanonical) |test_case| {
        var r = Reader.init(test_case);
        try std.testing.expectError(error.NonCanonical, Integer.read(&r));
    }
}

test "BitString.read" {
    // Happy path
    var reader = Reader.init(&.{ 3, 3, 5, 0x05, 0x42 });
    try std.testing.expectEqualDeep(
        BitString{ .unused_bits_count = 5, .bytes = &.{ 0x05, 0x42 } },
        try BitString.read(&reader),
    );

    // Invalid unused bits
    reader = Reader.init(&.{ 3, 2, 8, 0x00, 0x01 });
    try std.testing.expectError(error.MaxUnusedBitsExceeded, BitString.read(&reader));

    try testAcceptsCorrectTagClass(
        BitString,
        &.{ 5, 0x05, 0x42 },
        .{ .unused_bits_count = 5, .bytes = &.{ 0x05, 0x42 } },
        .{ .tag = universalTagNumber(.bit_string) },
    );
}

test "OctetString.read" {
    // Happy path
    var reader = Reader.init(&.{ 4, 2, 1, 2 });
    try std.testing.expectEqualDeep(
        OctetString{ .bytes = &.{ 1, 2 } },
        try OctetString.read(&reader),
    );

    try testAcceptsCorrectTagClass(
        OctetString,
        &.{ 3, 4 },
        .{ .bytes = &.{ 3, 4 } },
        .{ .tag = universalTagNumber(.octet_string) },
    );
}

test "Null.read" {
    // Happy path
    var reader = Reader.init(&.{ 5, 0 });
    try std.testing.expectEqualDeep(Null{}, try Null.read(&reader));

    // Non-canonical
    reader = Reader.init(&.{ 5, 40, 0 });
    try std.testing.expectError(error.NonCanonical, Null.read(&reader));

    try testAcceptsCorrectTagClass(Null, &.{}, Null{}, .{ .tag = universalTagNumber(.null) });
}

test "ObjectIdentifier.read" {
    // Happy path
    var reader = Reader.init(&.{ 6, 3, 1, 2, 3 });
    try std.testing.expectEqualDeep(
        ObjectIdentifier{ .bytes = &.{ 1, 2, 3 } },
        ObjectIdentifier.read(&reader),
    );

    // Max length exceeded
    reader = Reader.init(&.{ 6, 43, 0 });
    try std.testing.expectError(error.OidTooLong, ObjectIdentifier.read(&reader));

    try testAcceptsCorrectTagClass(
        ObjectIdentifier,
        &.{ 1, 2, 3 },
        .{ .bytes = &.{ 1, 2, 3 } },
        .{ .tag = universalTagNumber(.object_identifier) },
    );
}

test "Sequence.read" {
    // Happy path
    var reader = Reader.init(&.{ 48, 2, 5, 0 });
    try std.testing.expectEqualDeep(
        Sequence{ .bytes = &.{ 5, 0 } },
        try Sequence.read(&reader),
    );

    try testAcceptsCorrectTagClass(
        Sequence,
        &.{ 2, 1, 4 },
        .{ .bytes = &.{ 2, 1, 4 } },
        .{
            .tag = universalTagNumber(.sequence),
            .constructed = true,
        },
    );
}

test "ContextSpecific.read implicit" {
    var reader = Reader.init(&.{ 133, 1, 9 });
    const expected = ContextSpecific(Integer, .implicit, 5){ .value = .{ .bytes = &.{9} } };
    try std.testing.expectEqualDeep(expected, try ContextSpecific(Integer, .implicit, 5).read(&reader));

    // TODO: Test constructed flag

    try testAcceptsCorrectTagClass(
        ContextSpecific(Integer, .implicit, 3),
        &.{5},
        .{ .value = .{ .bytes = &.{5} } },
        .{ .tag = 3, .class = .context_specific },
    );
}

test "ContextSpecific.read explicit" {
    var reader = Reader.init(&.{ 0xa0 | 3, 3, 2, 1, 9 });
    const expected = ContextSpecific(Integer, .explicit, 3){ .value = .{ .bytes = &.{9} } };
    try std.testing.expectEqualDeep(expected, try ContextSpecific(Integer, .explicit, 3).read(&reader));

    try testAcceptsCorrectTagClass(
        ContextSpecific(Integer, .explicit, 3),
        &.{ 2, 1, 5 },
        .{ .value = .{ .bytes = &.{5} } },
        .{ .tag = 3, .class = .context_specific },
    );
}

const TestAcceptsParams = struct {
    tag: u5,
    class: Header.Tag.Class = .universal,
    constructed: bool = false,
};

fn testAcceptsCorrectTagClass(comptime T: type, comptime value: []const u8, expected: T, params: TestAcceptsParams) !void {
    // Rejects tags != tag
    try testAcceptsTagExclusive(T, value, expected, params);
    // Rejects non-universal classes
    try testAcceptsClassExclusive(T, value, expected, params);
}

fn testAcceptsTagExclusive(comptime T: type, comptime value: []const u8, expected: T, params: TestAcceptsParams) !void {
    var tag_number: u5 = 0;
    while (true) : (tag_number += 1) {
        const tag_byte = tag_number | (@as(u8, @intFromEnum(params.class)) << 6) | (@as(u8, @intFromBool(params.constructed)) << 5);
        var reader = Reader.init(&[2]u8{ tag_byte, value.len } ++ value);

        if (tag_number == params.tag) {
            try std.testing.expectEqualDeep(expected, try T.read(&reader));
        } else {
            try std.testing.expectError(error.UnexpectedTag, T.read(&reader));
        }

        if (tag_number == 31) break;
    }
}

fn testAcceptsClassExclusive(comptime T: type, comptime value: []const u8, expected: T, params: TestAcceptsParams) !void {
    const class_type_info = @typeInfo(Header.Tag.Class).Enum;
    inline for (class_type_info.fields) |field| {
        // We modify the tag to set the class bits.
        const tag_byte = @as(u8, params.tag) | (field.value << 6) | (@as(u8, @intFromBool(params.constructed)) << 5);
        var reader = Reader.init(&[2]u8{ tag_byte, value.len } ++ value);

        if (field.value == @intFromEnum(params.class)) { // Universal
            try std.testing.expectEqualDeep(expected, try T.read(&reader));
        } else {
            try std.testing.expectError(error.UnexpectedClass, T.read(&reader));
        }
    }
}