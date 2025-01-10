const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the modules
    const shared_secrets_module = b.addModule("shared-secrets", .{
        .source_file = .{ .path = "src/zig/model.zig" },
    });

    const crypto_module = b.addModule("crypto", .{
        .source_file = .{ .path = "src/zig/crypto.zig" },
        .dependencies = &.{
            .{ .name = "shared-secrets", .module = shared_secrets_module },
        },
    });

    // Create the library
    const lib = b.addStaticLibrary(.{
        .name = "shared-secrets",
        .root_source_file = .{ .path = "src/zig/model.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add module dependencies to the library
    lib.addModule("shared-secrets", shared_secrets_module);
    lib.addModule("crypto", crypto_module);

    b.installArtifact(lib);

    // Create unit tests
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zig/model.zig" },
        .target = target,
        .optimize = optimize,
    });

    const crypto_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zig/crypto.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(main_tests);
    const run_crypto_tests = b.addRunArtifact(crypto_tests);

    // Create a test step
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_crypto_tests.step);
}
