const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .os_tag = .windows,
        .cpu_arch = .x86_64,
    });
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.createModule(.{
        .root_source_file = b.path("../_shared/src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
            .name = "05-hwbp-syscall",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "veh_shared", .module = shared },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the demo");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
}
