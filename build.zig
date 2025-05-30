const std = @import("std");

const include_spath = "vendor/include";
const lib_spath = "vendor/lib";
const bin_spath = "vendor/bin";

const xlsxio_lib = [_][]const u8{
    "libxlsxio_read",
    "libxlsxio_write",
};

const static_dep_lib = [_][]const u8{
    lib_spath ++ "/libexpat.a",
    lib_spath ++ "/libminizip.a",
    lib_spath ++ "/libz.a",
    lib_spath ++ "/libbz2.a",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose an option "install_dlls" (default true)
    const link_static = b.option(bool, "link_static", "link xlsxio library statically {default: false)") orelse false;
    const read_only = b.option(bool, "read_only", "Only include the read library (default: false)") orelse false;

    // Define the xlsxio module.
    const xlsxio_mod = b.addModule("xlsxio", .{
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Add include path for @cImport
    xlsxio_mod.addIncludePath(b.path(include_spath));

    // Add C api module
    const xlsxio_api = b.addTranslateC(.{
        .root_source_file = b.path("include/c.h"),
        .target = target,
        .optimize = optimize,
    });

    xlsxio_api.addIncludePath(b.path(include_spath));
    xlsxio_mod.addImport("xlsxio_c", xlsxio_api.createModule());

    // Add dlls path if necessary
    if (!link_static) xlsxio_mod.addLibraryPath(b.path(bin_spath));

    // add static/import libraries depending on static/dynamic linking
    if (link_static) {
        // add static libraries
        if (read_only)
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ xlsxio_lib[0] ++ ".a"))
        else inline for (xlsxio_lib) |dll_name|
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ dll_name ++ ".a"));
        // add dependencies static libs
        inline for (static_dep_lib) |dll_path|
            xlsxio_mod.addObjectFile(b.path(dll_path));
    } else {
        // add import library, link to dynamic library
        if (read_only) {
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ xlsxio_lib[0] ++ ".dll.a"));
            xlsxio_mod.linkSystemLibrary(xlsxio_lib[0], .{});
        } else inline for (xlsxio_lib) |dll_name| {
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ dll_name ++ ".dll.a"));
            xlsxio_mod.linkSystemLibrary(dll_name, .{});
        }
    }
}

/// copy Xlsxio dynamic libraries to zig-out/bin
pub fn copyXlsxioDlls(
    b: *std.Build,
    dep: *std.Build.Dependency,
) void {
    const is_xlsxio_lib_path = getLibPath(b, dep);
    // return if xlsxio is linked statically
    if (is_xlsxio_lib_path == null) return;
    const xlsxio_lib_path = is_xlsxio_lib_path.?;

    // Check if read_only was requested by user;
    const user_read_only = if (dep.builder.user_input_options.get("read_only")) |read_only|
        if (read_only.value.scalar[0] == 't') true else false
    else
        false;

    // copy dynamic dlls to build zig-out/bin directory
    if (user_read_only) {
        const dll_file = std.mem.concat(b.allocator, u8, &.{ xlsxio_lib[0], ".dll" }) catch xlsxio_lib[0];
        b.installBinFile(b.pathJoin(&.{ xlsxio_lib_path, dll_file }), dll_file);
    } else for (xlsxio_lib) |dll_name| {
        const dll_file = std.mem.concat(b.allocator, u8, &.{ dll_name, ".dll" }) catch dll_name;
        b.installBinFile(b.pathJoin(&.{ xlsxio_lib_path, dll_file }), dll_file);
    }
}

/// Add Xlsxio dynamic libraries path to Run command
pub fn addRunPath(
    b: *std.Build,
    dep: *std.Build.Dependency,
    run: *std.Build.Step.Run,
) void {
    // only add path if xlsxio is linked dynamically
    if (getLibPath(b, dep)) |xlsxio_lib_path| run.addPathDir(xlsxio_lib_path);
}

/// get xlsxio libraries path relative to build directory
fn getLibPath(
    b: *std.Build,
    dep: *std.Build.Dependency,
) ?[]u8 {
    // Check if xlsxio is linked statically or dynamically
    if (dep.builder.user_input_options.get("link_static")) |link_static|
        if (link_static.value.scalar[0] == 't') {
            std.debug.print("xlsxio is linked statically, no need to copy the dynamic dlls or add their path to run cmd\n", .{});
            return null;
        };

    const build_root_path = if (b.build_root.path) |path|
        path
    else
        std.fs.cwd().realpathAlloc(b.allocator, ".") catch unreachable;
    const rel_path = std.fs.path.relative(b.allocator, build_root_path, dep.builder.pathFromRoot(".")) catch ".";
    return b.pathJoin(&.{ rel_path, bin_spath });
}
