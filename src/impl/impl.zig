pub const naive = @import("naive.zig");
pub const async = @import("async.zig");
pub const concurrent = @import("concurrent.zig");
pub const evented = @import("evented.zig");
pub const kernel = @import("kernel.zig");
pub const multikernel = @import("multikernel.zig");

test "all" {
    _ = naive;
    _ = async;
    _ = concurrent;
    _ = kernel;
    _ = multikernel;
}
