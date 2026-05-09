const std = @import("std");

pub const Layout = enum {
    RowMajor,
    ColumnMajor,
};

pub fn Matrix(comptime T: type) type {
    return struct {
        data: []T,
        n_rows: usize,
        n_columns: usize,
        major: Layout,
        pub fn init(allocator: std.mem.Allocator, n_rows: usize, n_columns: usize, major: Layout) !@This() {
            return .{
                .data = try allocator.alloc(T, n_rows * n_columns),
                .n_rows = n_rows,
                .n_columns = n_columns,
                .major = major,
            };
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }
        fn getRawIndex(self: *const @This(), dims: struct { usize, usize }) usize {
            if (self.major == .RowMajor) {
                return dims[0] * self.n_columns + dims[1];
            }
            return dims[1] * self.n_rows + dims[0];
        }
        pub fn get(self: *@This(), dims: struct { usize, usize }) *T {
            return &self.data[self.getRawIndex(dims)];
        }
        pub fn getConst(self: *const @This(), dims: struct { usize, usize }) T {
            return self.data[self.getRawIndex(dims)];
        }
        pub fn zero(self: *@This()) void {
            @memset(self.data, 0);
        }
        pub fn format(self: *const @This(), w: *std.Io.Writer) !void {
            var buf: [64]u8 = undefined;
            _ = try w.write("start matrix\n");
            for (0..self.n_rows) |i| {
                _ = try w.write("{ ");
                for (0..self.n_columns) |j| {
                    const T_as_str = std.fmt.bufPrint(&buf, "{}", .{self.getConst(.{ i, j })}) catch "T couldn't be printed";
                    _ = try w.write(T_as_str);
                    if (j == self.n_columns - 1) {
                        _ = try w.write(" }");
                    } else {
                        _ = try w.write(", ");
                    }
                }
                _ = try w.write("\n");
            }
            _ = try w.write("end matrix\n");
        }
    };
}

pub fn checkDimensions(comptime T: type, c: Matrix(T), a: Matrix(T), b: Matrix(T)) bool {
    return !(c.n_rows != a.n_rows or
        c.n_columns != b.n_columns or
        a.n_columns != b.n_rows);
}

test Matrix {
    var a = try Matrix(f32).init(std.testing.allocator, 2, 2, .RowMajor);
    defer a.deinit(std.testing.allocator);
}

test checkDimensions {
    {
        var a = try Matrix(f32).init(std.testing.allocator, 2, 2, .RowMajor);
        defer a.deinit(std.testing.allocator);
        var b = try Matrix(f32).init(std.testing.allocator, 2, 2, .RowMajor);
        defer b.deinit(std.testing.allocator);
        var c = try Matrix(f32).init(std.testing.allocator, 2, 2, .RowMajor);
        defer c.deinit(std.testing.allocator);
        try std.testing.expect(checkDimensions(f32, c, a, b));
    }

    {
        var a = try Matrix(f32).init(std.testing.allocator, 4, 3, .RowMajor);
        defer a.deinit(std.testing.allocator);
        var b = try Matrix(f32).init(std.testing.allocator, 3, 2, .RowMajor);
        defer b.deinit(std.testing.allocator);
        var c = try Matrix(f32).init(std.testing.allocator, 4, 2, .RowMajor);
        defer c.deinit(std.testing.allocator);
        try std.testing.expect(checkDimensions(f32, c, a, b));
    }
}
