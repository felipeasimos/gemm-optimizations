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

// TODO: fix
inline fn microkernel(comptime T: type, c: *Matrix(T), a_packed: Matrix(T), b_packed: Matrix(T), bi: usize, bj: usize) void {
    const ni = a_packed.n_rows;
    const nj = b_packed.n_columns;
    const nk = a_packed.n_columns;

    const vec_len = std.simd.suggestVectorLength(T) orelse 8;

    switch (c.major) {
        // write horizontally to C
        .RowMajor => {
            for (0..ni) |i| {
                for (0..nk) |k| {
                    var j = 0;
                    while (j < nj) : (j += vec_len) {
                        switch (nj - j) {
                            inline 1...vec_len => |N| {
                                // broadcast A scalar
                                const b_raw_index = b_packed.getRawIndex(.{ k, 0 });
                                const b_row: @Vector(N, T) = b_packed.data[b_raw_index .. b_raw_index + N].*;
                                const a_splat: @Vector(N, T) = @splat(a_packed.getConst(.{ k, i }));
                                const c_raw_index = c.getRawIndex(.{ i, 0 });
                                const c_row: *@Vector(N, T) = &(c.data[c_raw_index .. c_raw_index + N].*);
                                c_row.* = @mulAdd(@Vector(N, T), a_splat, b_row, c_row.*);
                            },
                            _ => @panic("what"),
                        }
                    }
                }
            }
        },
        // write vertically to C
        .ColumnMajor => {
            for (0..nk) |k| {
                for (0..nj) |j| {
                    var i = 0;
                    while (i < ni) : (i += vec_len) {
                        switch (ni - i) {
                            inline 1...vec_len => |N| {
                                // broadcast A scalar
                                const a_raw_index = a_packed.getRawIndex(.{ k, 0 });
                                const b_row: @Vector(N, T) = a_packed.data[a_raw_index .. a_raw_index + N].*;
                                const a_splat: @Vector(N, T) = @splat(a_packed.getConst(.{ k, i }));
                                const c_raw_index = c.getRawIndex(.{ i, 0 });
                                const c_row: *@Vector(N, T) = &(c.data[c_raw_index .. c_raw_index + N].*);
                                c_row.* = @mulAdd(@Vector(N, T), a_splat, b_row, c_row.*);
                            },
                            _ => @panic("what"),
                        }
                    }
                }
            }
        },
    }
}

inline fn pack(comptime T: type, m: Matrix(T), b_row: usize, b_column: usize, dst: Matrix(T)) void {
    switch (m.major) {
        .RowMajor => {
            for (0..dst.n_columns) |j| {
                for (0..dst.n_rows) |i| {
                    dst.get(.{ i, j }).* = m.getConst(.{ b_row + i, b_column + j });
                }
            }
        },
        .ColumnMajor => {
            for (0..dst.n_rows) |i| {
                for (0..dst.n_columns) |j| {
                    dst.get(.{ i, j }).* = m.getConst(.{ b_row + i, b_column + j });
                }
            }
        },
    }
}

/// A (i, k)
/// B (k, j)
/// C (i, j)
pub fn kernel(comptime T: type, _: anytype, c: *Matrix(T), a: Matrix(T), b: Matrix(T)) !void {
    std.debug.assert(checkDimensions(T, c.*, a, b));
    // loops should favor continuous iteration of C
    // therefore, the matrix that has the same major of C will be the one iterated
    // in the inner loop
    const ni = a.n_rows;
    const nj = b.n_columns;
    const nk = b.n_rows;

    // one page per packed submatrix
    const blocksize = 64 / @sizeOf(T);
    var buf: [blocksize * blocksize * 2]T = undefined;
    var buf_allocator = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = buf_allocator.threadSafeAllocator();

    var a_packed: Matrix(T) = undefined;
    var b_packed: Matrix(T) = undefined;

    var bi: usize = 0;
    while (bi < ni) : (bi += blocksize) {
        const a_n_rows = @min(blocksize, ni - bi);
        var bj: usize = 0;
        while (bj < nj) : (bj += blocksize) {
            const b_n_columns = @min(blocksize, nj - bj);
            var bk: usize = 0;
            while (bk < nk) : (bk += blocksize) {
                const a_n_columns = @min(blocksize, nk - bk);
                a_packed = Matrix(T).init(
                    allocator,
                    a_n_rows,
                    a_n_columns,
                    .ColumnMajor,
                );
                defer a_packed.deinit(allocator);
                const b_n_rows = @min(blocksize, nk - bk);
                b_packed = Matrix(T).init(
                    allocator,
                    b_n_rows,
                    b_n_columns,
                    .ColumnMajor,
                );
                defer b_packed.deinit(allocator);
                pack(T, a, bi, bk, &a_packed);
                pack(T, b, bk, bj, &b_packed);
                microkernel(T, c, a_packed, b_packed, bi, bj);
            }
        }
    }
}

test kernel {
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
    try kernel(u32, std.testing.io, &c, a, b);

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
