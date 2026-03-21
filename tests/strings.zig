const std = @import("std");
const zsip = @import("libzsip");

test "default deployment" {
    const expected = &[_]u8{ 0x00, 0x00, 0x00, 0x09, 0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00 };

    var buffer: [1024]u8 = undefined; // your buffer

    const text = "Hello";
    const text_slice: []const u8 = text[0..];
    const DeployedText = zsip.Deployed(@TypeOf(text_slice), zsip.DynamicStringDeployment{});
    const size = try zsip.serialize.serialize(DeployedText.wrap(text_slice), &buffer);

    try std.testing.expectEqualSlices(u8, expected, buffer[0..size]);
}

test "fixed deployment" {
    const expected = &[_]u8{ 0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00 };

    var buffer: [1024]u8 = undefined; // your buffer

    const text = "Hello";
    const text_slice: []const u8 = text[0..];
    const DeployedText = zsip.Deployed(@TypeOf(text_slice), zsip.FixedStringDeployment{ .length = 5 });
    const size = try zsip.serialize.serialize(DeployedText.wrap(text_slice), &buffer);

    try std.testing.expectEqualSlices(u8, expected, buffer[0..size]);
}
