const std = @import("std");
const protocol = @import("protocol.zig");
const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const StripDeployment = @import("deserialize.zig").StripDeployment;
const SerializeError = @import("root.zig").SerializeError;

pub const StubError = protocol.MethodError || SerializeError || std.net.Stream.WriteError || std.net.Stream.ReadError || std.mem.Allocator.Error;

pub fn handleRequests(
    comptime Methods: []const protocol.MethodDef,
    comptime Handlers: type,
    handlers: Handlers,
) fn (*std.net.Stream, std.mem.Allocator) StubError!void {
    const fields = @typeInfo(Handlers).@"struct".fields;
    comptime {
        if (fields.len != Methods.len) {
            @compileError("Handlers length does not match method definitions length.");
        }
    }
    return struct {
        fn wrapper(stream: *std.net.Stream, alloc: std.mem.Allocator) !void {
            while (true) {
                var header_buffer = [_]u8{0} ** 16;
                const n_header = try stream.read(header_buffer[0..]);
                std.debug.print("Read {}  bytes", .{n_header});
                if (n_header == 0) {
                    std.debug.print("Connection closed", .{});
                    return;
                }
                if (n_header != 16)
                    return protocol.MethodError.InvalidHeader;
                const header = try deserialize(protocol.Header, alloc, header_buffer[0..]);
                std.debug.print("Received request {}.", .{header.method_id});

                var buffer = try alloc.alloc(u8, header.length - 8);
                defer alloc.free(buffer[0..]);
                const n_buffer = try stream.read(buffer[0..]);

                if (n_buffer != buffer.len)
                    return protocol.MethodError.InvalidInput;

                inline for (0..Methods.len) |index| {
                    if (header.method_id == Methods[index].method_id) {
                        const response_bytes = try bindHandler(Methods[index].In, Methods[index].Out, @field(handlers, fields[index].name))(alloc, buffer[0..]);
                        try stream.writeAll(response_bytes);
                    }
                }
            }
        }
    }.wrapper;
}

pub fn bindHandler(
    comptime In: type,
    comptime Out: type,
    comptime handler: fn (StripDeployment(In)) Out,
) fn (alloc: std.mem.Allocator, payload: []const u8) (std.mem.Allocator.Error || SerializeError)![]u8 {
    return struct {
        fn wrapper(alloc: std.mem.Allocator, payload: []const u8) (std.mem.Allocator.Error || SerializeError)![]u8 {
            const input = try deserialize(In, alloc, payload);
            const output = handler(input);

            const buf = try alloc.alloc(u8, 1028);
            const n = try serialize(output, buf[16..]);
            const header = protocol.Header{
                .service_id = 1234,
                .method_id = 5678,
                .length = @intCast(n + 8),
                .client_id = 0,
                .session_id = 0,
                .protocol_version = 0,
                .interface_version = 0,
                .message_type = .Response,
                .return_code = .EOk,
            };
            _ = try serialize(header, buf[0..16]);
            return buf[0 .. n + 16];
        }
    }.wrapper;
}
