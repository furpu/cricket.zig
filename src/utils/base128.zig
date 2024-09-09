const std = @import("std");
const assert = std.debug.assert;

pub fn calcBufSize(len: usize) usize {
    return len * 8 / 7;
}

pub fn calcBufSizeComptime(len: comptime_int) comptime_int {
    return @divTrunc(len * 8, 7);
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

    return buf[buf_cursor..];
}

test "decode" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(113549, std.mem.readVarInt(u32, decode(&.{ 134, 247, 13 }, &buf), .big));
    try std.testing.expectEqual(840, std.mem.readVarInt(u32, decode(&.{ 134, 72 }, &buf), .big));
}
