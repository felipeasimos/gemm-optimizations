const std = @import("std");
const gemm = @import("gemm");
const Matrix = gemm.matrix.Matrix;

fn GEMMBenchmarkFunc(comptime T: type, comptime func: anytype) type {
    return struct {
        // dims: (i, j, k)
        pub fn run(io: std.Io, c: *Matrix(T), a: Matrix(T), b: Matrix(T)) !std.Io.Duration {
            c.zero();
            const start = std.Io.Clock.awake.now(io);
            try @call(.auto, func, .{ T, io, c, a, b });
            return start.untilNow(io, .awake);
        }
    };
}

fn benchmark(io: std.Io) !void {
    const types: []const type = &.{ u64, u32, u16, u8, f64, f32, f16 };
    const sizes: []const usize = &.{ 32, 64, 128, 256, 512, 1024, 2048 };
    const blocklist: [2][]const u8 = .{ "naive", "evented" };
    // const blocklist: [][]const u8 = &.{};

    var data_dir = try std.Io.Dir.cwd().createDirPathOpen(io, "data", .{});
    defer data_dir.close(io);

    inline for (types) |T| {
        std.debug.print("type {s}\n", .{@typeName(T)});
        inline for (@typeInfo(gemm.impl).@"struct".decls) |decl| {
            std.debug.print("\tmethod {s}\n", .{decl.name});
            const filename = std.fmt.comptimePrint("{}_{s}.csv", .{ T, decl.name });
            var file = try data_dir.createFile(io, filename, .{});
            defer file.close(io);

            var buf: [1024]u8 = undefined;
            var file_writer = file.writer(io, &buf);
            try file_writer.interface.print("size,time\n", .{});

            const in_blocklist = comptime in_blocklist: {
                for (blocklist) |bl| {
                    if (std.mem.eql(u8, bl, decl.name)) {
                        break :in_blocklist true;
                    }
                }
                break :in_blocklist false;
            };
            if (in_blocklist) continue;
            inline for (sizes) |size| {
                std.debug.print("\t\tsize {}\n", .{size});
                var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena_allocator.deinit();
                const allocator = arena_allocator.allocator();

                var c = try Matrix(T).init(allocator, size, size, .RowMajor);
                defer c.deinit(allocator);
                var a = try Matrix(T).init(allocator, size, size, .RowMajor);
                defer a.deinit(allocator);
                var b = try Matrix(T).init(allocator, size, size, .RowMajor);
                defer b.deinit(allocator);

                const func = @field(@field(gemm.impl, decl.name), decl.name);
                const elapsed = try GEMMBenchmarkFunc(T, func).run(io, &c, a, b);
                try file_writer.interface.print("{},{}\n", .{
                    size,
                    elapsed.toMilliseconds(),
                });
            }
            try file_writer.interface.flush();
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try benchmark(io);
}
