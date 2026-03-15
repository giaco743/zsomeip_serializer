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
    const expected = [_]u8{ 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02 };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const size = try zsip.serialize.serialize(givenUnion, slice[0..]);

    try std.testing.expectEqualSlices(u8, slice[0..size], &expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);
    defer deser.deinit();

    const deserialized = try deser.deserialize(DeployedTest);
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
    const expected = [_]u8{ 0x02, 0x02, 0x00, 0x02 };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const size = try zsip.serialize.serialize(givenUnion, slice[0..]);

    try std.testing.expectEqualSlices(u8, slice[0..size], &expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);
    defer deser.deinit();

    const deserialized = try deser.deserialize(DeployedTest);
    try std.testing.expectEqual(expectedOut, deserialized);
}
