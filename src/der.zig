// Reference: https://luca.ntop.org/Teaching/Appunti/asn1.html

const std = @import("std");
const big = std.math.big;
const builtin = @import("builtin");
const mem = std.mem;

const base128 = @import("base128.zig");
const Parser = @import("Parser.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Tag = enum(u5) {
    integer = 2,
    bit_string = 3,
    octet_string = 4,
    null = 5,
    object_identifier = 6,
    sequence = 16,
    set = 17,
    _,
};

pub fn parse(comptime T: type, parser: *Parser) !T {
    const parser_cursor_start = parser.cursor;
    errdefer parser.cursor = parser_cursor_start;

    switch (T) {
        Value => return Value.parseOne(parser),
        Value.BitString => {
            const val = try Value.parseOne(parser);
            return val.asBitString();
        },
        Value.ObjectIdentifier => {
            const val = try Value.parseOne(parser);
            return val.asObjectIdentifier();
        },
        Value.Sequence => {
            const val = try Value.parseOne(parser);
            return val.asSequence();
        },
        Value.Set => {
            const val = try Value.parseOne(parser);
            return val.asSet();
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .Int => {
            const val = try Value.parseOne(parser);
            const int_val = try val.asInteger();

            return int_val.toFixed(T);
        },
        .Pointer => |ptr_type| {
            if (ptr_type.size != .Slice) @compileError("Pointer types must be slices");

            switch (ptr_type.child) {
                u8 => {
                    const val = try Value.parseOne(parser);
                    const octet_string_val = try val.asOctetString();

                    return @constCast(octet_string_val.bytes);
                },
                else => @compileError("Not a supported type"),
            }
        },
        .Array => |arr_type| {
            const slice_val = try parse([]arr_type.child, parser);
            if (slice_val.len != arr_type.len) return error.WrongArrayLength;

            var arr: T = undefined;
            @memcpy(&arr, slice_val);

            return arr;
        },
        .Struct => |struct_type| {
            const val = try Value.parseOne(parser);
            const seq = try val.asSequence();
            var seq_parser = Parser{ .input = seq.bytes };

            var ret_val: T = undefined;
            inline for (struct_type.fields) |field| {
                // Optional are only allowed inside structured types so we must test this here.
                switch (@typeInfo(field.type)) {
                    .Optional => |opt_info| {
                        @field(ret_val, field.name) = parse(opt_info.child, &seq_parser) catch blk: {
                            break :blk null;
                        };
                    },
                    else => {
                        @field(ret_val, field.name) = try parse(field.type, &seq_parser);
                    },
                }
            }

            return ret_val;
        },
        .Union => |union_type| {
            inline for (union_type.fields) |field| {
                if (parse(field.type, parser)) |val| {
                    return @unionInit(T, field.name, val);
                } else |err| switch (err) {
                    error.EndOfInput => return err,
                    else => {},
                }
            }
            return error.Cast;
        },
        else => @compileError("Not a supported type"),
    }
}

pub const Value = union(enum) {
    integer: Integer,
    bit_string: BitString,
    octet_string: OctetString,
    null,
    object_identifier: ObjectIdentifier,
    sequence: Sequence,
    set: Set,
    custom: Custom,

    pub const Integer = struct {
        bytes: []const u8,

        pub fn toFixed(self: Integer, comptime IntT: type) !IntT {
            const type_info = @typeInfo(IntT).Int;
            if (type_info.signedness != .signed) @compileError("Must be a signed int type");
            if (type_info.bits / 8 < self.bytes.len) return error.IntTypeTooSmall;

            var val = mem.readVarInt(IntT, self.bytes, .big);

            // If we got a negative number we must extend the sign bit
            // TODO: find a better algorithm.
            if (self.bytes[0] & 0x80 == 0x80) {
                const num_bits = self.bytes.len * 8;
                for (num_bits..type_info.bits) |b| {
                    val = val | (@as(IntT, 1) << @intCast(b));
                }
            }

            return val;
        }
    };

    pub const BitString = struct {
        bytes: []const u8,

        pub fn unusedBitsCount(self: BitString) u8 {
            if (self.bytes.len == 0) return 0;
            return self.bytes[0];
        }

        pub fn contents(self: BitString) []const u8 {
            if (self.bytes.len <= 1) return &.{};
            return self.bytes[1..];
        }
    };

    pub const OctetString = struct {
        bytes: []const u8,
    };

    pub const ObjectIdentifier = struct {
        bytes: []const u8,

        pub fn iterator(self: ObjectIdentifier) OidIterator {
            return OidIterator.init(self.bytes);
        }

        pub fn print(self: ObjectIdentifier, writer: std.io.AnyWriter) !void {
            var iter = self.iterator();
            var first = true;
            // TODO: using i64 here to allow for very large numbers but this smells.
            while (try iter.next(i64)) |v| {
                if (!first) try writer.writeByte('.');
                try writer.print("{}", .{v});
                first = false;
            }
        }
    };

    pub const Sequence = struct {
        bytes: []const u8,

        pub fn iterator(self: Sequence) ValueIterator {
            return ValueIterator.init(self.bytes);
        }
    };

    pub const Set = struct {
        bytes: []const u8,

        pub fn iterator(self: Set) ValueIterator {
            return ValueIterator.init(self.bytes);
        }
    };

    pub const Custom = struct {
        // TODO: Tags can be much larger than this but we still don't support
        // high tag numbers.
        tag: u8,
        bytes: []const u8,
    };

    pub fn parseOne(p: *Parser) !Value {
        const parser_cursor_start = p.cursor;
        errdefer p.cursor = parser_cursor_start;

        const tag_byte = try p.parseAny();
        if (tag_byte == 0x1F) {
            return error.HighTagNumberNotSupported;
        }
        const tag: Tag = @enumFromInt(tag_byte & 0x1F);

        const length_byte = try p.parseAny();
        var length: usize = undefined;
        if (length_byte & 0x80 == 0x80) {
            const max_octets_count = @sizeOf(usize);
            const octets_count: u8 = length_byte & 0x7F;

            // TODO: In the future we should allow bigger lengths but IDK.
            if (octets_count > max_octets_count) return error.LengthTooBig;

            var length_octets: [max_octets_count]u8 = .{0} ** max_octets_count;
            for (0..octets_count) |i| {
                length_octets[i] = try p.parseAny();
            }

            length = mem.readVarInt(usize, length_octets[0..octets_count], .big);
        } else {
            length = @intCast(length_byte);
        }

        const bytes = try p.parseAnyN(length);

        const val: Value = switch (tag) {
            .integer => .{ .integer = .{ .bytes = bytes } },
            .bit_string => .{ .bit_string = .{ .bytes = bytes } },
            .octet_string => .{ .octet_string = .{ .bytes = bytes } },
            .null => .null,
            .object_identifier => .{ .object_identifier = .{ .bytes = bytes } },
            .sequence => .{ .sequence = .{ .bytes = bytes } },
            .set => .{ .set = .{ .bytes = bytes } },
            _ => .{ .custom = .{ .tag = @intFromEnum(tag), .bytes = bytes } },
        };

        return val;
    }

    pub fn isNull(self: Value) bool {
        return self == .null;
    }

    pub fn asInteger(self: Value) !Integer {
        switch (self) {
            .integer => |i| return i,
            else => return error.Cast,
        }
    }

    pub fn asBitString(self: Value) !BitString {
        switch (self) {
            .bit_string => |s| return s,
            else => return error.Cast,
        }
    }

    pub fn asOctetString(self: Value) !OctetString {
        switch (self) {
            .octet_string => |s| return s,
            else => return error.Cast,
        }
    }

    pub fn asObjectIdentifier(self: Value) !ObjectIdentifier {
        switch (self) {
            .object_identifier => |oid| return oid,
            else => return error.Cast,
        }
    }

    pub fn asSequence(self: Value) !Sequence {
        switch (self) {
            .sequence => |s| return s,
            else => return error.Cast,
        }
    }

    pub fn asSet(self: Value) !Set {
        switch (self) {
            .set => |s| return s,
            else => return error.Cast,
        }
    }
};

pub const ValueIterator = struct {
    parser: Parser,

    pub fn init(bytes: []const u8) ValueIterator {
        return .{ .parser = .{ .input = bytes } };
    }

    pub fn next(self: *ValueIterator) !?Value {
        if (self.parser.peek() == null) return null;
        return try Value.parseOne(&self.parser);
    }
};

pub const OidIterator = struct {
    _c: usize = 0,
    parser: Parser,

    pub fn init(bytes: []const u8) OidIterator {
        return .{ .parser = .{ .input = bytes } };
    }

    pub fn next(self: *OidIterator, comptime IntT: type) !?IntT {
        const component = switch (self._c) {
            0 => self.parseFirstComponent(IntT),
            1 => self.parseSecondComponent(IntT),
            else => self.parseComponent(IntT),
        };
        self._c += 1;
        return component;
    }

    fn parseFirstComponent(self: *OidIterator, comptime IntT: type) ?IntT {
        if (self.parser.peek()) |b| {
            return switch (b) {
                0...39 => 0,
                40...79 => 1,
                else => 2,
            };
        }
        return null;
    }

    fn parseSecondComponent(self: *OidIterator, comptime IntT: type) ?IntT {
        var first_comp: IntT = undefined;
        if (self.parseFirstComponent(IntT)) |c| {
            first_comp = c;
        } else {
            return null;
        }

        const b = self.parser.parseAny() catch unreachable;
        if (first_comp == 2) return b - 80;
        return b % 40;
    }

    fn parseComponent(self: *OidIterator, comptime IntT: type) !?IntT {
        const max_byte_count = @sizeOf(IntT);
        const max_bit_count = max_byte_count * 8;

        const cursor_start = self.parser.cursor;
        var len: usize = 0;
        while (true) {
            const b = self.parser.parseAny() catch return null;
            len += 1;
            if (len * 7 > max_bit_count) return error.Overflow;
            if (b & 0x80 == 0) break;
        }

        self.parser.cursor = cursor_start;
        const bytes = self.parser.parseAnyN(len) catch unreachable;
        var buf: [@divTrunc(max_bit_count, 7)]u8 = undefined;

        return mem.readVarInt(IntT, base128.decode(bytes, &buf), .big);
    }

    fn hasNextByte(c: u8) bool {
        return c >> 7;
    }
};

test "parse" {
    // int
    var p = Parser{ .input = &.{ @intFromEnum(Tag.integer), 1, 3 } };
    try std.testing.expectEqual(@as(i32, 3), try parse(i32, &p));

    // octet string
    p = .{ .input = &.{ @intFromEnum(Tag.octet_string), 5, 1, 2, 3, 4, 5 } };
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, try parse([]const u8, &p));

    // Struct (sequence with optional)
    const TestT = struct {
        i: i32,
        o: ?i16,
        s: []const u8,
    };

    // when optional value is not included in the sequence
    p = .{ .input = &.{ @intFromEnum(Tag.sequence), 8, @intFromEnum(Tag.integer), 1, 5, @intFromEnum(Tag.octet_string), 3, 1, 2, 3 } };
    try std.testing.expectEqualDeep(TestT{ .i = 5, .s = &.{ 1, 2, 3 }, .o = null }, try parse(TestT, &p));

    // with optional value included in the sequence
    p = .{ .input = &.{ @intFromEnum(Tag.sequence), 11, @intFromEnum(Tag.integer), 1, 5, @intFromEnum(Tag.integer), 1, 0xF5, @intFromEnum(Tag.octet_string), 3, 1, 2, 3 } };
    try std.testing.expectEqualDeep(TestT{ .i = 5, .s = &.{ 1, 2, 3 }, .o = -11 }, try parse(TestT, &p));

    // Union (CHOICE)
    const TestUnion = union(enum) {
        s: []const u8,
        i: i32,
    };

    p = .{ .input = &.{ @intFromEnum(Tag.integer), 1, 8 } };
    try std.testing.expectEqualDeep(TestUnion{ .i = 8 }, try parse(TestUnion, &p));

    p = .{ .input = &.{ @intFromEnum(Tag.octet_string), 3, 'a', 'b', 'c' } };
    try std.testing.expectEqualDeep(TestUnion{ .s = "abc" }, try parse(TestUnion, &p));

    p = .{ .input = &.{ @intFromEnum(Tag.bit_string), 1, 0 } };
    try std.testing.expectError(error.Cast, parse(TestUnion, &p));
}

