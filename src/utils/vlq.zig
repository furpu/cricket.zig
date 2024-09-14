//! Variable-length quantity integers encoding and decoding.

const std = @import("std");
const assert = std.debug.assert;
const Type = std.builtin.Type;

pub fn calcEncodeBufSize(val: anytype) usize {
    const float_type = switch (@typeInfo(@TypeOf(val))) {
        .int => |type_info| blk: {
            if (type_info.signedness == .signed) @compileError("Signed integer types are not supported");
            break :blk f64;
        },
        .comptime_int => blk: {
            break :blk comptime_float;
        },
        else => @compileError("Only integer types are supported"),
    };

    return @intFromFloat(@ceil((@ceil(@log2(@as(float_type, @floatFromInt(val + 1)))) / 7.0)));
}

pub fn encode(val: anytype, buf: []u8) []const u8 {
    // TODO: support comptime_int?
    const type_info = @typeInfo(@TypeOf(val)).int;
    if (type_info.signedness == .signed) @compileError("Signed integer types are not supported");

    var offset: u16 = 0;
    var i: usize = buf.len;
    var prev_byte: ?u8 = null;
    while (true) {
        const byte: u8 = @truncate((val >> @intCast(offset)) & 0x7F);

        if (prev_byte) |prev| {
            // Stop if we read 2 bytes == 0 in a row
            if (prev == 0 and byte == 0) break;
            // Store the previous byte read and decide if we should set the 8th byte.
            i -= 1;
            buf[i] = prev;
            if (offset - 7 > 0) buf[i] |= 1 << 7;
        }

        prev_byte = byte;
        offset += 7;
        if (offset >= type_info.bits) break;
    }

    // Store the remaining byte, if any
    if (prev_byte) |prev| {
        if (prev > 0) {
            i -= 1;
            buf[i] = prev;
        }
    }

    return buf[i..];
}

pub fn calcDecodeBufSize(len: usize) usize {
    return len * 8 / 7;
}

pub fn decode(input: []const u8, buf: []u8) []const u8 {
    var in_cursor = input.len;
    var buf_cursor = buf.len;
    var bit_queue: u16 = 0;
    var bit_count: u4 = 0;
    while (in_cursor > 0) {
        in_cursor -= 1;
        bit_queue |= @as(u16, input[in_cursor] & 0x7F) << bit_count;
        bit_count += 7;
        if (bit_count >= 8) {
            buf_cursor -= 1;
            buf[buf_cursor] = @truncate(bit_queue & 0xFF);
            bit_queue >>= 8;
            bit_count -= 8;
        }
    }
    assert(bit_count <= 8);

    if (bit_count > 0) {
        buf_cursor -= 1;
        buf[buf_cursor] = @truncate(bit_queue & 0xFF);
    }

    const ret = buf[buf_cursor..];
    assert(ret.len == calcDecodeBufSize(input.len));

    return ret;
}

pub fn decodeInt(comptime T: type, input: []const u8) !T {
    if (calcDecodeBufSize(input.len) > @sizeOf(T)) return error.IntTypeTooSmall;
    var buf: [@sizeOf(T)]u8 = undefined;
    const decoded_slice = decode(input, &buf);

    return std.mem.readVarInt(T, decoded_slice, .big);
}

test "encode" {
    const test_val: u32 = 113549;
    var buf: [calcEncodeBufSize(test_val)]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &[_]u8{ 134, 247, 13 }, encode(test_val, &buf));
}

test "decode and decodeInt" {
    try std.testing.expectEqual(113549, decodeInt(u32, &.{ 134, 247, 13 }));
    try std.testing.expectEqual(840, decodeInt(u32, &.{ 134, 72 }));
    try std.testing.expectError(error.IntTypeTooSmall, decodeInt(u8, &.{ 134, 72 }));
}
