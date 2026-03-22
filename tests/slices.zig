const std = @import("std");
const zsip = @import("libzsip");

test "u16 array" {
    const array = [_]u16{ 1, 2, 3, 4 };
    const input = zsip.Deployed([]const u16, zsip.ArrayDeployment{}).wrap(array[0..]);
    const expected = &[_]u8{ 0x00, 0x00, 0x00, 0x08, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(@TypeOf(input));
    try std.testing.expectEqualSlices(u16, array[0..], deserialized[0..]);
    gpa.allocator().free(deserialized);
}

test "u8 array" {
    const array = [_]u8{ 1, 2, 3, 4 };
    const input = zsip.Deployed([]const u8, zsip.ArrayDeployment{}).wrap(array[0..]);
    const expected = &[_]u8{ 0x00, 0x00, 0x00, 0x04, 0x01, 0x02, 0x03, 0x04 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(@TypeOf(input));
    try std.testing.expectEqualSlices(u8, array[0..], deserialized[0..]);
    gpa.allocator().free(deserialized);
}

test "u8 string" {
    const array = [_]u8{ 'a', 'b', 'c', 'd' };
    const input = array[0..];
    const expected = &[_]u8{ 0x00, 0x00, 0x00, 0x08, 0xEF, 0xBB, 0xBF, 'a', 'b', 'c', 'd', 0 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize([]const u8);
    try std.testing.expectEqualStrings(input, deserialized);
}
