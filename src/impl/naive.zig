const std = @import("std");
const matrix = @import("../matrix.zig");
const Matrix = matrix.Matrix;
const checkDimensions = matrix.checkDimensions;

inline fn add(A: anytype, B: anytype) @TypeOf(A) {
    return switch (@typeInfo(@TypeOf(A))) {
        .float => A * B,
        .int => A *% B,
        inline else => @compileError("invalid type"),
    };
}

inline fn addToT(ptr: anytype, acc: anytype) void {
    switch (@typeInfo(@TypeOf(acc))) {
        .float => ptr.* += acc,
        .int => ptr.* +%= acc,
        inline else => @compileError("invalid type"),
    }
}

/// A (i, k)
/// B (k, j)
/// C (i, j)
pub fn naive(comptime T: type, _: anytype, c: *Matrix(T), a: Matrix(T), b: Matrix(T)) !void {
    std.debug.assert(checkDimensions(T, c.*, a, b));
    // loops should favor continuous iteration of C
    // therefore, the matrix that has the same major of C will be the one iterated
    // in the inner loop
    const ni = a.n_rows;
    const nj = b.n_columns;
    const nk = b.n_rows;
    switch (c.major) {
        .RowMajor => {
            if (b.major == .RowMajor) {
                for (0..ni) |i| {
                    for (0..nk) |k| {
                        const A = a.getConst(.{ i, k });
                        for (0..nj) |j| {
                            const B = b.getConst(.{ k, j });
                            addToT(c.get(.{ i, j }), add(A, B));
                        }
                    }
                }
                // if a doesn't match, well, nothing better to do
            } else {
                for (0..ni) |i| {
                    for (0..nj) |j| {
                        for (0..nk) |k| {
                            const A = a.getConst(.{ i, k });
                            const B = b.getConst(.{ k, j });
                            addToT(c.get(.{ i, j }), add(A, B));
                        }
                    }
                }
            }
        },

        .ColumnMajor => {
            if (a.major == .ColumnMajor) {
                for (0..nj) |j| {
                    for (0..nk) |k| {
                        const B = b.getConst(.{ k, j });
                        for (0..ni) |i| {
                            const A = a.getConst(.{ i, k });
                            addToT(c.get(.{ i, j }), add(A, B));
                        }
                    }
                }
                // if b doesn't match, well, nothing better to do
            } else {
                for (0..nj) |j| {
                    for (0..ni) |i| {
                        for (0..nk) |k| {
                            const A = a.getConst(.{ i, k });
                            const B = b.getConst(.{ k, j });

                            addToT(c.get(.{ i, j }), add(A, B));
                        }
                    }
                }
            }
        },
    }
}

test naive {
    var a = try Matrix(u32).init(std.testing.allocator, 4, 3, .RowMajor);
    defer a.deinit(std.testing.allocator);
    a.get(.{ 0, 0 }).* = 1;
    a.get(.{ 0, 1 }).* = 2;
    a.get(.{ 0, 2 }).* = 3;
    a.get(.{ 1, 0 }).* = 4;
    a.get(.{ 1, 1 }).* = 5;
    a.get(.{ 1, 2 }).* = 6;
    a.get(.{ 2, 0 }).* = 7;
    a.get(.{ 2, 1 }).* = 8;
    a.get(.{ 2, 2 }).* = 9;
    a.get(.{ 3, 0 }).* = 10;
    a.get(.{ 3, 1 }).* = 11;
    a.get(.{ 3, 2 }).* = 12;
    var b = try Matrix(u32).init(std.testing.allocator, 3, 2, .RowMajor);
    b.get(.{ 0, 0 }).* = 1;
    b.get(.{ 0, 1 }).* = 2;
    b.get(.{ 1, 0 }).* = 3;
    b.get(.{ 1, 1 }).* = 4;
    b.get(.{ 2, 0 }).* = 5;
    b.get(.{ 2, 1 }).* = 6;
    defer b.deinit(std.testing.allocator);
    var c = try Matrix(u32).init(std.testing.allocator, 4, 2, .RowMajor);
    defer c.deinit(std.testing.allocator);
    try naive(u32, {}, &c, a, b);

    try std.testing.expectEqualDeep(&[_]u32{
        22,
        28,
        49,
        64,
        76,
        100,
        103,
        136,
    }, c.data);
}
