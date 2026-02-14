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

pub const NoopDeployment = struct {};

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
                        return SerializeError.OutOfBounds;

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

    pub fn serializeTag(self: *Serializer, comptime widthType: Width, value: usize) !void {
        switch (widthType) {
            .U8 => {
                const val = std.math.cast(u8, value) orelse return SerializeError.OutOfValueBounds;
                try self.serializeInt(u8, val);
            },
            .U16 => {
                const val = std.math.cast(u16, value) orelse return SerializeError.OutOfValueBounds;
                try self.serializeInt(u16, val);
            },
            .U32 => {
                const val = std.math.cast(u32, value) orelse return SerializeError.OutOfValueBounds;
                try self.serializeInt(u32, val);
            },
        }
    }
    pub fn patchTag(self: *Serializer, comptime widthType: Width, pos: usize, size: usize) !void {
        const current_pos = self.pos;
        self.pos = pos;
        try self.serializeTag(widthType, size);
        self.pos = current_pos;
    }
    pub fn serializeDynamicString(self: *Serializer, comptime depl: DynamicStringDeployment, value: []const u8) !void {
        try self.serializeTag(depl.lengthWidth, value.len + 4); // + BOM and null
        try self.serializeString(value);
    }
    pub fn serializeString(self: *Serializer, value: []const u8) !void {
        if (self.payload[self.pos..].len < value.len + 4) // + BOM + null
            return .BufferOverflow;
        const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };
        self.writeBytes(BOM[0..]);
        self.writeBytes(value);
        const NULL = [1]u8{0x00};
        self.writeBytes(NULL[0..]);
    }
    pub fn serializeFixedString(self: *Serializer, comptime length: u64, value: []const u8) !void {
        if (value.len != length)
            return .OutOfBounds;
        try self.serializeString(value);
    }
    pub fn writeBytes(self: *Serializer, bytes: []const u8) !void {
        if (self.pos + bytes.len > self.payload.len)
            return SerializeError.OutOfBounds;
        std.mem.copy(u8, self.payload[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }
};

const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    OutOfBounds,
    OutOfValueBounds,
};

pub fn serialize(value: anytype, buffer: []u8) !usize {
    var serializer = Serializer.init(buffer);
    try CompoundTypeSerializer.serialize(@TypeOf(value), value, &serializer);
    return serializer.pos;
}

pub fn is_deployed(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "Inner") and @hasDecl(T, "Depl"),
        else => false,
    };
}

const CompoundTypeSerializer = struct {
    pub fn serialize(comptime T: type, value: T, serializer: *Serializer) !void {
        const deployed = comptime is_deployed(T);

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
                            switch (T.Depl) {
                                FixedStringDeployment => |depl| try serializer.serializeFixedString(depl.length, value.value),
                                DynamicStringDeployment => |depl| try serializer.serializeDynamicString(depl, value.value),
                                ArrayDeployment => |depl| try CompoundTypeSerializer.serializeSlice(serializer, p.child, depl, value.value),
                                else => try serializer.serializeDynamicString(.{}, value.value),
                            }
                        }
                        return;
                    }
                }
                if (deployed) {
                    const slice = @as([]const p.child, value.value);
                    try CompoundTypeSerializer.serializeSlice(serializer, p.child, T.Depl, slice);
                } else {
                    const slice = @as([]const p.child, value);
                    try CompoundTypeSerializer.serializeSlice(serializer, p.child, .{}, slice);
                }
            },
            else => @compileError("Unsupported type"),
        }
    }

    pub fn serializeSlice(serializer: *Serializer, comptime T: type, comptime depl: ArrayDeployment, value: []const T) !void {
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
                const DeployedField = Deployed(@TypeOf(field_value), @field(Depl, field.name));
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

    pub fn serializeUnion(comptime T: type, comptime depl: UnionDeployment, serializer: *Serializer, value: T) !void {
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
