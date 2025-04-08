const std = @import("std");

const include_spath = "vendor/include";
const lib_spath = "vendor/lib";
const bin_spath = "vendor/bin";

const xlsxio_dlls = [_][]const u8{
    "libxlsxio_read",
    "libxlsxio_write",
};

const static_dep_dlls = [_][]const u8{
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
    // Add dlls path if necessary
    if (!link_static) xlsxio_mod.addLibraryPath(b.path(bin_spath));

    // add static/import libraries depending on static/dynamic linking
    if (link_static) {
        // add static libraries
        if (read_only)
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ xlsxio_dlls[0] ++ ".a"))
        else inline for (xlsxio_dlls) |dll_name|
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ dll_name ++ ".a"));
        // add dependencies static libs
        inline for (static_dep_dlls) |dll_path|
            xlsxio_mod.addObjectFile(b.path(dll_path));
    } else {
        // add import library, link to dynamic library
        if (read_only) {
            xlsxio_mod.addObjectFile(b.path(lib_spath ++ "/" ++ xlsxio_dlls[0] ++ ".dll.a"));
            xlsxio_mod.linkSystemLibrary(xlsxio_dlls[0], .{});
        } else inline for (xlsxio_dlls) |dll_name| {
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
    const xlsxio_lib_path = getLibPath(b, dep);

    // Check if xlsxio is linked statically or dynamically
    if (dep.builder.user_input_options.get("link_static")) |link_static|
        if (link_static.value.scalar[0] == 't') {
            std.debug.print("xlsxio is linked statically, no need to copy the dynamic dlls to the bin directory\n", .{});
            return;
        };

    // Check if read_only was requested by user;
    const user_read_only = if (dep.builder.user_input_options.get("read_only")) |read_only|
        if (read_only.value.scalar[0] == 't') true else false
    else
        false;

    // copy dynamic dlls to build zig-out/bin directory
    if (user_read_only) {
        const dll_file = std.mem.concat(b.allocator, u8, &.{ xlsxio_dlls[0], ".dll" }) catch xlsxio_dlls[0];
        b.installBinFile(b.pathJoin(&.{ xlsxio_lib_path, dll_file }), dll_file);
    } else for (xlsxio_dlls) |dll_name| {
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
    const xlsxio_lib_path = getLibPath(b, dep);
    run.addPathDir(xlsxio_lib_path);
}

/// get xlsxio libraries path relative to build directory
fn getLibPath(
    b: *std.Build,
    dep: *std.Build.Dependency,
) []u8 {
    const build_root_path = if (b.build_root.path) |path|
        path
    else
        std.fs.cwd().realpathAlloc(b.allocator, ".") catch unreachable;
    const rel_path = std.fs.path.relative(b.allocator, build_root_path, dep.builder.pathFromRoot(".")) catch ".";
    return b.pathJoin(&.{ rel_path, "vendor/bin" });
}
