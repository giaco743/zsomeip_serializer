const std = @import("std");
const zsip = @import("zsomeip_serializer");

test "default deployment" {
    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const DeployedTest = zsip.Deployed(Test, struct {}{});
    const givenStruct = DeployedTest{ .value = Test{
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    } };
    const expected = &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const size = try zsip.serialize(givenStruct, slice[0..]);

    try std.testing.expectEqualSlices(u8, slice[0..size], expected);
}