test "Value.parse" {
    const input = [_]u8{ @intFromEnum(Tag.integer), 2, 1, 3 };
    var p = Parser{ .input = &input };

    try std.testing.expectEqualDeep(Value{ .integer = .{ .bytes = input[2..] } }, Value.parseOne(&p));
}

test "Integer.toFixed" {
    const test_cases = [_]struct { val: Value.Integer, expected: i32 }{
        .{ .val = .{ .bytes = &.{1} }, .expected = 1 },
        .{ .val = .{ .bytes = &.{ 0, 0x80 } }, .expected = 128 },
        .{ .val = .{ .bytes = &.{0x80} }, .expected = -128 },
        .{ .val = .{ .bytes = &.{ 0xFF, 0x7F } }, .expected = -129 },
    };

    for (test_cases) |test_case| {
        try std.testing.expectEqual(test_case.expected, try test_case.val.toFixed(i32));
    }
}

test "ValueIterator" {
    var input = [_]u8{
        @intFromEnum(Tag.sequence),
        undefined,
        @intFromEnum(Tag.integer),
        2,
        1,
        2,
        @intFromEnum(Tag.null),
        0,
        @intFromEnum(Tag.octet_string),
        2,
        97,
        98,
    };
    input[1] = @intCast(input[2..].len);

    const expected = [_]Value{
        .{ .integer = .{ .bytes = input[4..6] } },
        .null,
        .{ .octet_string = .{ .bytes = input[10..12] } },
    };

    var parser = Parser{ .input = &input };
    const val = try Value.parseOne(&parser);
    const seq = try val.asSequence();

    var iter = seq.iterator();
    var i: usize = 0;
    while (try iter.next()) |elem_val| : (i += 1) {
        try std.testing.expectEqualDeep(expected[i], elem_val);
    }
}

test "OidIterator" {
    // Encoding of OID = "1.2.840.113549.1.1.5"
    var iter = OidIterator.init(&.{ 42, 134, 72, 134, 247, 13, 1, 1, 5 });
    const expected = [_]i32{ 1, 2, 840, 113549, 1, 1, 5 };

    var i: usize = 0;
    while (try iter.next(i32)) |v| : (i += 1) {
        try std.testing.expectEqual(expected[i], v);
    }
}
