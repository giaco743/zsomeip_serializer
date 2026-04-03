const std = @import("std");
const root = @import("root.zig");

const protocol = @import("protocol.zig");
const proxy = @import("proxy.zig");

const Greet = struct {
    greeting: []const u8,
};

const testFunction = proxy.bindMethod(protocol.Test, protocol.Test, 1234, 5678);
const voidFunction = proxy.bindMethod(void, void, 1234, 6666);

pub fn main() !void {
    const stream = try std.net.connectUnixSocket("/tmp/service.sock");

    const request = protocol.Test{
        .a = 69,
        .b = 420,
        .c = 1990,
        .text = "Hello",
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var prxy = proxy.Proxy.init(allocator, stream);
    const response = try testFunction(&prxy, request);
    defer allocator.free(response.text);
    std.debug.print("Received response: a: {d}, b: {d}, c: {d}, text: {s},\n", .{
        response.a,
        response.b,
        response.c,
        response.text,
    });
    std.Thread.sleep(1000000000);
    try voidFunction(&prxy, void{});
    std.debug.print("Called void function", .{});
    std.Thread.sleep(1000000000);
}
