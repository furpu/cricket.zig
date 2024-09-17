pub const decode = @import("decode.zig");
pub const formats = @import("formats.zig");

pub const utils = struct {
    pub const vlq = @import("utils/vlq.zig");
};

const std = @import("std");

test {
    comptime {
        std.testing.refAllDecls(decode);
        std.testing.refAllDeclsRecursive(formats);
        std.testing.refAllDeclsRecursive(utils);
    }
}
