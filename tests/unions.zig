const std = @import("std");
const zsip = @import("libzsip");

test "default deployment" {
    const TestUnion = union(enum) {
        uint8: u8,
        uint16: u16,
        uint32: u32,
    };
    const DeployedTest = zsip.Deployed(TestUnion, zsip.UnionDeployment{});
    const given = TestUnion{
        .uint16 = 2,
    };
    const givenUnion = DeployedTest.wrap(given);
    const expectedOut = given;
    const expected = [_]u8{ 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02 };

    var buffer: [1024]u8 = undefined; // your buffer
    const bytes_written = try zsip.serialize(givenUnion, &buffer);
    try std.testing.expectEqualSlices(u8, expected[0..], buffer[0..bytes_written]);

    const alloc = std.heap.smp_allocator;
    const deserialized = try zsip.deserialize(DeployedTest, alloc, expected[0..]);
    try std.testing.expectEqual(expectedOut, deserialized);
}

test "deployment" {
    const TestUnion = union(enum) {
        uint8: u8,
        uint16: u16,
        uint32: u32,
    };
    const DeployedTest = zsip.Deployed(TestUnion, zsip.UnionDeployment{ .lengthWidth = zsip.Width.U8, .typeWidth = zsip.Width.U8 });
    const given = TestUnion{
        .uint16 = 2,
    };
    const givenUnion = DeployedTest.wrap(given);
    const expectedOut = given;
    const expected = [_]u8{ 0x03, 0x02, 0x00, 0x02 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(givenUnion, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], &expected);

    const alloc = std.heap.smp_allocator;
    const deserialized = try zsip.deserialize(DeployedTest, alloc, expected[0..]);
    try std.testing.expectEqual(expectedOut, deserialized);
}
