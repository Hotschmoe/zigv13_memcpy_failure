const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a72 },
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("memcpy_repro.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "memcpy_repro",
        .root_module = root_module,
        .linkage = .static,
        .strip = false,
    });

    exe.setLinkerScript(b.path("linker.ld"));
    b.installArtifact(exe);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-aarch64",
        "-machine", "virt",
        "-cpu", "cortex-a72",
        "-m", "128M",
        "-nographic",
        "-monitor", "none",
        "-chardev", "stdio,id=uart0",
        "-serial", "chardev:uart0",
        "-d", "cpu_reset,guest_errors,unimp,in_asm",
        "-D", "qemu.log",
        "-smp", "1",
        "-kernel", "zig-out/bin/memcpy_repro",
    });
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the reproduction");
    run_step.dependOn(&run_cmd.step);
}
