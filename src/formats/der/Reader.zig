//! DER reader.

const Self = @This();

const std = @import("std");
const io = std.io;
const Header = @import("Header.zig");

stream: io.FixedBufferStream([]const u8),

pub const ReadError = error{
    UnexpectedTag,
    UnexpectedClass,
    LengthExceedsMax,
    IndefiniteLength,
    EndOfStream,
};

pub fn init(input: []const u8) Self {
    return .{ .stream = io.fixedBufferStream(input) };
}

pub fn readByte(self: *Self) ReadError!u8 {
    const byte = self.stream.reader().any().readByte() catch return error.EndOfStream;
    return byte;
}

pub fn readBytes(self: *Self, n: usize) ReadError![]const u8 {
    const pos = self.stream.pos;
    if (pos + n > self.stream.buffer.len) return error.EndOfStream;
    self.stream.pos = pos + n;
    return self.stream.buffer[pos..self.stream.pos];
}

pub fn readHeader(self: *Self) ReadError!Header {
    const tag = try self.readTag();
    const length = try self.readLength();
    return .{ .tag = tag, .length = length };
}

pub fn readHeaderExact(self: *Self, tag_number: u5, class: Header.Tag.Class) ReadError!Header {
    const header = try self.readHeader();
    if (header.tag.getClass() != class) return error.UnexpectedClass;
    if (header.tag.getNumber() != tag_number) return error.UnexpectedTag;
    return header;
}

pub fn readTag(self: *Self) ReadError!Header.Tag {
    const byte = self.stream.reader().any().readByte() catch return error.EndOfStream;
    const class = Header.Tag.Class.fromTagByte(byte);
    const raw = Header.Tag.rawComponentFromTagByte(byte);

    return switch (class) {
        .universal => blk: {
            // Check if the tag is a valid tag number. Return error if not.
            const tag_number = std.meta.intToEnum(Header.Tag.UniversalTagNumber, raw.number) catch return error.UnexpectedTag;
            const tag = Header.Tag{ .universal = Header.Tag.Component(Header.Tag.UniversalTagNumber){
                .constructed = raw.constructed,
                .number = tag_number,
            } };
            break :blk tag;
        },
        inline else => |t| blk: {
            const tag = @unionInit(Header.Tag, @tagName(t), raw);
            break :blk tag;
        },
    };
}

pub fn readLength(self: *Self) ReadError!u28 {
    const byte = self.stream.reader().any().readByte() catch return error.EndOfStream;

    // If the length byte is 0x80, this means indefinite length (which DER does not allow).
    //
    // If the first byte has the 8th bit set to 1 (i.e. > 0x80) then bits 7 to 1 represent
    // the length octets count that should be read further.
    //
    // If the first byte has the 8th bit set to 0 then it corresponds to the actual length.
    switch (byte) {
        0...0x7F => return @intCast(byte),
        0x80 => return error.IndefiniteLength,
        0x81...0x84 => |k| {
            const nbytes = k & 0x7F;
            var parsed_length: u32 = 0;
            for (0..nbytes) |_| {
                const length_byte = self.stream.reader().any().readByte() catch return error.EndOfStream;
                parsed_length = (parsed_length << 8) | length_byte;
            }
            if (parsed_length > Header.length_max) return error.LengthExceedsMax;
            return @intCast(parsed_length);
        },
        else => return error.LengthExceedsMax,
    }
}
