const std = @import("std");
pub const serialize = @import("serialize.zig").serialize;
pub const Deserializer = @import("deserialize.zig").Deserializer;
pub const StripDeployment = @import("root.zig").StripDeployment;

const MessageType = enum(u8) {
    Request = 0x00,
    RequestNoReturn = 0x01,
    Notification = 0x02,
    Response = 0x80,
    Error = 0x81,
    TpRequest = 0x20,
    TpRequestNoReturn = 0x21,
    TpNotification = 0x22,
    TpResponse = 0xa0,
    TpError = 0xa1,
};

const ReturnCode = enum(u8) {
    EOk = 0x00,
    ENotOk = 0x01,
};

pub const Header = struct {
    service_id: u16,
    method_id: u16,
    length: u32,
    client_id: u16,
    session_id: u16,
    protocol_version: u8,
    interface_version: u8,
    message_type: MessageType,
    return_code: ReturnCode,
};

const Message = struct {
    header: Header,
    payload: []const u8,
};

pub const MethodError = error{
    InvalidHeader,
    InvalidInput,
};

pub fn callMethod(
    comptime T: type,
    allocator: std.mem.Allocator,
    service_id: u16,
    method_id: u16,
    value: anytype,
    stream: *std.net.Stream,
) !StripDeployment(T) {
    var buffer: [1024]u8 = undefined;
    const payload = buffer[16..];
    const length = try serialize(value, payload);

    const header = Header{
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

    try stream.writeAll(buffer[0 .. length + 16]);

    var response_header_buffer: [16]u8 = undefined;
    const n_header = try stream.read(&response_header_buffer);
    if (n_header != 16) {
        return MethodError.InvalidHeader;
    }

    var header_deserializer = Deserializer.init(allocator, &response_header_buffer);
    const response_header = try header_deserializer.deserialize(Header);
    const payload_len = response_header.length - 8;

    var heap_buf: ?[]u8 = null;
    var stack_buf: [1024]u8 = undefined;
    const buf = if (payload_len <= stack_buf.len)
        stack_buf[0..payload_len]
    else blk: {
        const tmp = try allocator.alloc(u8, payload_len);
        heap_buf = tmp;
        break :blk tmp;
    };
    defer if (heap_buf) |b| allocator.free(b);

    const n_payload = try stream.read(buf);
    if (n_payload != payload_len) {
        return MethodError.InvalidInput;
    }

    var payload_deserializer = Deserializer.init(allocator, buf);
    const ret = try payload_deserializer.deserialize(T);
    return ret;
}

pub const Test = struct {
    a: u8,
    b: u16,
    c: u32,
    text: []const u8,
};
