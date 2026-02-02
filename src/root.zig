const std = @import("std");

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

pub const StringDeploymentVariant = union(enum) {
    fixed_string_depl: FixedStringDeployment,
    dynamic_string_depl: DynamicStringDeployment,
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

pub const Deployment = union(enum) {
    array_depl: ArrayDeployment,
    string_depl: StringDeploymentVariant,
    union_depl: UnionDeployment,
    struct_depl: StructDeployment,
};

pub const FieldDeployment = struct {
    name: []const u8,
    depl: Deployment,
};

pub const StructDeployment = struct {
    field_depls: []const FieldDeployment = &[0]FieldDeployment{},

    pub fn get_field_depl(comptime self: StructDeployment, comptime field_name: []const u8) ?Deployment {
        for (self.field_depls) |depl| {
            if (std.mem.eql(u8, depl.name, field_name)) {
                return depl.depl;
            }
        }
        return null;
    }
};

/// Caller-owned Serializer: the caller is responsible for managing the buffer
/// and passing it to init. This keeps the lifetime straightforward.
pub const Serializer = struct {
    payload: []u8,
    pos: usize = 0, // byte position
    bit_offset: u8 = 0, // bit offset within current byte (0-7)

    pub fn init(buffer: []u8) Serializer {
        return Serializer{
            .payload = buffer,
            .pos = 0,
            .bit_offset = 0,
        };
    }
    pub fn get(self: *const Serializer) []u8 {
        return self.payload[0..self.pos];
    }
    pub fn serializeInt(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        switch (info) {
            .int => {
                if ((info.int.bits % 8) == 0) {
                    const size = @sizeOf(T);
                    if (self.pos + size > self.payload.len)
                        return .OutOfBounds;

                    const ptr: *[size]u8 = @ptrCast(self.payload[self.pos..].ptr);
                    std.mem.writeInt(T, ptr, value, .big);
                    self.pos += size;
                } else {
                    @compileError("Bit sized integers are not yet supported");
                }
            },
            else => @compileError("T must be an integer type"),
        }
    }
    pub fn serializeFloat(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        if (info != .float)
            @compileError("T must be a float type");

        const IntT = std.meta.Int(.unsigned, @bitSizeOf(T));
        const bits: IntT = @bitCast(value);

        const size = @sizeOf(T);
        if (self.pos + size > self.payload.len)
            return error.OutOfBounds;

        const ptr: *[size]u8 = @ptrCast(self.payload[self.pos..].ptr);
        std.mem.writeInt(IntT, ptr, bits, .big);
        self.pos += size;
    }

    pub fn serializeTag(self: *Serializer, comptime widthType: Width, value: usize) !void {
        switch (widthType) {
            .U8 => {
                if (value > 0xFF) return SerializeError.BufferOverflow;
                try self.serializeInt(u8, value);
            },
            .U16 => {
                if (value > 0xFFFF) return SerializeError.BufferOverflow;
                try self.serializeInt(u16, value);
            },
            .U32 => {
                if (value > 0xFFFF_FFFF) return SerializeError.BufferOverflow;
                try self.serializeInt(u32, value);
            },
        }
    }
    pub fn patchTag(self: *Serializer, comptime widthType: Width, pos: usize, size: usize) !void {
        const current_pos = self.pos;
        self.pos = pos;
        try self.serializeTag(widthType, size);
        self.pos = current_pos;
    }
};

const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    WrongDeployment,
    OutOfBounds,
};

pub fn serialize(comptime depl: ?Deployment, value: anytype, serializer: *Serializer) !void {
    try CompoundTypeSerializer.serialize(@TypeOf(value), depl, value, serializer);
}

const CompoundTypeSerializer = struct {
    pub fn serialize(comptime T: type, comptime depl: ?Deployment, value: T, serializer: *Serializer) !void {
        const info = @typeInfo(T);

        switch (info) {
            .@"struct" => {
                const struct_depl = switch (depl orelse Deployment{ .struct_depl = StructDeployment{} }) {
                    .struct_depl => |struct_depl| struct_depl,
                    else => StructDeployment{},
                };
                try CompoundTypeSerializer.serializeStruct(@TypeOf(value), struct_depl, serializer, value);
            },
            .@"union" => {
                const union_depl = switch (depl orelse Deployment{ .union_depl = UnionDeployment{} }) {
                    .union_depl => |union_depl| union_depl,
                    else => unreachable,
                };
                try CompoundTypeSerializer.serializeUnion(@TypeOf(value), union_depl, serializer, value);
            },
            .int => {
                try serializer.serializeInt(T, value);
            },
            .float => {
                try serializer.serializeFloat(T, value);
            },
            .array => |a| {
                try CompoundTypeSerializer.serializeArray(a.child, a.len, value);
            },
            .pointer => |p| {
                if (p.size == .slice) {
                    const array_depl = switch (depl orelse Deployment{ .array_depl = ArrayDeployment{} }) {
                        .array_depl => |array_depl| array_depl,
                        else => {
                            return .WrongDeployment;
                        },
                    };
                    const slice = @as([]const p.child, value);
                    try CompoundTypeSerializer.serializeSlice(serializer, p.child, array_depl, slice);
                } else {
                    return SerializeError.InvalidType;
                }
            },
            else => return SerializeError.InvalidType,
        }
    }

    pub fn serializeSlice(serializer: *Serializer, comptime T: type, comptime depl: ArrayDeployment, value: []const T) !void {
        const length_pos = serializer.pos;
        try serializer.serializeTag(depl.lengthWidth, 0);
        const start = serializer.pos;
        for (value) |element| {
            try CompoundTypeSerializer.serialize(@TypeOf(element), null, element, serializer);
        }
        const end = serializer.pos;
        try serializer.patchTag(depl.lengthWidth, length_pos, end - start);
    }

    pub fn serializeArray(serializer: *Serializer, comptime T: type, comptime Size: usize, value: [Size]T) !void {
        for (value) |element| {
            try CompoundTypeSerializer.serialize(@TypeOf(element), null, element, serializer);
        }
    }

    pub fn serializeStruct(comptime T: type, comptime depl: StructDeployment, serializer: *Serializer, value: T) !void {
        const info = @typeInfo(T);
        const s = switch (info) {
            .@"struct" => |s| s,
            else => unreachable,
        };

        inline for (0..s.fields.len) |i| {
            try CompoundTypeSerializer.serialize(s.fields[i].type, depl.get_field_depl(s.fields[i].name), @field(value, s.fields[i].name), serializer);
        }
    }

    pub fn serializeUnion(comptime T: type, comptime depl: UnionDeployment, serializer: *Serializer, value: T) !void {
        switch (value) {
            inline else => |payload, tag| {
                const length_pos = serializer.pos;
                try serializer.serializeTag(depl.lengthWidth, 0);
                try serializer.serializeTag(depl.typeWidth, @intFromEnum(tag));
                const start = serializer.pos;
                try CompoundTypeSerializer.serialize(@TypeOf(payload), null, payload, serializer);
                const end = serializer.pos;
                serializer.patchTag(depl.lengthWidth, length_pos, end - start);
            },
        }
    }
};
