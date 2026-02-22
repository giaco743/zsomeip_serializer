const std = @import("std");
pub const serialize = @import("serialize.zig");
pub const deserialize = @import("deserialize.zig");

pub const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    OutOfBounds,
    OutOfValueBounds,
    BomMissing,
    NullMissing,
    InvalidLength,
};

pub const Width = enum {
    U8,
    U16,
    U32,
};

pub const ArrayDeployment = struct {
    lengthWidth: Width = .U32,
    min: ?u64 = null,
    max: ?u64 = null,
};
pub const FixedStringDeployment = struct {
    length: u64,
};

pub const DynamicStringDeployment = struct {
    lengthWidth: Width = .U32,
    min: ?u64 = null,
    max: ?u64 = null,
};

pub const UnionDeployment = struct {
    lengthWidth: Width = .U32,
    typeWidth: Width = .U32,
};

pub fn is_deployed(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "Inner") and @hasDecl(T, "Depl"),
        else => false,
    };
}

pub fn Deployed(comptime T: type, comptime depl: anytype) type {
    const Base = if (is_deployed(T)) T.Inner else T;

    return struct {
        value: Base,
        pub const Inner = Base;
        pub const Depl = depl;
        pub const Self = @This();

        pub fn wrap(val: T) Self {
            return .{ .value = if (comptime is_deployed(T)) val.value else val };
        }
    };
}
