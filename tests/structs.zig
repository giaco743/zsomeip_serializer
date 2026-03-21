const std = @import("std");
const zsip = @import("libzsip");

test "default deployment" {
    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const DeployedTest = zsip.Deployed(Test, struct {}{});
    const given = Test{
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    };
    const givenStruct = DeployedTest.wrap(given);
    const expectedOut = zsip.deserialize.StripDeployment(Test){
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    };
    const expected = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE };

    var buffer: [1024]u8 = undefined; // your buffer

    const size = try zsip.serialize.serialize(givenStruct, buffer[0..]);

    try std.testing.expectEqualSlices(u8, buffer[0..size], &expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(DeployedTest);
    try std.testing.expectEqual(expectedOut, deserialized);
}

test "no deployment" {
    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const givenStruct = Test{
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    };
    const expectedOut = zsip.deserialize.StripDeployment(Test){
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    };
    const expected = &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE };
    var buffer: [1024]u8 = undefined; // your buffer

    const size = try zsip.serialize.serialize(givenStruct, &buffer);

    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(Test);
    try std.testing.expectEqual(expectedOut, deserialized);
}

const InnerStruct = struct {
    x: u16,
};

test "nested struct" {
    const OuterStruct = struct {
        inner: InnerStruct,
        y: u32,
    };

    var buffer: [1024]u8 = undefined; // your buffer

    const outer = OuterStruct{
        .inner = InnerStruct{ .x = 0x1234 },
        .y = 0x56789ABC,
    };
    const expectedOut = zsip.deserialize.StripDeployment(OuterStruct){
        .inner = zsip.deserialize.StripDeployment(InnerStruct){ .x = 0x1234 },
        .y = 0x56789ABC,
    };
    const expected = &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC };
    const size = try zsip.serialize.serialize(outer, &buffer);
    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(OuterStruct);
    try std.testing.expectEqual(expectedOut, deserialized);
}

test "empty struct" {
    const EmptyStruct = struct {};

    var buffer: [1024]u8 = undefined; // your buffer

    const empty = EmptyStruct{};
    const expectedOut = zsip.deserialize.StripDeployment(EmptyStruct){};
    const expected = &[_]u8{};
    const size = try zsip.serialize.serialize(empty, &buffer);
    try std.testing.expectEqualSlices(u8, buffer[0..size], expected);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(EmptyStruct);
    try std.testing.expectEqual(expectedOut, deserialized);
}

test "complex struct" {
    const U16Array = zsip.Deployed([]u16, zsip.ArrayDeployment{});
    const ComplexStruct = struct {
        a: u16,
        b: U16Array,
        inner: InnerStruct,
        s: []const u8,
    };

    var buffer: [1024]u8 = undefined; // your buffer

    var b = [_]u16{ 0x56, 0x78, 0x9A };
    const complex = ComplexStruct{ .a = 0x1234, .b = U16Array{ .value = b[0..] }, .inner = InnerStruct{ .x = 0xBCDE }, .s = "test" };
    const expectedOut = zsip.deserialize.StripDeployment(ComplexStruct){ .a = 0x1234, .b = b[0..], .inner = zsip.deserialize.StripDeployment(InnerStruct){ .x = 0xBCDE }, .s = "test" };
    const expected = &[_]u8{
        0x12, 0x34, // a: u16
        0x00, 0x00, 0x00, 0x06, // b: Vec length
        0x00, 0x56, 0x00, 0x78, 0x00, 0x9A, // b: Vec data
        0xBC, 0xDE, // inner.x: u16
        0x00, 0x00, 0x00, 0x08, // s: String length
        0xEF, 0xBB, 0xBF, // s: BOM
        0x74, 0x65, 0x73, 0x74, 0x00, // s: "test\0"
    };
    const size = try zsip.serialize.serialize(complex, &buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer[0..size]);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var deser = zsip.deserialize.Deserializer.init(gpa.allocator(), expected[0..]);

    const deserialized = try deser.deserialize(ComplexStruct);
    try std.testing.expectEqual(expectedOut.a, deserialized.a);
    try std.testing.expectEqualStrings(expectedOut.s, deserialized.s);
    try std.testing.expectEqual(expectedOut.inner, deserialized.inner);
    try std.testing.expectEqualSlices(u16, expectedOut.b, deserialized.b);

    gpa.allocator().free(deserialized.b);
}
