const std = @import("std");

pub const stub = @import("stub.zig");
pub const protocol = @import("protocol.zig");
pub const StripDeployment = @import("deserialize.zig").StripDeployment;

pub const Test = @import("protocol.zig").Test;

const Greet = struct {
    greeting: []const u8,
};

fn handleTest(_: StripDeployment(Test)) Test {
    return Test{
        .a = 1,
        .b = 2,
        .c = 3,
        .text = "abcde",
    };
}

fn handleVoid(_: void) void {
    std.debug.print("Hanlde Void called!", .{});
}

fn handleInteger(i: u16) u32 {
    std.debug.print("Hanlde Int called with {}!", .{i});
    return 1234;
}

fn handleGreet(greeting: []const u8) []const u8 {
    std.debug.print("Proxy: {s}", .{greeting});
    return "Hi proxy, how is it going?";
}

pub const method_def = [_]protocol.MethodDef{
    .{
        .In = Test,
        .Out = Test,
        .method_id = 5678,
        .name = "testF",
    },
    .{
        .In = void,
        .Out = void,
        .method_id = 6666,
        .name = "voidF",
    },
    .{
        .In = u16,
        .Out = u32,
        .method_id = 6969,
        .name = "intF",
    },

    .{
        .In = []const u8,
        .Out = []const u8,
        .method_id = 1000,
        .name = "greet",
    },
};

const genHandleRequests = stub.handleRequests(&method_def, .{
    .testF = handleTest,
    .voidF = handleVoid,
    .intF = handleInteger,
    .greet = handleGreet,
});

pub fn main() !void {
    const listen_addr = try std.net.Address.initUnix("/tmp/service.sock");
    var server = try listen_addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    while (true) {
        var conn = try server.accept();

        _ = try std.Thread.spawn(.{}, genHandleRequests, .{ &conn.stream, gpa.allocator() });
    }
}
