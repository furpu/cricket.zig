test {
    _ = @import("Parser.zig");
    // Formats
    _ = @import("formats/der.zig");
    _ = @import("formats/pem.zig");
    // Utils
    _ = @import("utils/base128.zig");
}
