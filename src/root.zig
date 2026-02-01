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

pub const StructDeployment = struct {
    field_depls: []const Deployment,
};

/// Caller-owned Serializer: the caller is responsible for managing the buffer
/// and passing it to init. This keeps the lifetime straightforward.
pub const Serializer = struct {
    payload: []u8,
    pos: usize = 0, // byte position
    bit_offset: u8 = 0, // bit offset within current byte (0-7)

    pub fn serializeInt(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        switch (info) {
            .int => |i| {
                const bits: u8 = @intCast(i.bits);
                switch (i.signedness) {
                    .signed => try self.serializeSigned(@intCast(value), bits),
                    .unsigned => try self.serializeUnsigned(@intCast(value), bits),
                }
            },
            else => unreachable,
        }
    }
    pub fn serializeFloat(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        switch (info) {
            .float => |f| {
                const byte_count: usize = f.bits / 8;
                if (self.pos + byte_count > self.payload.len) return SerializeError.BufferOverflow;

                // Bitcast to integer and write as big-endian using manual shifts
                if (f.bits == 32) {
                    const bits_u32: u32 = @bitCast(value);
                    var i: usize = 0;
                    while (i < 4) : (i += 1) {
                        const shift: u5 = @intCast((3 - i) * 8);
                        self.payload[self.pos + i] = @intCast((bits_u32 >> shift) & 0xFF);
                    }
                } else if (f.bits == 64) {
                    const bits_u64: u64 = @bitCast(value);
                    var i: usize = 0;
                    while (i < 8) : (i += 1) {
                        const shift: u6 = @intCast((7 - i) * 8);
                        self.payload[self.pos + i] = @intCast((bits_u64 >> shift) & 0xFF);
                    }
                } else {
                    return SerializeError.InvalidType;
                }

                self.pos += byte_count;
                self.bit_offset = 0;
            },
            else => return SerializeError.InvalidType,
        }
    }

    fn serializeUnsigned(self: *Serializer, value: u64, bits: u8) !void {
        // Write `bits` bits of `value` in big-endian bit order
        var remaining = bits;
        const bit_value = value;

        while (remaining > 0) {
            if (self.pos >= self.payload.len) return SerializeError.BufferOverflow;

            const bits_to_write = @min(remaining, 8 - self.bit_offset);
            const shift: u8 = remaining - bits_to_write;
            // Extract the top bits_to_write bits from bit_value
            const bits_mask: u64 = (@as(u64, 1) << @as(u6, @min(bits_to_write, 63))) - 1;
            const bits_data: u8 = @intCast((bit_value >> @as(u6, @min(shift, 63))) & bits_mask);
            const byte_shift: u3 = @intCast(8 - self.bit_offset - bits_to_write);
            self.payload[self.pos] |= bits_data << byte_shift;

            self.bit_offset += bits_to_write;
            if (self.bit_offset == 8) {
                self.bit_offset = 0;
                self.pos += 1;
            }

            remaining -= bits_to_write;
        }
    }

    fn serializeSigned(self: *Serializer, value: i64, bits: u8) !void {
        // Reinterpret as two's-complement unsigned
        const uv: u64 = @bitCast(value);
        try self.serializeUnsigned(uv, bits);
    }

    pub fn serializeLength(self: *Serializer, comptime widthType: Width, size: usize) !void {
        switch (widthType) {
            .U8 => {
                if (size > 0xFF) return SerializeError.BufferOverflow;
                try self.serializeUnsigned(@as(u64, size), 8);
            },
            .U16 => {
                if (size > 0xFFFF) return SerializeError.BufferOverflow;
                try self.serializeUnsigned(@as(u64, size), 16);
            },
            .U32 => {
                if (size > 0xFFFF_FFFF) return SerializeError.BufferOverflow;
                try self.serializeUnsigned(@as(u64, size), 32);
            },
        }
    }
    fn patchWidth(self: *Serializer, comptime widthType: Width, pos: usize, size: usize) !void {
        const current_pos = self.pos;
        self.pos = pos;
        try self.serializeLength(widthType, size);
        self.pos = current_pos;
    }
};

const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    WrongDeployment,
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
            .@"union" => |u| {
                std.debug.print("Serialize Union: {s}\n", .{@typeName(T)});
                std.debug.print("Name: ", .{u.tag_type});
                const union_depl = switch (depl orelse Deployment{ .union_depl = UnionDeployment{} }) {
                    .union_depl => |union_depl| union_depl,
                    else => unreachable,
                };
                try CompoundTypeSerializer.serializeUnion(@TypeOf(value), union_depl, serializer, value);
            },
            .int => {
                std.debug.print("Serialize Integer: {s}\n", .{@typeName(T)});
                try serializer.serializeInt(T, value);
            },
            .float => {
                std.debug.print("Serialize Float: {s}\n", .{@typeName(T)});
                try serializer.serializeFloat(T, value);
            },
            .array => |a| {
                std.debug.print("Serialize Array: {s}\n", .{@typeName(T)});
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
                    std.debug.print("Serialize Slice: {s}\n", .{@typeName(T)});
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
        try serializer.serializeLength(depl.lengthWidth, 0);
        const start = serializer.pos;
        for (value) |element| {
            try CompoundTypeSerializer.serialize(@TypeOf(element), null, element, serializer);
        }
        const end = serializer.pos;
        try serializer.patchWidth(depl.lengthWidth, length_pos, end - start);
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
            try CompoundTypeSerializer.serialize(s.fields[i].type, depl.field_depls[i], @field(value, s.fields[i].name), serializer);
        }
    }

    pub fn serializeUnion(comptime T: type, comptime depl: UnionDeployment, serializer: *Serializer, value: T) !void {
        switch (value) {
            inline else => |payload, tag| {
                const length_pos = serializer.pos;
                try serializer.serializeLength(depl.lengthWidth, 0);
                try serializer.serializeLength(depl.typeWidth, @intFromEnum(tag));
                const start = serializer.pos;
                try CompoundTypeSerializer.serialize(@TypeOf(payload), null, payload, serializer);
                const end = serializer.pos;
                serializer.patchWidth(depl.lengthWidth, length_pos, end - start);
            },
        }
    }
};
