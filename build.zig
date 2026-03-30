const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("rootlib", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const lib = b.addLibrary(.{ .linkage = .static, .name = "libzsip", .root_module = lib_mod });
    b.installArtifact(lib);

    const exe_mod = b.addModule("zsomeip_serializer", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{ .name = "zsip", .root_module = exe_mod });
    exe.linkLibrary(lib);
    b.installArtifact(exe);

    const client_mod = b.addModule("client", .{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    const client_exe = b.addExecutable(.{ .name = "client", .root_module = client_mod });
    client_exe.linkLibrary(lib);
    b.installArtifact(client_exe);

    const service_mod = b.addModule("service", .{
        .root_source_file = b.path("src/service.zig"),
        .target = target,
        .optimize = optimize,
    });
    const service_exe = b.addExecutable(.{ .name = "service", .root_module = service_mod });
    service_exe.linkLibrary(lib);
    b.installArtifact(service_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run integration tests");
    const test_files = [_][]const u8{
        "tests/arrays.zig",
        "tests/slices.zig",
        "tests/strings.zig",
        "tests/structs.zig",
        "tests/unions.zig",
        "tests/serialize_bench.zig",
    };
    for (test_files) |file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("libzsip", lib_mod);
        const test_exec = b.addTest(.{
            .name = std.fs.path.basename(file),
            .root_module = test_mod,
        });
        const run_test = b.addRunArtifact(test_exec);

        test_step.dependOn(&run_test.step);
    }
}
