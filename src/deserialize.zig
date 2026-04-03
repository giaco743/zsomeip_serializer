const std = @import("std");
const root = @import("root.zig");

pub fn deserialize(comptime Out: type, allocator: std.mem.Allocator, input: []const u8) !StripDeployment(Out) {
    var deser = Deserializer.init(allocator, input);
    return try deser.deserialize(Out);
}

const Deserializer = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize = 0, // byte position

    fn init(allocator: std.mem.Allocator, input: []const u8) Deserializer {
        return Deserializer{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    fn deserializeInt(self: *Deserializer, comptime T: type) !T {
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
    fn deserializeFloat(self: *Deserializer, comptime T: type) !T {
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

    fn deserializeTag(self: *Deserializer, comptime widthType: root.Width) !WidthToType(widthType) {
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
    fn deserializeString(self: *Deserializer, length: usize) ![]const u8 {
        if (self.input[self.pos..].len < length)
            return root.SerializeError.BufferOverflow;
        const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };
        if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 3], &BOM))
            return root.SerializeError.BomMissing;
        if (self.input[self.pos + length - 1] != 0)
            return root.SerializeError.NullMissing;
        var buf = try self.allocator.alloc(u8, length - 4);
        @memcpy(buf[0..], self.input[self.pos + 3 .. self.pos + length - 1]);
        self.pos += length;
        return buf;
    }
    fn deserializeDynamicString(self: *Deserializer, comptime depl: root.DynamicStringDeployment) ![]const u8 {
        const length = try self.deserializeTag(depl.lengthWidth);
        return try self.deserializeString(length);
    }
    fn deserializeFixedString(self: *Deserializer, comptime length: u64) ![]const u8 {
        return try self.deserializeString(length);
    }
    fn deserializeArray(self: *Deserializer, comptime T: type, comptime Size: usize) ![Size]T {
        var result: [Size]T = undefined;
        for (0..Size) |i| {
            result[i] = try self.deserialize(T);
        }
        return result;
    }
    fn deserializeSlice(self: *Deserializer, comptime Child: type, comptime depl: root.ArrayDeployment) (root.SerializeError || error{OutOfMemory})![]Child {
        const size = try self.deserializeTag(depl.lengthWidth);
        const end_pos = self.pos + size;

        var list = std.ArrayList(Child){};
        defer list.deinit(self.allocator);

        while (self.pos < end_pos) {
            try list.append(self.allocator, try self.deserialize(Child));
        }

        if (self.pos != end_pos) {
            return root.SerializeError.InvalidLength;
        }

        return list.toOwnedSlice(self.allocator);
    }
    fn deserializeUnion(self: *Deserializer, comptime T: type, comptime depl: root.UnionDeployment) (root.SerializeError || error{OutOfMemory})!T {
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
    fn deserialize(self: *Deserializer, comptime T: type) !StripDeployment(T) {
        const deployed = comptime root.is_deployed(T);

        const StrippedType = StripDeployment(T);
        const InnerType = comptime if (deployed) T.Inner else T;

        const info = @typeInfo(InnerType);
        switch (info) {
            .void => {
                std.debug.print("Recieved void to deserialize", .{});
                return void{};
            },
            .@"enum" => |e| {
                const val = try self.deserializeInt(e.tag_type);
                std.debug.print("Deserializing enum {s}, got value {x}\n", .{ @typeName(T), val });
                return @enumFromInt(val);
            },
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
            .array => |a| {
                return try self.deserializeArray(a.child, a.len);
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
                        } else {
                            if (deployed) {
                                if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                    return try self.deserializeSlice(p.child, T.Depl);
                                } else {
                                    @compileError("Wrong deployment for slice");
                                }
                            } else {
                                return try self.deserializeSlice(p.child, root.ArrayDeployment{});
                            }
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
                                } else {
                                    if (deployed) {
                                        if (@TypeOf(T.Depl) == root.ArrayDeployment) {
                                            return try self.deserializeSlice(a.child, T.Depl);
                                        } else {
                                            @compileError("Wrong deployment for slice");
                                        }
                                    } else {
                                        return try self.deserializeSlice(p.child, root.ArrayDeployment{});
                                    }
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
    return StripDeploymentImpl(T).T;
}

pub fn StripDeploymentImpl(comptime T: type) struct { T: type, has_depl: bool } {
    if (root.is_deployed(T)) {
        return .{ .T = StripDeployment(T.Inner), .has_depl = true };
    }

    var has_depl = false;
    return switch (@typeInfo(T)) {
        .@"struct" => |s| {
            var fields: [s.fields.len]std.builtin.Type.StructField = undefined;

            inline for (s.fields, 0..) |f, i| {
                const sd_ty = StripDeploymentImpl(f.type);
                has_depl = sd_ty.has_depl;
                fields[i] = .{
                    .name = f.name,
                    .type = sd_ty.T,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(sd_ty.T),
                };
            }

            if (has_depl) {
                return .{
                    .T = @Type(.{
                        .@"struct" = .{
                            .layout = s.layout,
                            .fields = &fields,
                            .decls = &.{},
                            .is_tuple = false,
                        },
                    }),
                    .has_depl = true,
                };
            } else {
                return .{ .T = T, .has_depl = false };
            }
        },

        else => return .{ .T = T, .has_depl = false },
    };
}
