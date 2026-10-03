const std = @import("std");

// Build the pinned raylib C sources directly: its upstream build.zig uses APIs
// removed in Zig 0.17. Resolve the package through Zig's generated dependency
// table without invoking that script or modifying the downloaded package.
fn sourceRoot(b: *std.Build) std.Build.LazyPath {
    const dependencies = @import("root").dependencies;
    inline for (dependencies.root_deps) |dep| {
        if (comptime std.mem.eql(u8, dep[0], "raylib")) {
            const package = @field(dependencies.packages, dep[1]);
            return b.graph.cwdRelativePath(package.build_root);
        }
    }
    @compileError("raylib dependency is missing from build.zig.zon");
}

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct { library: *std.Build.Step.Compile, bindings: *std.Build.Module } {
    const source = sourceRoot(b);
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(source.path(b, "src"));
    mod.addIncludePath(source.path(b, "src/platforms"));
    mod.addIncludePath(source.path(b, "src/external/glfw/include"));
    mod.addCMacro("PLATFORM_DESKTOP_GLFW", "");
    mod.addCMacro("_GNU_SOURCE", "");
    mod.addCMacro("GL_SILENCE_DEPRECATION", "199309L");
    const flags = &.{ "-std=gnu99", "-fno-sanitize=undefined" };
    mod.addCSourceFiles(.{
        .root = source,
        .files = &.{ "src/rcore.c", "src/utils.c", "src/rshapes.c", "src/rtextures.c", "src/rtext.c", "src/rmodels.c", "src/raudio.c" },
        .flags = flags,
    });
    if (target.result.os.tag == .macos) {
        mod.addCSourceFile(.{ .file = source.path(b, "src/rglfw.c"), .flags = &.{ "-std=gnu99", "-fno-sanitize=undefined", "-ObjC" } });
    } else {
        mod.addCSourceFile(.{ .file = source.path(b, "src/rglfw.c"), .flags = flags });
    }
    switch (target.result.os.tag) {
        .windows => {
            for ([_][]const u8{ "winmm", "gdi32", "opengl32" }) |lib| mod.linkSystemLibrary(lib, .{});
        },
        .linux => {
            mod.addCMacro("_GLFW_X11", "");
            for ([_][]const u8{ "GL", "X11", "Xrandr", "Xinerama", "Xi", "Xcursor" }) |lib| mod.linkSystemLibrary(lib, .{});
        },
        .macos => {
            for ([_][]const u8{ "Foundation", "CoreServices", "CoreGraphics", "AppKit", "IOKit" }) |framework| mod.linkFramework(framework, .{});
        },
        else => @panic("Unsupported desktop platform for raylib"),
    }
    const lib = b.addLibrary(.{ .name = "raylib", .linkage = .static, .root_module = mod });
    lib.installHeader(source.path(b, "src/raylib.h"), "raylib.h");
    lib.installHeader(source.path(b, "src/raymath.h"), "raymath.h");
    const bindings = b.addTranslateC(.{
        .root_source_file = source.path(b, "src/raylib.h"),
        .target = target,
        .optimize = optimize,
    });
    return .{ .library = lib, .bindings = bindings.createModule() };
}
