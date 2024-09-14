pub const formats = struct {
    pub const der = @import("formats/der.zig");
    pub const ecdsa = @import("formats/ecdsa.zig");
    pub const Pem = @import("formats/Pem.zig");
    pub const pkcs8 = @import("formats/pkcs8.zig");
    pub const spki = @import("formats/spki.zig");
};

pub const utils = struct {
    pub const vlq = @import("utils/vlq.zig");
};

const std = @import("std");

test {
    comptime {
        std.testing.refAllDeclsRecursive(formats);
        std.testing.refAllDeclsRecursive(utils);
    }
}
