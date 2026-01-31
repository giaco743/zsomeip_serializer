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

    pub fn serialize_int(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        switch (info) {
            .int => |i| {
                const bits: u8 = @intCast(i.bits);
                switch (i.signedness) {
                    .signed => try self.serialize_signed(@intCast(value), bits),
                    .unsigned => try self.serialize_unsigned(@intCast(value), bits),
                }
            },
            else => unreachable,
        }
    }
    pub fn serialize_float(self: *Serializer, comptime T: type, value: T) !void {
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

    fn serialize_unsigned(self: *Serializer, value: u64, bits: u8) !void {
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

    fn serialize_signed(self: *Serializer, value: i64, bits: u8) !void {
        // Reinterpret as two's-complement unsigned
        const uv: u64 = @bitCast(value);
        try self.serialize_unsigned(uv, bits);
    }

    pub fn serialize_slice(self: *Serializer, comptime T: type, comptime depl: ArrayDeployment, value: []const T) !void {
        const length: usize = value.len;
        // write length according to requested width with bounds checking
        switch (depl.lengthWidth) {
            .U8 => {
                if (length > 0xFF) return SerializeError.BufferOverflow;
                try self.serialize_unsigned(@as(u64, length), 8);
            },
            .U16 => {
                if (length > 0xFFFF) return SerializeError.BufferOverflow;
                try self.serialize_unsigned(@as(u64, length), 16);
            },
            .U32 => {
                if (length > 0xFFFF_FFFF) return SerializeError.BufferOverflow;
                try self.serialize_unsigned(@as(u64, length), 32);
            },
        }

        for (value) |element| {
            try serialize(null, element, self);
        }
    }
    pub fn serialize_array(self: *Serializer, comptime T: type, comptime Size: usize, value: [Size]T) !void {
        for (value) |element| {
            try serialize(null, element, self);
        }
    }
};

const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    WrongDeployment,
};

pub fn serialize(comptime depl: ?Deployment, value: anytype, serializer: *Serializer) !void {
    try serializeImpl(@TypeOf(value), depl, value, serializer);
}

pub fn serializeImpl(comptime T: type, comptime depl: ?Deployment, value: T, serializer: *Serializer) !void {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            std.debug.print("Serialize Struct: {s}\n", .{@typeName(T)});
            const field_depls = switch (depl orelse Deployment{ .struct_depl = StructDeployment{ .field_depls = &[0]Deployment{} } }) {
                .struct_depl => |struct_depl| struct_depl.field_depls,
                else => unreachable,
            };
            inline for (0..s.fields.len) |i| {
                try serializeImpl(s.fields[i].type, field_depls[i], @field(value, s.fields[i].name), serializer);
            }
        },
        .@"union" => |u| {
            std.debug.print("Serialize Union: {s}\n", .{@typeName(T)});
            std.debug.print("Name: ", .{u.tag_type});
        },
        .int => {
            std.debug.print("Serialize Integer: {s}\n", .{@typeName(T)});
            try serializer.serialize_int(T, value);
        },
        .float => {
            std.debug.print("Serialize Float: {s}\n", .{@typeName(T)});
            try serializer.serialize_float(T, value);
        },
        .array => |a| {
            std.debug.print("Serialize Array: {s}\n", .{@typeName(T)});
            try serializer.serialize_array(a.child, a.len, value);
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
                try serializer.serialize_slice(p.child, array_depl, slice);
            } else {
                return SerializeError.InvalidType;
            }
        },
        else => return SerializeError.InvalidType,
    }
}
