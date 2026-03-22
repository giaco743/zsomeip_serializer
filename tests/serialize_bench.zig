const std = @import("std");
const zsip = @import("libzsip");

test "bench" {
    const start = std.time.milliTimestamp();

    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const DeployedTest = zsip.Deployed(Test, struct {}{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var buffer: [1024]u8 = undefined; // your buffer

    for (0..1000000) |i| {
        const given = Test{
            .a = @truncate(i),
            .b = @truncate(i + 100),
            .c = @truncate(i + 100000),
        };
        const givenStruct = DeployedTest.wrap(given);

        const size = try zsip.serialize(givenStruct, &buffer);

        var deser = zsip.Deserializer.init(gpa.allocator(), buffer[0..size]);
        _ = try deser.deserialize(DeployedTest);
    }
    const end = std.time.milliTimestamp();
    std.debug.print("elapsed ms = {}\n", .{end - start});
}
