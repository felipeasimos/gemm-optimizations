const std = @import("std");
const matrix = @import("../matrix.zig");
const Matrix = matrix.Matrix;
const checkDimensions = matrix.checkDimensions;

fn calculateBlockside(comptime T: type) usize {
    const target_cache_size_in_bytes = 128 * 1024;
    const side_of_block_in_bytes = std.math.sqrt(target_cache_size_in_bytes);
    return side_of_block_in_bytes / @sizeOf(T);
}

inline fn microkernel(comptime T: type, comptime n_acc: usize, si: usize, sj: usize, i: usize, j: usize, c: *Matrix(T), a_packed: Matrix(T), b_packed: Matrix(T)) void {
    const vec_len = std.simd.suggestVectorLength(T).?;
    const nk = a_packed.n_columns;

    const remaining_cols =
        b_packed.n_columns - j;

    const active_lanes =
        @min(vec_len, remaining_cols);

    // Tail mask
    var mask: @Vector(vec_len, bool) = undefined;
    inline for (0..vec_len) |lane| {
        mask[lane] = lane < active_lanes;
    }

    var accs: [n_acc]@Vector(vec_len, T) = .{.{0} ** vec_len} ** n_acc;

    switch (c.major) {
        // broadcast A
        .RowMajor => {
            var k: usize = 0;
            while (k < nk) : (k += 1) {
                // reuse B through accumulators
                const b_raw_index = b_packed.getRawIndex(.{ k, j });
                // Safe temporary load
                var b_tmp: [vec_len]T = .{0} ** vec_len;
                inline for (0..vec_len) |lane| {
                    if (lane < active_lanes) {
                        b_tmp[lane] = b_packed.data[b_raw_index + lane];
                    }
                }
                const b_row: @Vector(vec_len, T) = b_tmp;
                inline for (0..n_acc) |acc_idx| {
                    if (i + acc_idx < a_packed.n_rows) {
                        const a_splat: @Vector(vec_len, T) = @splat(a_packed.getConst(.{ i + acc_idx, k }));

                        switch (comptime @typeInfo(T)) {
                            .int => accs[acc_idx] = (a_splat *% b_row) +% accs[acc_idx],
                            .float => accs[acc_idx] = @mulAdd(@Vector(vec_len, T), a_splat, b_row, accs[acc_idx]),
                            inline else => @compileError("nope"),
                        }
                    }
                }
            }
            inline for (0..n_acc) |acc_idx| {
                if (i + acc_idx < a_packed.n_rows) {
                    const c_raw_index = c.getRawIndex(.{ si + i + acc_idx, sj + j });
                    inline for (0..vec_len) |lane| {
                        if (lane < active_lanes) {
                            switch (@typeInfo(T)) {
                                .int => c.data[c_raw_index..][lane] +%= accs[acc_idx][lane],
                                .float => c.data[c_raw_index..][lane] += accs[acc_idx][lane],
                                inline else => @compileError("nope"),
                            }
                        }
                    }
                }
            }
        },
        // broadcast B
        .ColumnMajor => {},
    }
}

inline fn pack(comptime T: type, m: Matrix(T), b_row: usize, b_column: usize, dst: *Matrix(T)) void {
    const actual_rows = @min(dst.n_rows, m.n_rows - b_row);
    const actual_cols = @min(dst.n_columns, m.n_columns - b_column);

    dst.n_rows = actual_rows;
    dst.n_columns = actual_cols;

    switch (m.major) {
        .RowMajor => {
            for (0..actual_cols) |j| {
                for (0..actual_rows) |i| {
                    dst.get(.{ i, j }).* = m.getConst(.{ b_row + i, b_column + j });
                }
            }
        },
        .ColumnMajor => {
            for (0..actual_rows) |i| {
                for (0..actual_cols) |j| {
                    dst.get(.{ i, j }).* = m.getConst(.{ b_row + i, b_column + j });
                }
            }
        },
    }
}

/// A (i, k)
/// B (k, j)
/// C (i, j)
/// TODO: make it column major friendly for C matrices
fn Worker(comptime T: type) type {
    const blockside = calculateBlockside(T);
    const vec_len = std.simd.suggestVectorLength(T).?;
    const n_acc = 4;
    return struct {
        pub fn macrokernel(si: usize, sj: usize, c: *Matrix(T), a: Matrix(T), b: Matrix(T)) void {
            const nk = b.n_rows;

            var buf: [blockside * blockside * 2]T = undefined;
            var buf_allocator = std.heap.FixedBufferAllocator.init(std.mem.asBytes(&buf));
            const allocator = buf_allocator.threadSafeAllocator();

            var a_packed = Matrix(T).init(
                allocator,
                blockside,
                blockside,
                .ColumnMajor,
            ) catch @panic("not enough space in allocated buffer");
            var b_packed = Matrix(T).init(
                allocator,
                blockside,
                blockside,
                .RowMajor,
            ) catch @panic("not enough space in allocated buffer");

            // iterate through A and B strides
            var k: usize = 0;
            while (k < nk) : (k += blockside) {
                a_packed.n_rows = blockside;
                a_packed.n_columns = blockside;
                b_packed.n_rows = blockside;
                b_packed.n_columns = blockside;

                pack(T, a, si, k, &a_packed);
                pack(T, b, k, sj, &b_packed);
                // iterate through A and B microtiles
                var i: usize = 0;
                while (i < a_packed.n_rows) : (i += n_acc) {
                    var j: usize = 0;
                    while (j < b_packed.n_columns) : (j += vec_len) {
                        microkernel(T, n_acc, si, sj, i, j, c, a_packed, b_packed);
                    }
                }
            }
        }
    };
}

/// A (i, k)
/// B (k, j)
/// C (i, j)
pub fn multikernel(comptime T: type, io: std.Io, c: *Matrix(T), a: Matrix(T), b: Matrix(T)) !void {
    std.debug.assert(checkDimensions(T, c.*, a, b));
    const ni = a.n_rows;
    const nj = b.n_columns;

    const blockside = calculateBlockside(T);

    var group = std.Io.Group.init;

    var si: usize = 0;
    while (si < ni) : (si += blockside) {
        var sj: usize = 0;
        while (sj < nj) : (sj += blockside) {
            try group.concurrent(io, Worker(T).macrokernel, .{ si, sj, c, a, b });
        }
    }
    try group.await(io);
}

test multikernel {
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
    c.zero();
    try multikernel(u32, std.testing.io, &c, a, b);

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
