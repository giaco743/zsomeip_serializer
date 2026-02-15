const std = @import("std");
const zsip = @import("zsomeip_serializer");

test "default deployment" {
    const expected = &[_]u8{ 0x00, 0x00, 0x00, 0x09, 0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00 };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const text = "Hello";
    const text_slice: []const u8 = text[0..];
    const DeployedText = zsip.Deployed(@TypeOf(text_slice), zsip.DynamicStringDeployment{});
    const size = try zsip.serialize(DeployedText.wrap(text_slice), slice[0..]);

    try std.testing.expectEqualSlices(u8, expected, slice[0..size]);
}

test "fixed deployment" {
    const expected = &[_]u8{ 0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00 };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const text = "Hello";
    const text_slice: []const u8 = text[0..];
    const DeployedText = zsip.Deployed(@TypeOf(text_slice), zsip.FixedStringDeployment{ .length = 5 });
    const size = try zsip.serialize(DeployedText.wrap(text_slice), slice[0..]);

    try std.testing.expectEqualSlices(u8, expected, slice[0..size]);
}
