const std = @import("std");
const root = @import("root.zig");

pub fn serialize(value: anytype, buffer: []u8) !usize {
    var serializer = Serializer{ .buffer = buffer, .pos = 0 };
    try serializer.serializeImpl(@TypeOf(value), value);
    return serializer.pos;
}

const Serializer = struct {
    buffer: []u8,
    pos: usize = 0,

    pub fn serializeImpl(self: *Serializer, comptime T: type, value: T) !void {
        const deployed = comptime root.is_deployed(T);

        const ActualType = comptime if (deployed) T.Inner else T;

        const info = @typeInfo(ActualType);

        switch (info) {
            .@"struct" => {
                if (deployed) {
                    try self.serializeStruct(ActualType, T.Depl, value.value);
                } else {
                    try self.serializeStruct(ActualType, struct {}{}, value);
                }
            },
            .@"union" => {
                if (deployed) {
                    try self.serializeUnion(ActualType, T.Depl, value.value);
                } else {
                    try self.serializeUnion(ActualType, .{}, value);
                }
            },
            .int => {
                try self.serializeInt(ActualType, value);
            },
            .float => {
                try self.serializeFloat(ActualType, value);
            },
            .array => |a| {
                try self.serializeArray(a.child, a.len, value);
            },
            .pointer => |p| {
                switch (p.size) {
                    .slice => {
                        if (p.child == u8) {
                            if (deployed) {
                                if (@TypeOf(T.Depl) == root.DynamicStringDeployment) {
                                    try self.serializeDynamicString(T.Depl, value.value);
                                } else if (@TypeOf(T.Depl) == root.FixedStringDeployment) {
                                    try self.serializeString(value.value);
                                } else if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                    try self.serializeSlice(u8, T.Depl, value.value);
                                } else {
                                    @compileError("Wrong deployment");
                                }
                            } else {
                                try self.serializeDynamicString(.{}, value);
                            }
                        } else {
                            if (deployed) {
                                try self.serializeSlice(p.child, T.Depl, value.value);
                            } else {
                                try self.serializeSlice(p.child, .{}, value);
                            }
                        }
                    },
                    .one => {
                        switch (@typeInfo(p.child)) {
                            .array => |a| {
                                if (a.child == u8) {
                                    if (deployed) {
                                        if (@TypeOf(T.Depl) == root.DynamicStringDeployment) {
                                            try self.serializeDynamicString(T.Depl, value.value.*[0..]);
                                        } else if (@TypeOf(T.Depl) == root.FixedStringDeployment) {
                                            try self.serializeString(value.value.*[0..]);
                                        } else if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                            try self.serializeSlice(u8, T.Depl, value.value.*[0..]);
                                        } else {
                                            @compileError("Wrong deployment");
                                        }
                                    } else {
                                        try self.serializeDynamicString(.{}, value.*[0..]);
                                    }
                                } else {
                                    if (deployed) {
                                        try self.serializeSlice(a.child, T.Depl, value.value.*[0..]);
                                    } else {
                                        try self.serializeSlice(a.child, .{}, value.*[0..]);
                                    }
                                }
                            },
                            else => {
                                @compileError("Unsupported one elem pointer");
                            },
                        }
                    },
                    else => {
                        @compileError("Unsupported pointer");
                    },
                }
            },
            else => @compileError("Unsupported type"),
        }
    }

    pub fn serializeInt(self: *Serializer, comptime T: type, value: T) !void {
        const info = @typeInfo(T);
        switch (info) {
            .int => {
                if ((info.int.bits % 8) == 0) {
                    var buf: [@sizeOf(T)]u8 = undefined;
                    std.mem.writeInt(T, &buf, value, .big);
                    try self.writeBytes(buf[0..]);
                } else {
                    @compileError("Bit sized integers are not yet supported");
                }
            },
            else => @compileError("T must be an integer type"),
        }
    }
    pub fn serializeFloat(self: *Serializer, comptime T: type, value: T) !void {
        comptime {
            if (@typeInfo(T) != .float)
                @compileError("T must be a float type");
        }

        const IntT = std.meta.Int(.unsigned, @bitSizeOf(T));
        const bits: IntT = @bitCast(value);

        try self.serializeInt(IntT, bits);
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
    pub fn serializeDynamicString(self: *Serializer, comptime depl: root.DynamicStringDeployment, value: []const u8) !void {
        const lenght = value.len + 4;
        try self.serializeTag(depl.lengthWidth, lenght);
        try self.serializeString(value);
    }
    pub fn serializeString(self: *Serializer, value: []const u8) !void {
        const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };
        try self.writeBytes(BOM[0..]);
        try self.writeBytes(value);
        const NULL = [1]u8{0x00};
        try self.writeBytes(NULL[0..]);
    }
    pub fn writeBytes(self: *Serializer, bytes: []const u8) !void {
        if (self.buffer.len - self.pos < bytes.len)
            return root.SerializeError.BufferOverflow;
        @memcpy(self.buffer[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }

    pub fn serializeSlice(self: *Serializer, comptime T: type, comptime depl: root.ArrayDeployment, value: []const T) !void {
        const length_pos = self.pos;
        try self.serializeTag(depl.lengthWidth, 0);
        const start_pos = self.pos;

        for (value) |element| {
            try self.serializeImpl(T, element);
        }

        const end_pos = self.pos;
        self.pos = length_pos;

        try self.serializeTag(depl.lengthWidth, end_pos - start_pos);

        self.pos = end_pos;
    }

    pub fn serializeArray(self: *Serializer, comptime T: type, comptime Size: usize, value: [Size]T) !void {
        for (value) |element| {
            try self.serializeImpl(@TypeOf(element), element);
        }
    }

    pub fn serializeStruct(self: *Serializer, comptime T: type, comptime Depl: anytype, value: T) !void {
        comptime {
            if (@typeInfo(T) != .@"struct")
                @compileError("T must be a struct type");
        }

        inline for (@typeInfo(T).@"struct".fields) |field| {
            const field_value = @field(value, field.name);

            if (@hasField(@TypeOf(Depl), field.name)) {
                const DeployedField = root.Deployed(@TypeOf(field_value), @field(Depl, field.name));
                try self.serializeImpl(
                    DeployedField,
                    DeployedField.wrap(field_value),
                );
            } else {
                try self.serializeImpl(
                    @TypeOf(field_value),
                    field_value,
                );
            }
        }
    }

    pub fn serializeUnion(self: *Serializer, comptime T: type, comptime depl: root.UnionDeployment, value: T) !void {
        comptime {
            if (@typeInfo(T) != .@"union")
                @compileError("serializeUnion expects a union type");
        }
        switch (value) {
            inline else => |payload, tag| {
                const length_pos = self.pos;
                try self.serializeTag(depl.lengthWidth, 0);

                const start_pos = self.pos;
                const tag_int = @intFromEnum(tag);
                try self.serializeTag(depl.typeWidth, tag_int + 1);

                try self.serializeImpl(@TypeOf(payload), payload);
                const end_pos = self.pos;

                self.pos = length_pos;
                try self.serializeTag(depl.lengthWidth, end_pos - start_pos);
                self.pos = end_pos;
            },
        }
    }
};
