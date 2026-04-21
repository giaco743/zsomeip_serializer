const std = @import("std");
const SerializeError = @import("root.zig").SerializeError;
const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const StripDeployment = @import("root.zig").StripDeployment;
const protocol = @import("protocol.zig");

pub const ProxyError = protocol.MethodError || SerializeError || std.Io.Writer.Error || std.Io.Reader.Error || std.mem.Allocator.Error || std.Io.Cancelable;

pub const Proxy = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,

    pub fn init(
        io: std.Io,
        alloc: std.mem.Allocator,
        stream: std.Io.net.Stream,
    ) Proxy {
        return Proxy{
            .io = io,
            .allocator = alloc,
            .stream = stream,
        };
    }

    fn callMethod(
        self: *Proxy,
        comptime Out: type,
        service_id: u16,
        method_id: u16,
        input: anytype,
    ) ProxyError!StripDeployment(Out) {
        std.debug.print("Calling method {}.\n", .{method_id});
        var input_bytes = [_]u8{0} ** 1024;
        const payload = input_bytes[16..];
        const length = try serialize(input, payload);
        std.debug.print("Searialized input with length {}.\n", .{length});

        const header = protocol.Header{
            .service_id = service_id,
            .method_id = method_id,
            .length = @intCast(length + 8),
            .client_id = 0,
            .session_id = 0,
            .protocol_version = 0,
            .interface_version = 0,
            .message_type = .Request,
            .return_code = .EOk,
        };
        const header_length = try serialize(header, input_bytes[0..16]);
        std.debug.print("Searialized header with length {}.\n", .{header_length});

        std.debug.print("Searialized input.\n", .{});
        var w_buffer: [1024]u8 = undefined;

        var stream_writer = self.stream.writer(self.io, &w_buffer);
        var writer = &stream_writer.interface;
        try writer.writeAll(input_bytes[0 .. length + 16]);
        try writer.flush();
        std.debug.print("Sent input: {any}.\n", .{input_bytes[0 .. length + 16]});

        var r_buffer: [1024]u8 = undefined;
        var response_header_bytes: [16]u8 = undefined;
        var stream_reader = self.stream.reader(self.io, &r_buffer);
        var reader = &stream_reader.interface;

        std.debug.print("Before reading.\n", .{});
        try reader.readSliceAll(response_header_bytes[0..]);
        std.debug.print("After reading.\n", .{});

        const response_header = try deserialize(protocol.Header, self.allocator, response_header_bytes[0..]);
        const payload_len = response_header.length - 8;
        std.debug.print("Received response for {} with payload length {}.", .{ response_header.method_id, payload_len });

        if (Out == void) {
            if (payload_len != 0)
                return ProxyError.InvalidInput;
            return void{};
        }

        var heap_buf: ?[]u8 = null;
        var stack_buf: [1024]u8 = undefined;
        const buf = if (payload_len <= stack_buf.len)
            stack_buf[0..payload_len]
        else blk: {
            const tmp = try self.allocator.alloc(u8, payload_len);
            heap_buf = tmp;
            break :blk tmp;
        };
        defer if (heap_buf) |b| self.allocator.free(b);

        try reader.readSliceAll(buf);

        return try deserialize(Out, self.allocator, buf);
    }
};

fn bindMethod(comptime In: type, comptime Out: type, comptime service_id: u16, comptime method_id: u16) fn (proxy: *Proxy, input: In) ProxyError!StripDeployment(Out) {
    // returns a function that calls callMethod with baked IDs
    return struct {
        fn wrapper(proxy: *Proxy, input: In) ProxyError!StripDeployment(Out) {
            return try proxy.callMethod(Out, service_id, method_id, input);
        }
    }.wrapper;
}

fn generateProxyMethodsType(
    comptime Methods: []const protocol.MethodDef,
) type {
    var field_names: [10][]const u8 = undefined;
    var field_types: [10]type = undefined;
    for (0..Methods.len) |i| {
        field_names[i] = Methods[i].name;
        field_types[i] = fn (*Proxy, Methods[i].In) ProxyError!Methods[i].Out;
    }

    return @Struct(
        .auto,
        null,
        field_names[0..Methods.len],
        field_types[0..Methods.len],
        &@splat(.{}),
    );
}

pub fn makeProxyMethods(
    comptime Methods: []const protocol.MethodDef,
) generateProxyMethodsType(Methods) {
    const T = generateProxyMethodsType(Methods);
    var val: T = undefined;
    inline for (Methods) |M| {
        @field(val, M.name) = bindMethod(M.In, M.Out, 1234, M.method_id);
    }
    return val;
}
