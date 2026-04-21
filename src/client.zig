const std = @import("std");
const root = @import("root.zig");

const protocol = @import("protocol.zig");
const proxy = @import("proxy.zig");
const service = @import("service.zig");

const Greet = struct {
    greeting: []const u8,
};
const myProxy = proxy.makeProxyMethods(service.method_def[0..]);

pub fn main() !void {
    const path = "/tmp/service.sock";
    const service_addr = try std.Io.net.UnixAddress.init(path);
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const stream = try service_addr.connect(io);

    const request = protocol.Test{
        .a = 69,
        .b = 420,
        .c = 1990,
        .text = "Hello",
    };

    var alloc = std.heap.smp_allocator;
    var prxy = proxy.Proxy.init(io, alloc, stream);
    const response = try myProxy.testF(&prxy, request);
    defer alloc.free(response.text);
    std.debug.print("Received response: a: {d}, b: {d}, c: {d}, text: {s},\n", .{
        response.a,
        response.b,
        response.c,
        response.text,
    });

    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
    try myProxy.voidF(&prxy, void{});
    std.debug.print("Called void function", .{});
    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);

    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
    const received = try myProxy.intF(&prxy, 4321);
    std.debug.print("Called int function, received {}.", .{received});
    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);

    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
    const greetResponse = try myProxy.greet(&prxy, "Hey stub, good morning!");
    defer alloc.free(greetResponse);
    std.debug.print("Called greet function, received {s}.", .{greetResponse});
    try std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real);
}
