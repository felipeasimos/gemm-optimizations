const std = @import("std");
pub const impl = @import("impl/impl.zig");
pub const matrix = @import("matrix.zig");

test "all" {
    _ = impl;
    _ = matrix;
}

