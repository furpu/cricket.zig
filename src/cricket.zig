pub const decode = @import("decode.zig");
pub const formats = @import("formats.zig");

pub const utils = struct {
    pub const vlq = @import("utils/vlq.zig");
};

const std = @import("std");

test {
    comptime {
        std.testing.refAllDeclsRecursive(@This());
    }
}
