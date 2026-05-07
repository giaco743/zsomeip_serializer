const std = @import("std");
pub const serialize = @import("serialize.zig").serialize;
pub const deserialize = @import("deserialize.zig").deserialize;

pub const SerializeError = error{
    InvalidType,
    BufferOverflow,
    Unaligned,
    OutOfBounds,
    OutOfValueBounds,
    BomMissing,
    NullMissing,
    InvalidLength,
    InvalidUnionTag,
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

pub fn WidthToType(comptime widthType: Width) type {
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
    if (is_deployed(T)) {
        return .{ .T = StripDeployment(T.Inner), .has_depl = true };
    }

    var has_depl = false;
    return switch (@typeInfo(T)) {
        .@"struct" => |s| {
            var field_names: [10][]const u8 = undefined;
            var field_types: [10]type = undefined;

            var n_fields = 0;

            inline for (s.fields, 0..) |f, i| {
                const sd_ty = StripDeploymentImpl(f.type);
                has_depl = sd_ty.has_depl;
                field_names[i] = f.name;
                field_types[i] = sd_ty.T;
                n_fields += 1;
            }

            if (has_depl) {
                return .{
                    .T = @Struct(.auto, null, field_names[0..n_fields], field_types[0..n_fields], &@splat(.{})),
                    .has_depl = true,
                };
            } else {
                return .{ .T = T, .has_depl = false };
            }
        },

        else => return .{ .T = T, .has_depl = false },
    };
}

test "StripDeployment removes deployment from dynamic string" {
    const DStr = Deployed([]const u8, .{
        .lengthWidth = .U16,
    });

    const Stripped = StripDeployment(DStr);

    comptime {
        std.debug.assert(Stripped == []const u8);
    }
}

test "StripDeployment strips string field deployment" {
    const S = struct {
        name: Deployed([]const u8, .{
            .lengthWidth = .U8,
        }),
    };

    const Stripped = StripDeployment(S);

    const Expected = struct {
        name: []const u8,
    };

    comptime {
        const a = @typeInfo(Stripped).@"struct";
        const b = @typeInfo(Expected).@"struct";

        std.debug.assert(a.fields.len == b.fields.len);

        for (a.fields, b.fields) |fa, fb| {
            std.debug.assert(std.mem.eql(u8, fa.name, fb.name));
            std.debug.assert(fa.type == fb.type);
        }
    }
}

test "StripDeployment does not change the type if there is no deployment" {
    const S = struct {
        val: u32,
        name: []const u8,
    };

    const Stripped = StripDeployment(S);
    try std.testing.expect(Stripped == S);
}

test "deserialize returns stripped type for string deployment" {
    const DStr = Deployed([]const u8, DynamicStringDeployment{
        .lengthWidth = .U16,
    });
    const S = struct {
        name: DStr,
    };

    const Stripped = StripDeployment(S);

    try std.testing.expect(Stripped != S);

    var buffer: [256]u8 = undefined;

    const input = S{
        .name = DStr.wrap("hello"),
    };

    const n = try serialize(input, &buffer);
    // 2 bytes size + 3 bytes BOM + 5 bytes "hello" + 1 byte \0
    try std.testing.expectEqual(n, 11);

    const allocator = std.testing.allocator;
    const result = try deserialize(S, allocator, &buffer);
    defer allocator.free(result.name);

    const stripped: Stripped = result;

    try std.testing.expectEqualStrings("hello", stripped.name);
}

test "deserialize returns stripped type for string deployment also nested" {
    const DStr = Deployed([]const u8, DynamicStringDeployment{
        .lengthWidth = .U16,
    });
    const S = struct {
        name: DStr,
    };

    const D = struct {
        val: u32,
        inner: S,
    };

    const Stripped = StripDeployment(D);

    var buffer: [256]u8 = undefined;

    const input = D{
        .val = 123,
        .inner = S{
            .name = DStr.wrap("hello"),
        },
    };

    const n = try serialize(input, &buffer);
    // 4 bytes (u32) + 2 bytes size + 3 bytes BOM + 5 bytes "hello" + 1 byte \0
    try std.testing.expectEqual(n, 15);

    const allocator = std.testing.allocator;
    const result = try deserialize(D, allocator, &buffer);
    defer allocator.free(result.inner.name);

    const stripped: Stripped = result;

    try std.testing.expectEqual(123, stripped.val);
    try std.testing.expectEqualStrings("hello", stripped.inner.name);
}

pub const U16Str = Deployed([]const u8, DynamicStringDeployment{ .lengthWidth = .U16 });

pub const Greet = struct {
    greeting: U16Str,
};
