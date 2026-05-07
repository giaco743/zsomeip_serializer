const std = @import("std");
const zsip = @import("libzsip");

fn benchmark(alloc: std.mem.Allocator) (std.mem.Allocator.Error || zsip.SerializeError)!void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const start = std.Io.Timestamp.now(io, .real);

    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const DeployedTest = zsip.Deployed(Test, struct {}{});

    var buffer: [1024]u8 = undefined; // your buffer

    for (0..1000000) |i| {
        const given = Test{
            .a = @truncate(i),
            .b = @truncate(i + 100),
            .c = @truncate(i + 100000),
        };
        const givenStruct = DeployedTest.wrap(given);

        const size = try zsip.serialize(givenStruct, &buffer);

        _ = try zsip.deserialize(DeployedTest, alloc, buffer[0..size]);
    }
    const end = std.Io.Timestamp.now(io, .real);
    std.debug.print("elapsed ns = {}\n", .{start.durationTo(end)});
}

test "bench" {
    const alloc = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(alloc, benchmark, .{});
}
