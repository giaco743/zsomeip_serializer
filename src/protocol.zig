const std = @import("std");

pub const MethodError = error{
    InvalidHeader,
    InvalidInput,
};

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

pub const MethodDef = struct {
    In: type,
    Out: type,
    method_id: u16,
};

pub const Test = struct {
    a: u8,
    b: u16,
    c: u32,
    text: []const u8,
};
