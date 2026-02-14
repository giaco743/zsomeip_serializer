const std = @import("std");
const zsip = @import("zsomeip_serializer");

test "default deployment" {
    const expected = &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const text = "Hello";
    const DeployedText = zsip.Deployed(@TypeOf(text[0..]), zsip.DynamicStringDeployment{});
    const size = try zsip.serialize(DeployedText.init(text[0..]), slice[0..]);

    try std.testing.expectEqualSlices(u8, slice[0..size], expected);
}
