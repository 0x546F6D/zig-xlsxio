# zig-xlsxio

A Zig wrapper for [xlsxio](https://github.com/brechtsanders/xlsxio), a library for reading and writing Excel XLSX files.

## Features

- Read XLSX files with support for multiple sheets
- Write XLSX files with multiple sheets
- Support for different data types (string, integer, float, datetime)
- Memory-efficient streaming API
- Windows 64-bit support

## Requirements

- Zig 0.14.0 or later
- **Windows 64-bit only** (currently)

## Libraries used

- [XLSX I/O version 0.2.35](https://github.com/brechtsanders/xlsxio/releases/tag/0.2.35) for both dynamic.dll and static.a libraries
- [mingw-w64-x86_64-expat 2.7.1](https://packages.msys2.org/packages/mingw-w64-x86_64-expat) for libexpat.a
- [mingw-w64-x86_64-minizip 1.3.1](https://packages.msys2.org/packages/mingw-w64-x86_64-minizip) for libminizip.a
- [mingw-w64-x86_64-zlib 1.3.1](https://packages.msys2.org/packages/mingw-w64-x86_64-zlib) for libz.a
- [mingw-w64-x86_64-bzip2 1.0.8](https://packages.msys2.org/packages/mingw-w64-x86_64-bzip2) for libbz2.a

## Installation

### Using Zig Package Manager

```bash
# Add to your project
zig fetch --save git+https://github.com/0x546F6D/zig-xlsxio
```

### build.zig using helper functions

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const xlsxio_dep = b.dependency("xlsxio", .{
        .target = target,
        .optimize = optimize,
        // use only the read library
        .read_only = true,
        // link xlsxio statically
        .link_static = true,
    });

    exe.root_module.addImport("xlsxio", xlsxio_dep.module("xlsxio"));
    // Copy xlsxio dlls to bin directory
    @import("xlsxio").copyXlsxioDlls(b, xlsxio_dep);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    // Add xlsxio dlls directory to run command
    @import("xlsxio").addRunPath(b, xlsxio_dep, run_cmd);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

## Usage

### Reading Excel Files

```zig
const std = @import("std");
const xlsxio = @import("xlsxio");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Open Excel file
    var reader = try xlsxio.Reader.init(allocator, "data.xlsx");
    defer reader.deinit();
    
    // Open a sheet (use null for first sheet)
    var sheet = try xlsxio.Reader.Sheet.init(&reader, "Sheet1");
    defer sheet.deinit();
    
    // Iterate through rows
    while (sheet.nextRow()) {
        // Read cells
        const text = try sheet.nextCellString();
        if (text) |t| {
            std.debug.print("Text: {s}\n", .{t});
            allocator.free(t); // Don't forget to free the string!
        }
        
        const number = try sheet.nextCellInt();
        if (number) |n| {
            std.debug.print("Number: {d}\n", .{n});
        }
        
        const float_val = try sheet.nextCellFloat();
        if (float_val) |f| {
            std.debug.print("Float: {d}\n", .{f});
        }
        
        const date = try sheet.nextCellDatetime();
        if (date) |d| {
            std.debug.print("Date (timestamp): {d}\n", .{d.secs});
        }
    }
}
```

### Writing Excel Files

```zig
const std = @import("std");
const xlsxio = @import("xlsxio");

pub fn main() !void {
    // Create a new Excel file
    var writer = try xlsxio.Writer.init("output.xlsx", "Sheet1");
    defer writer.deinit();
    
    // Add column headers
    writer.addCellString("Name");
    writer.addCellString("Age");
    writer.addCellString("Score");
    writer.addCellString("Date");
    writer.nextRow();
    
    // Add data
    writer.addCellString("Alice");
    writer.addCellInt(28);
    writer.addCellFloat(95.5);
    writer.addCellDatetime(xlsxio.Timestamp{ .secs = 1716691200 }); // Unix timestamp
    writer.nextRow();
    
    // Add another sheet
    writer.addSheet("Sheet2");
    
    // Add data to the new sheet
    writer.addCellString("Data on Sheet 2");
    writer.nextRow();
}
```

## API Reference

### Reader

- `Reader.init(allocator, filename)` - Open an Excel file for reading
- `Reader.deinit()` - Close the Excel file
- `Reader.Sheet.init(reader, sheet_name)` - Open a specific sheet (pass null for first sheet)
- `Reader.Sheet.deinit()` - Close the sheet
- `Reader.Sheet.nextRow()` - Move to the next row (returns true if successful)
- `Reader.Sheet.nextCell()` - Get the next cell's content as a raw string
- `Reader.Sheet.nextCellString()` - Get the next cell's content as a string
- `Reader.Sheet.nextCellInt()` - Get the next cell's content as an integer
- `Reader.Sheet.nextCellFloat()` - Get the next cell's content as a float
- `Reader.Sheet.nextCellDatetime()` - Get the next cell's content as a timestamp

### Writer

- `Writer.init(filename, sheet_name)` - Create a new Excel file for writing
- `Writer.deinit()` - Close the Excel file and save changes
- `Writer.addSheet(name)` - Add a new sheet
- `Writer.addCellString(value)` - Add a string cell
- `Writer.addCellInt(value)` - Add an integer cell
- `Writer.addCellFloat(value)` - Add a float cell
- `Writer.addCellDatetime(value)` - Add a datetime cell
- `Writer.nextRow()` - Move to the next row

## Known Limitations

- Currently only supports Windows 64-bit
- Returned strings must be freed manually

## License

This project is licensed under the MIT License - see the LICENSE file for details.

