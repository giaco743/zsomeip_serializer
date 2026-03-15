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
    var buffer = [_]u8{0} ** 128;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    for (0..1000000) |i| {
        const given = Test{
            .a = @truncate(i),
            .b = @truncate(i + 100),
            .c = @truncate(i + 100000),
        };
        const givenStruct = DeployedTest.wrap(given);

        const size = try zsip.serialize.serialize(givenStruct, buffer[0..]);

        var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), buffer[0..size]);
        defer deser.deinit();
        _ = try deser.deserialize(DeployedTest);
    }
    const end = std.time.milliTimestamp();
    std.debug.print("elapsed ms = {}\n", .{end - start});
}
