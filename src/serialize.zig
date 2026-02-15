const std = @import("std");
const root = @import("root.zig");

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
                        return root.SerializeError.OutOfBounds;

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
            return .OutOfBounds;

        const ptr: *[size]u8 = @ptrCast(self.payload[self.pos..].ptr);
        std.mem.writeInt(IntT, ptr, bits, .big);
        self.pos += size;
    }

    pub fn serializeTag(self: *Serializer, comptime widthType: root.Width, value: usize) !void {
        switch (widthType) {
            .U8 => {
                const val = std.math.cast(u8, value) orelse return root.SerializeError.OutOfValueBounds;
                try self.serializeInt(u8, val);
            },
            .U16 => {
                const val = std.math.cast(u16, value) orelse return root.SerializeError.OutOfValueBounds;
                try self.serializeInt(u16, val);
            },
            .U32 => {
                const val = std.math.cast(u32, value) orelse return root.SerializeError.OutOfValueBounds;
                try self.serializeInt(u32, val);
            },
        }
    }
    pub fn patchTag(self: *Serializer, comptime widthType: root.Width, pos: usize, size: usize) !void {
        const current_pos = self.pos;
        self.pos = pos;
        try self.serializeTag(widthType, size);
        self.pos = current_pos;
    }
    pub fn serializeDynamicString(self: *Serializer, comptime depl: root.DynamicStringDeployment, value: []const u8) !void {
        try self.serializeTag(depl.lengthWidth, value.len + 4); // + BOM and null
        try self.serializeString(value);
    }
    pub fn serializeString(self: *Serializer, value: []const u8) !void {
        if (self.payload[self.pos..].len < value.len + 4) // + BOM + null
            return root.SerializeError.BufferOverflow;
        const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };
        try self.writeBytes(BOM[0..]);
        try self.writeBytes(value);
        const NULL = [1]u8{0x00};
        try self.writeBytes(NULL[0..]);
    }
    pub fn serializeFixedString(self: *Serializer, comptime length: u64, value: []const u8) !void {
        if (value.len != length)
            return root.SerializeError.OutOfBounds;
        try self.serializeString(value);
    }
    pub fn writeBytes(self: *Serializer, bytes: []const u8) !void {
        if (self.pos + bytes.len > self.payload.len)
            return root.SerializeError.OutOfBounds;
        @memcpy(self.payload[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }
};

pub fn serialize(value: anytype, buffer: []u8) !usize {
    var serializer = Serializer.init(buffer);
    try CompoundTypeSerializer.serialize(@TypeOf(value), value, &serializer);
    return serializer.pos;
}

const CompoundTypeSerializer = struct {
    pub fn serialize(comptime T: type, value: T, serializer: *Serializer) !void {
        const deployed = comptime root.is_deployed(T);

        const ActualType = comptime if (deployed) T.Inner else T;

        const info = @typeInfo(ActualType);

        switch (info) {
            .@"struct" => {
                if (deployed) {
                    try CompoundTypeSerializer.serializeStruct(ActualType, T.Depl, serializer, value.value);
                } else {
                    try CompoundTypeSerializer.serializeStruct(ActualType, struct {}{}, serializer, value);
                }
            },
            .@"union" => {
                if (deployed) {
                    try CompoundTypeSerializer.serializeUnion(ActualType, T.Depl, serializer, value.value);
                } else {
                    try CompoundTypeSerializer.serializeUnion(ActualType, .{}, serializer, value);
                }
            },
            .int => {
                try serializer.serializeInt(ActualType, value);
            },
            .float => {
                try serializer.serializeFloat(ActualType, value);
            },
            .array => |a| {
                try CompoundTypeSerializer.serializeArray(a.child, a.len, value);
            },
            .pointer => |p| {
                if (p.size == .slice) {
                    if (p.child == u8) {
                        if (deployed) {
                            if (@TypeOf(T.Depl) == root.DynamicStringDeployment) {
                                try serializer.serializeDynamicString(T.Depl, value.value);
                            } else if (@TypeOf(T.Depl) == root.FixedStringDeployment) {
                                try serializer.serializeFixedString(T.Depl.length, value.value);
                            } else if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                try CompoundTypeSerializer.serializeSlice(serializer, p.child, T.Depl, value.value);
                            } else {
                                @compileError("Wrong deployment");
                            }
                        } else {
                            try serializer.serializeDynamicString(root.DynamicStringDeployment{}, value.value);
                        }
                        return;
                    }
                    if (deployed) {
                        try CompoundTypeSerializer.serializeSlice(serializer, p.child, T.Depl, value.value);
                    } else {
                        try CompoundTypeSerializer.serializeSlice(serializer, p.child, .{}, value);
                    }
                } else {
                    comptime {
                        var buf: [64]u8 = undefined;
                        const msg = try std.fmt.bufPrint(&buf, "Only pointers to slices are valid, got: {d}!", .{p.size});
                        @compileError(msg);
                    }
                }
            },
            else => @compileError("Unsupported type"),
        }
    }

    pub fn serializeSlice(serializer: *Serializer, comptime T: type, comptime depl: root.ArrayDeployment, value: []const T) !void {
        const length_pos = serializer.pos;
        try serializer.serializeTag(depl.lengthWidth, 0);
        const start = serializer.pos;
        for (value) |element| {
            try CompoundTypeSerializer.serialize(@TypeOf(element), element, serializer);
        }
        const end = serializer.pos;
        try serializer.patchTag(depl.lengthWidth, length_pos, end - start);
    }

    pub fn serializeArray(serializer: *Serializer, comptime T: type, comptime Size: usize, value: [Size]T) !void {
        for (value) |element| {
            try CompoundTypeSerializer.serialize(@TypeOf(element), element, serializer);
        }
    }

    pub fn serializeStruct(comptime T: type, comptime Depl: anytype, serializer: *Serializer, value: T) !void {
        const s = switch (@typeInfo(T)) {
            .@"struct" => |s| s,
            else => unreachable,
        };

        inline for (s.fields) |field| {
            const field_value = @field(value, field.name);

            if (@hasField(@TypeOf(Depl), field.name)) {
                const DeployedField = root.Deployed(@TypeOf(field_value), @field(Depl, field.name));
                try CompoundTypeSerializer.serialize(
                    DeployedField,
                    DeployedField.wrap(field_value),
                    serializer,
                );
            } else {
                try CompoundTypeSerializer.serialize(
                    @TypeOf(field_value),
                    field_value,
                    serializer,
                );
            }
        }
    }

    pub fn serializeUnion(comptime T: type, comptime depl: root.UnionDeployment, serializer: *Serializer, value: T) !void {
        switch (value) {
            inline else => |payload, tag| {
                const length_pos = serializer.pos;
                try serializer.serializeTag(depl.lengthWidth, 0);
                try serializer.serializeTag(depl.typeWidth, @intFromEnum(tag));
                const start = serializer.pos;
                try CompoundTypeSerializer.serialize(@TypeOf(payload), payload, serializer);
                const end = serializer.pos;
                serializer.patchTag(depl.lengthWidth, length_pos, end - start);
            },
        }
    }
};
