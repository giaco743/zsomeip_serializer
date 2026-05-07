const std = @import("std");
const zsip = @import("libzsip");

test "u16 array" {
    const input = [_]u16{ 1, 2, 3, 4 };
    const expected = &[_]u8{ 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected[0..]);

    const alloc = std.heap.smp_allocator;
    const deserialized = try zsip.deserialize(@TypeOf(input), alloc, expected[0..]);
    try std.testing.expectEqualSlices(u16, input[0..], deserialized[0..]);
}

test "u8 array" {
    const input = [_]u8{ 1, 2, 3, 4 };
    const expected = &[_]u8{ 0x01, 0x02, 0x03, 0x04 };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected[0..]);

    const alloc = std.heap.smp_allocator;
    const deserialized = try zsip.deserialize(@TypeOf(input), alloc, expected[0..]);
    try std.testing.expectEqualSlices(u8, input[0..], deserialized[0..]);
}

test "u8 string" {
    const input = [_]u8{ 'a', 'b', 'c', 'd' };
    const expected = &[_]u8{ 'a', 'b', 'c', 'd' };

    var buffer: [1024]u8 = undefined; // your buffer
    const size = try zsip.serialize(input, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected[0..]);

    const alloc = std.heap.smp_allocator;
    const deserialized = try zsip.deserialize([4]u8, alloc, expected[0..]);
    try std.testing.expectEqualStrings(input[0..], deserialized[0..]);
}
