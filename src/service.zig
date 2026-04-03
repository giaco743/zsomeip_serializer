const std = @import("std");

pub const stub = @import("stub.zig");
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

const method_def = [_]stub.MethodDef{stub.MethodDef{
    .method = stub.bindHandler(StripDeployment(Test), Test, handleTest),
    .method_id = 5678,
}};

const genHandleRequests = stub.handleRequests(&method_def);

pub fn main() !void {
    const listen_addr = try std.net.Address.initUnix("/tmp/service.sock");
    var server = try listen_addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        try genHandleRequests(&conn.stream, gpa.allocator());
    }
}
