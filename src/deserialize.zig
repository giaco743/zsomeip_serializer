const std = @import("std");
const root = @import("root.zig");

pub const Deserializer = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize = 0, // byte position

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Deserializer {
        return Deserializer{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    pub fn deserializeInt(self: *Deserializer, comptime T: type) !T {
        const info = @typeInfo(T);
        switch (info) {
            .int => {
                if ((info.int.bits % 8) == 0) {
                    const size = @sizeOf(T);
                    if (self.pos + size > self.input.len)
                        return root.SerializeError.OutOfBounds;

                    const ptr: *const [size]u8 = @ptrCast(self.input[self.pos..].ptr);
                    const result = std.mem.readInt(T, ptr, .big);
                    self.pos += size;
                    return result;
                } else {
                    @compileError("Bit sized integers are not yet supported");
                }
            },
            else => @compileError("T must be an integer type"),
        }
    }
    pub fn deserializeFloat(self: *Deserializer, comptime T: type) !T {
        const info = @typeInfo(T);
        if (info != .float)
            @compileError("T must be a float type");

        const IntT = std.meta.Int(.unsigned, @bitSizeOf(T));

        const size = @sizeOf(T);
        if (self.pos + size > self.input.len)
            return root.SerializeError.OutOfBounds;

        const ptr: *[size]u8 = @ptrCast(self.input[self.pos..].ptr);
        const resultAsInt = std.mem.readInt(IntT, ptr, .big);
        self.pos += size;
        return @bitCast(resultAsInt);
    }

    pub fn deserializeTag(self: *Deserializer, comptime widthType: root.Width) !WidthToType(widthType) {
        switch (widthType) {
            .U8 => {
                const result: u8 = try self.deserializeInt(WidthToType(widthType));
                return result;
            },
            .U16 => {
                const result: u16 = try self.deserializeInt(WidthToType(widthType));
                return result;
            },
            .U32 => {
                const result: u32 = try self.deserializeInt(WidthToType(widthType));
                return result;
            },
        }
    }
    pub fn deserializeString(self: *Deserializer, length: usize) ![]const u8 {
        if (self.input[self.pos..].len < length)
            return root.SerializeError.BufferOverflow;
        const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };
        if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 3], &BOM))
            return root.SerializeError.BomMissing;
        if (self.input[self.pos + length - 1] != 0)
            return root.SerializeError.NullMissing;
        const result = self.input[self.pos + 3 .. self.pos + (length - 1)];
        self.pos += length;
        return result;
    }
    pub fn deserializeDynamicString(self: *Deserializer, comptime depl: root.DynamicStringDeployment) ![]const u8 {
        const length = try self.deserializeTag(depl.lengthWidth);
        return try self.deserializeString(length);
    }
    pub fn deserializeFixedString(self: *Deserializer, comptime length: u64) ![]const u8 {
        return try self.deserializeString(length);
    }
    pub fn deserializeArray(self: *Deserializer, comptime T: type, comptime Size: usize) ![Size]T {
        var buffer = try self.arena.allocator().alloc(T, Size);
        for (0..Size) |i| {
            buffer[i] = try self.deserialize();
        }
        return buffer;
    }
    pub fn deserializeSlice(self: *Deserializer, comptime Child: type, comptime depl: root.ArrayDeployment) (root.SerializeError || error{OutOfMemory})![]Child {
        const size = try self.deserializeTag(depl.lengthWidth);
        // Check that byteLength is a multiple of element size
        if (size % @sizeOf(Child) != 0) {
            return root.SerializeError.InvalidLength; // your custom error
        }
        const length = size / @sizeOf(Child);
        var slice = try self.allocator.alloc(Child, length);

        for (slice[0..]) |*elem| {
            elem.* = try self.deserialize(Child);
        }

        return slice;
    }
    pub fn deserializeUnion(self: *Deserializer, comptime T: type, comptime depl: root.UnionDeployment) (root.SerializeError || error{OutOfMemory})!T {
        const info = @typeInfo(T);
        if (info != .@"union")
            @compileError("T must be a float type");
        _ = try self.deserializeTag(depl.lengthWidth);
        const discriminant = try self.deserializeTag(depl.typeWidth);
        const fields = info.@"union".fields;
        inline for (fields, 0..) |field, i| {
            if (discriminant == i + 1) {
                const payload = try self.deserialize(field.type);
                return @unionInit(T, field.name, payload);
            }
        }
        return error.InvalidUnionTag;
    }
    pub fn deserialize(self: *Deserializer, comptime T: type) !StripDeployment(T) {
        const deployed = comptime root.is_deployed(T);

        const StrippedType = StripDeployment(T);
        const InnerType = comptime if (deployed) T.Inner else T;

        const info = @typeInfo(InnerType);
        switch (info) {
            .@"struct" => |s| {
                var result: StrippedType = undefined;
                if (deployed) {
                    inline for (s.fields) |field| {
                        if (@hasField(@TypeOf(T.Depl), field.name)) {
                            std.debug.print("Deserializing {any}", .{field.name});
                            const DeployedField = root.Deployed(field.type, @field(T.Depl, field.name));
                            const field_value = try self.deserialize(DeployedField);
                            @field(result, field.name) = field_value;
                        } else {
                            @field(result, field.name) = try self.deserialize(field.type);
                        }
                    }
                } else {
                    inline for (s.fields) |field| {
                        @field(result, field.name) = try self.deserialize(field.type);
                    }
                }
                return result;
            },
            .@"union" => {
                if (deployed) {
                    if (@TypeOf(T.Depl) != root.UnionDeployment) {
                        @compileError("Wrong deployment for union");
                    }
                    return try self.deserializeUnion(InnerType, T.Depl);
                } else {
                    return try self.deserializeUnion(InnerType, root.UnionDeployment{});
                }
            },
            .int => {
                return try self.deserializeInt(T);
            },
            .float => {
                return try self.deserializeFloat(T);
            },
            .array => {
                return try self.deserializeArray(info.array.child, T.Depl);
            },
            .pointer => |p| {
                switch (p.size) {
                    .slice => {
                        if (p.child == u8) {
                            if (deployed) {
                                if (@TypeOf(T.Depl) == root.DynamicStringDeployment) {
                                    return try self.deserializeDynamicString(T.Depl);
                                } else if (@TypeOf(T.Depl) == root.FixedStringDeployment) {
                                    return try self.deserializeFixedString(T.Depl.length);
                                } else if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                    return try self.deserializeSlice(p.child, T.Depl);
                                } else {
                                    @compileError("Wrong deployment for u8 slice");
                                }
                            } else {
                                return try self.deserializeDynamicString(root.DynamicStringDeployment{});
                            }
                        }
                        if (deployed) {
                            if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                return try self.deserializeSlice(p.child, T.Depl);
                            } else {
                                @compileError("Wrong deployment for slice");
                            }
                        } else {
                            return try self.deserializeSlice(p.child, root.ArrayDeployment{});
                        }
                    },
                    .one => {
                        switch (@typeInfo(p.child)) {
                            .array => |a| {
                                if (a.child == u8) {
                                    if (deployed) {
                                        if (@TypeOf(T.Depl) == root.DynamicStringDeployment) {
                                            return try self.deserializeDynamicString(T.Depl);
                                        } else if (@TypeOf(T.Depl) == root.FixedStringDeployment) {
                                            return try self.deserializeFixedString(T.Depl.length);
                                        } else if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                            return try self.deserializeSlice(u8, T.Depl);
                                        } else {
                                            @compileError("Wrong deployment for u8 slice");
                                        }
                                    } else {
                                        return try self.deserializeDynamicString(root.DynamicStringDeployment{});
                                    }
                                }
                                if (deployed) {
                                    if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                        return try self.deserializeSlice(a.child, T.Depl);
                                    } else {
                                        @compileError("Wrong deployment for slice");
                                    }
                                } else {
                                    return try self.deserializeSlice(p.child, root.ArrayDeployment{});
                                }
                            },
                            else => {
                                @compileError("Unsupported single elem pointer type");
                            },
                        }
                    },
                    else => {
                        @compileError("Unsupported pointer type");
                    },
                }
            },
            else => @compileError("Unsupported type"),
        }
    }
};

fn WidthToType(comptime widthType: root.Width) type {
    return switch (widthType) {
        .U8 => u8,
        .U16 => u16,
        .U32 => u32,
    };
}

pub fn StripDeployment(comptime T: type) type {
    if (root.is_deployed(T))
        return StripDeployment(T.Inner);

    return switch (@typeInfo(T)) {
        .@"struct" => |s| {
            var fields: [s.fields.len]std.builtin.Type.StructField = undefined;

            inline for (s.fields, 0..) |f, i| {
                fields[i] = .{
                    .name = f.name,
                    .type = StripDeployment(f.type),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(StripDeployment(f.type)),
                };
            }

            return @Type(.{
                .@"struct" = .{
                    .layout = s.layout,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        },

        else => return T,
    };
}
