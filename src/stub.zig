const std = @import("std");
const protocol = @import("protocol.zig");
const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const StripDeployment = @import("deserialize.zig").StripDeployment;
const SerializeError = @import("root.zig").SerializeError;

pub const StubError = protocol.MethodError || SerializeError || std.Io.Writer.Error || std.Io.Reader.Error || std.mem.Allocator.Error || std.Io.Cancelable;

pub fn handleRequests(
    comptime Methods: []const protocol.MethodDef,
    handlers: generateHandlers(Methods),
) fn (std.Io, *std.Io.net.Stream, std.mem.Allocator) StubError!void {
    const fields = @typeInfo(generateHandlers(Methods)).@"struct".fields;
    comptime {
        if (fields.len != Methods.len) {
            @compileError("Handlers length does not match method definitions length.");
        }
    }
    return struct {
        fn wrapper(io: std.Io, stream: *std.Io.net.Stream, alloc: std.mem.Allocator) !void {
            std.debug.print("Received request\n", .{});
            var r_buffer: [1028]u8 = undefined;
            var w_buffer: [1028]u8 = undefined;
            var stream_reader = stream.reader(io, r_buffer[0..]);
            var stream_writer = stream.writer(io, w_buffer[0..]);
            var reader = &stream_reader.interface;
            var writer = &stream_writer.interface;

            while (true) {
                var header_bytes: [16]u8 = undefined;
                std.debug.print("Reading header\n", .{});
                reader.readSliceAll(header_bytes[0..]) catch {
                    std.debug.print("Connection closed.\n", .{});
                    return;
                };

                std.debug.print("Deserializing header\n", .{});
                const header = try deserialize(protocol.Header, alloc, header_bytes[0..]);
                std.debug.print("Received request {}.\n", .{header.method_id});

                if (header.length < 8)
                    return StubError.InvalidHeader;

                const payload_len = header.length - 8;
                var payload = try alloc.alloc(u8, payload_len);
                defer alloc.free(payload[0..]);

                try reader.readSliceAll(payload[0..]);

                inline for (0..Methods.len) |index| {
                    if (header.method_id == Methods[index].method_id) {
                        const response_bytes = try bindHandler(Methods[index].In, Methods[index].Out, @field(handlers, fields[index].name))(alloc, payload[0..]);
                        try writer.writeAll(response_bytes);
                        try writer.flush();
                    }
                }
            }
        }
    }.wrapper;
}

fn bindHandler(
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

fn generateHandlers(
    comptime Methods: []const protocol.MethodDef,
) type {
    var field_names: [10][]const u8 = undefined;
    var field_types: [10]type = undefined;
    for (0..Methods.len) |i| {
        field_names[i] = Methods[i].name;
        field_types[i] = fn (Methods[i].In) Methods[i].Out;
    }

    return @Struct(.auto, null, field_names[0..Methods.len], field_types[0..Methods.len], &@splat(.{}));
}
