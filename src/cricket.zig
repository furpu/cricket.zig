const std = @import("std");

pub const formats = struct {
    pub const der = @import("formats/der.zig");
    pub const pem = @import("formats/pem.zig");
};

pub const utils = struct {
    pub const base128 = @import("utils/base128.zig");
};

test {
    comptime {
        std.testing.refAllDeclsRecursive(formats);
        std.testing.refAllDeclsRecursive(utils);
    }
}
