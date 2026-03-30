const std = @import("std");
const root = @import("root.zig");
const Header = @import("protocol.zig").Header;
pub const serialize = @import("serialize.zig").serialize;
pub const Deserializer = @import("deserialize.zig").Deserializer;
pub const MethodError = @import("protocol.zig").MethodError;
pub const Test = @import("protocol.zig").Test;

const callMethod = @import("protocol.zig").callMethod;

const Greet = struct {
    greeting: []const u8,
};

pub fn handleRequest(
    stream: *std.net.Stream,
) !void {
    var header_buf: [16]u8 = undefined;
    const n_header = try stream.read(&header_buf);
    if (n_header != 16) {
        return MethodError.InvalidHeader;
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var header_deserializer = Deserializer.init(gpa.allocator(), header_buf[0..]);
    const header = try header_deserializer.deserialize(Header);

    const payload_len = header.length - 8;
    var payload_buf: [1024]u8 = undefined;
    const n_payload = try stream.read(payload_buf[0..payload_len]);

    if (n_payload != payload_len) {
        return MethodError.InvalidInput;
    }

    var payload_deserializer = Deserializer.init(gpa.allocator(), payload_buf[0..payload_len]);
    const request = try payload_deserializer.deserialize(Test);

    std.debug.print("Received: a: {d}, b: {d}, c: {d}, text: {s}", .{
        request.a,
        request.b,
        request.c,
        request.text,
    });

    const response = Test{
        .a = 1,
        .b = 2,
        .c = 3,
        .text = "World",
    };

    var send_buf: [1024]u8 = undefined;
    const payload_slice = send_buf[16..];
    const payload_size = try serialize(response, payload_slice);

    const response_header = Header{
        .service_id = header.service_id,
        .method_id = header.method_id,
        .length = @intCast(payload_size + 8),
        .client_id = header.client_id,
        .session_id = header.session_id,
        .protocol_version = header.protocol_version,
        .interface_version = header.interface_version,
        .message_type = .Response,
        .return_code = .EOk,
    };
    _ = try serialize(response_header, send_buf[0..16]);
    std.debug.print("Sending: a: {d}, b: {d}, c: {d}, text: {s}", .{
        response.a,
        response.b,
        response.c,
        response.text,
    });
    try stream.writeAll(send_buf[0 .. 16 + payload_size]);
}

pub fn main() !void {
    const listen_addr = try std.net.Address.initUnix("/tmp/service.sock");
    var server = try listen_addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        try handleRequest(&conn.stream);
    }
}
