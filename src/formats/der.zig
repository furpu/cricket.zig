// References:
// - https://luca.ntop.org/Teaching/Appunti/asn1.html
// - https://github.com/RustCrypto/formats

const std = @import("std");

pub const Header = @import("der/Header.zig");
pub const Reader = @import("der/Reader.zig");
const internal = @import("der/internal.zig");
pub const types = @import("der/types.zig");
pub const Any = types.Any;
pub const BitString = types.BitString;
pub const ObjectIdentifier = types.ObjectIdentifier;
pub const ContextSpecific = types.ContextSpecific;

pub fn read(comptime T: type, input: []const u8) !T {
    var reader = Reader.init(input);
    return internal.read(T, &reader, .{});
}

const UniversalTagNumber = Header.Tag.UniversalTagNumber;

test "read Integer -> int" {
    const input = &.{ @intFromEnum(UniversalTagNumber.integer), 1, 3 };
    try std.testing.expectEqual(@as(i32, 3), try read(i32, input));
}

test "read OctetString -> []const u8" {
    const input = &.{ @intFromEnum(UniversalTagNumber.octet_string), 5, 1, 2, 3, 4, 5 };
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, try read([]const u8, input));
}

test "read Sequence -> struct" {
    const TestT = struct {
        i: i32,
        o: ?i16,
        s: []const u8,
    };

    // when optional value is not included in the sequence
    const input1 = &.{
        @intFromEnum(UniversalTagNumber.sequence) | @as(u8, 1) << 5, // TODO: implement a function to set tag bits
        8,
        @intFromEnum(UniversalTagNumber.integer),
        1,
        5,
        @intFromEnum(UniversalTagNumber.octet_string),
        3,
        1,
        2,
        3,
    };
    try std.testing.expectEqualDeep(TestT{ .i = 5, .s = &.{ 1, 2, 3 }, .o = null }, try read(TestT, input1));

    // with optional value included in the sequence
    const input2 = &.{
        @intFromEnum(UniversalTagNumber.sequence) | @as(u8, 1) << 5, // TODO: implement a function to set tag bits
        11,
        @intFromEnum(UniversalTagNumber.integer),
        1,
        5,
        @intFromEnum(UniversalTagNumber.integer),
        1,
        0xF5,
        @intFromEnum(UniversalTagNumber.octet_string),
        3,
        1,
        2,
        3,
    };
    try std.testing.expectEqualDeep(TestT{ .i = 5, .s = &.{ 1, 2, 3 }, .o = -11 }, try read(TestT, input2));
}

test "read" {
    // Union (CHOICE)
    {
        const TestUnion = union(enum) {
            s: []const u8,
            i: i32,
        };

        const input1 = &.{ @intFromEnum(UniversalTagNumber.integer), 1, 8 };
        try std.testing.expectEqualDeep(TestUnion{ .i = 8 }, try read(TestUnion, input1));

        const input2 = &.{ @intFromEnum(UniversalTagNumber.octet_string), 3, 'a', 'b', 'c' };
        try std.testing.expectEqualDeep(TestUnion{ .s = "abc" }, try read(TestUnion, input2));

        const input3 = &.{ @intFromEnum(UniversalTagNumber.bit_string), 1, 0 };
        try std.testing.expectError(error.Cast, read(TestUnion, input3));
    }
}
