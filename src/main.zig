const std = @import("std");
const zsomeip_serializer = @import("zsomeip_serializer");

const Message = struct {
    a: u3,
    b: u3,
};

const EightMessages = struct {
    one: Message,
    two: Message,
    three: Message,
    four: Message,
    five: Message,
    six: Message,
    seven: Message,
    eight: Message,
};

pub fn main() !void {
    // const one = Message{
    //     .a = 0,
    //     .b = 0,
    // };
    // const two = Message{
    //     .a = 7,
    //     .b = 7,
    // };

    // const both = EightMessages{
    //     .one = one,
    //     .two = one,
    //     .three = one,
    //     .four = one,
    //     .five = two,
    //     .six = two,
    //     .seven = two,
    //     .eight = two,
    // };

    // var buffer: [6]u8 = undefined;
    // @memset(&buffer, 0); // Initialize buffer to 0
    // var serializer = zsomeip_serializer.Serializer{ .payload = &buffer };
    // try zsomeip_serializer.serialize(both, &serializer);
    // std.debug.print("First byte: {b:0>8}\n", .{buffer[0]});
    // std.debug.print("Second byte: {b:0>8}\n", .{buffer[1]});
    // std.debug.print("Third byte: {b:0>8}\n", .{buffer[2]});
    // std.debug.print("Fourth byte: {b:0>8}\n", .{buffer[3]});
    // std.debug.print("Fifth byte: {b:0>8}\n", .{buffer[4]});
    // std.debug.print("Sixth byte: {b:0>8}\n", .{buffer[5]});

    // std.debug.print("Serializing array\n", .{});
    // var a_buffer: [9]u8 = undefined;
    // @memset(&a_buffer, 0); // Initialize buffer to 0
    // var a_serializer = zsomeip_serializer.Serializer{ .payload = &a_buffer };
    // const array = [_]u8{ 1, 2, 3, 4, 5 };
    // try zsomeip_serializer.serialize(array, &a_serializer);
    // std.debug.print("First byte: {b:0>8}\n", .{a_buffer[0]});
    // std.debug.print("Second byte: {b:0>8}\n", .{a_buffer[1]});
    // std.debug.print("Third byte: {b:0>8}\n", .{a_buffer[2]});
    // std.debug.print("Fourth byte: {b:0>8}\n", .{a_buffer[3]});
    // std.debug.print("Fifth byte: {b:0>8}\n", .{a_buffer[4]});
    // std.debug.print("Sixth byte: {b:0>8}\n", .{a_buffer[5]});
    // std.debug.print("Seventh byte: {b:0>8}\n", .{a_buffer[6]});
    // std.debug.print("Eight byte: {b:0>8}\n", .{a_buffer[7]});
    // std.debug.print("Nineth byte: {b:0>8}\n", .{a_buffer[8]});

    const ArrayMessage = struct {
        array_a: []u16,
        array_b: []u16,
    };

    std.debug.print("Serializing width array\n", .{});
    var bw_buffer: [22]u8 = undefined;
    @memset(&bw_buffer, 0); // Initialize buffer to 0
    var bw_array = [_]u16{ 1, 2, 3, 4 };
    var bw_serializer = zsomeip_serializer.Serializer{ .payload = &bw_buffer };
    try zsomeip_serializer.serialize(zsomeip_serializer.Deployment{ .struct_depl = zsomeip_serializer.StructDeployment{ .field_depls = &[_]zsomeip_serializer.FieldDeployment{zsomeip_serializer.FieldDeployment{ .name = "array_a", .depl = zsomeip_serializer.Deployment{ .array_depl = zsomeip_serializer.ArrayDeployment{ .lengthWidth = .U16 } } }} } }, ArrayMessage{ .array_a = bw_array[0..], .array_b = bw_array[0..] }, &bw_serializer);
    std.debug.print("First byte: {b:0>8}\n", .{bw_buffer[0]});
    std.debug.print("Second byte: {b:0>8}\n", .{bw_buffer[1]});
    std.debug.print("Third byte: {b:0>8}\n", .{bw_buffer[2]});
    std.debug.print("Fourth byte: {b:0>8}\n", .{bw_buffer[3]});
    std.debug.print("Fifth byte: {b:0>8}\n", .{bw_buffer[4]});
    std.debug.print("Sixth byte: {b:0>8}\n", .{bw_buffer[5]});
    std.debug.print("Seventh byte: {b:0>8}\n", .{bw_buffer[6]});
    std.debug.print("Eight byte: {b:0>8}\n", .{bw_buffer[7]});
    std.debug.print("Nineth byte: {b:0>8}\n", .{bw_buffer[8]});
    std.debug.print("Tenth byte: {b:0>8}\n", .{bw_buffer[9]});
    std.debug.print("Elevneth byte: {b:0>8}\n", .{bw_buffer[10]});
    std.debug.print("Twelveth byte: {b:0>8}\n", .{bw_buffer[11]});
    std.debug.print("Thirteenth byte: {b:0>8}\n", .{bw_buffer[12]});
    std.debug.print("Fourteenth byte: {b:0>8}\n", .{bw_buffer[13]});
    std.debug.print("Fifteenth byte: {b:0>8}\n", .{bw_buffer[14]});
    std.debug.print("Sixteenth byte: {b:0>8}\n", .{bw_buffer[15]});
    std.debug.print("Seventeenth byte: {b:0>8}\n", .{bw_buffer[16]});
    std.debug.print("Eighteenth byte: {b:0>8}\n", .{bw_buffer[17]});
    std.debug.print("Nineteenth byte: {b:0>8}\n", .{bw_buffer[18]});
    std.debug.print("Twenteeth byte: {b:0>8}\n", .{bw_buffer[19]});
    std.debug.print("Twentyfirst byte: {b:0>8}\n", .{bw_buffer[20]});
    std.debug.print("Twentysecond byte: {b:0>8}\n", .{bw_buffer[21]});
}
