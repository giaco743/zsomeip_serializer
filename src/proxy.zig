const std = @import("std");
const SerializeError = @import("root.zig").SerializeError;
const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const StripDeployment = @import("root.zig").StripDeployment;
const protocol = @import("protocol.zig");

pub const ProxyError = protocol.MethodError || SerializeError || std.net.Stream.WriteError || std.net.Stream.ReadError || std.mem.Allocator.Error;

pub const Proxy = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,

    pub fn init(
        alloc: std.mem.Allocator,
        stream: std.net.Stream,
    ) Proxy {
        return Proxy{
            .allocator = alloc,
            .stream = stream,
        };
    }

    fn callMethod(
        self: *const Proxy,
        comptime Out: type,
        service_id: u16,
        method_id: u16,
        input: anytype,
    ) ProxyError!StripDeployment(Out) {
        std.debug.print("Calling method {}.", .{method_id});
        var buffer = [_]u8{0} ** 1024;
        const payload = buffer[16..];
        const length = try serialize(input, payload);

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
        _ = try serialize(header, buffer[0..16]);

        try self.stream.writeAll(buffer[0 .. length + 16]);

        var response_header_buffer: [16]u8 = [_]u8{0} ** 16;
        const n_header = try self.stream.read(&response_header_buffer);
        if (n_header != 16) {
            return protocol.MethodError.InvalidHeader;
        }

        const response_header = try deserialize(protocol.Header, self.allocator, response_header_buffer[0..]);
        std.debug.print("Received response for {}.", .{response_header.method_id});
        const payload_len = response_header.length - 8;

        if (Out == void)
            return void{};

        var heap_buf: ?[]u8 = null;
        var stack_buf = [_]u8{0} ** 1024;
        const buf = if (payload_len <= stack_buf.len)
            stack_buf[0..payload_len]
        else blk: {
            const tmp = try self.allocator.alloc(u8, payload_len);
            heap_buf = tmp;
            break :blk tmp;
        };
        defer if (heap_buf) |b| self.allocator.free(b);

        const n_payload = try self.stream.read(buf);
        if (n_payload != payload_len) {
            return protocol.MethodError.InvalidInput;
        }

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
    var method_fields: [Methods.len]std.builtin.Type.StructField = undefined;
    for (0..Methods.len) |i| {
        method_fields[i] = std.builtin.Type.StructField{
            .alignment = 8,
            .default_value_ptr = null,
            .is_comptime = false,
            .name = Methods[i].name,
            .type = fn (*Proxy, Methods[i].In) ProxyError!Methods[i].Out,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &method_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
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
