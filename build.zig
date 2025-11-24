const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "test",
        .linkage = .static,
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "gbemu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        // In the current Zig version (0.15.2) the self-hosted compiler leads to
        // massive performance slowdowns, so temporarily falling back to LLVM builds.
        .use_llvm = true,
    });
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC();

    const constants = b.createModule(.{ .root_source_file = b.path("src/constants/root.zig") });
    exe.root_module.addImport("constants", constants);

    const util = b.createModule(.{ .root_source_file = b.path("src/util/root.zig") });
    exe.root_module.addImport("util", util);

    const core = b.addModule("core", .{ .root_source_file = b.path("src/core/root.zig") });
    core.addImport("constants", constants);
    core.addImport("util", util);
    // {
    //     const cpu = b.createModule(.{ .root_source_file = b.path("src/core/cpu/root.zig") });
    //     core.addImport("cpu", cpu);
    //     const dma = b.createModule(.{ .root_source_file = b.path("src/core/dma/root.zig") });
    //     core.addImport("dma", dma);
    //     const timer = b.createModule(.{ .root_source_file = b.path("src/core/timer/root.zig") });
    //     core.addImport("timer", timer);
    //     const joypad = b.createModule(.{ .root_source_file = b.path("src/core/joypad/root.zig") });
    //     core.addImport("joypad", joypad);
    //     const ppu = b.createModule(.{ .root_source_file = b.path("src/core/ppu/root.zig") });
    //     core.addImport("ppu", ppu);
    //     const apu = b.createModule(.{ .root_source_file = b.path("src/core/apu/root.zig") });
    //     core.addImport("apu", apu);
    //     const cart = b.createModule(.{ .root_source_file = b.path("src/core/cart/root.zig") });
    //     core.addImport("cart", cart);
    //     const memory = b.createModule(.{ .root_source_file = b.path("src/core/memory/root.zig") });
    //     core.addImport("memory", memory);
    //     const timing = b.createModule(.{ .root_source_file = b.path("src/core/timing/root.zig") });
    //     core.addImport("timing", timing);
    //     const bess = b.createModule(.{
    //         .root_source_file = b.path("src/core/bess/root.zig"),
    //         .imports = &.{.{
    //             .name = "cart",
    //             .module = cart,
    //         }},
    //     });
    //     core.addImport("bess", bess);
    //     const debug = b.createModule(.{
    //         .root_source_file = b.path("src/core/debug/root.zig"),
    //         .imports = &.{
    //             .{
    //                 .name = "util",
    //                 .module = util,
    //             },
    //             .{
    //                 .name = "joypad",
    //                 .module = joypad,
    //             },
    //         },
    //     });
    //     core.addImport("debug", debug);
    // }
    exe.root_module.addImport("core", core);

    const sdl = b.createModule(.{ .root_source_file = b.path("src/sdl/root.zig") });
    sdl.addImport("core", core);
    sdl.addImport("constants", constants);
    exe.root_module.addImport("sdl", sdl);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
