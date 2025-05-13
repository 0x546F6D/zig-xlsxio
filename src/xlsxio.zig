const std = @import("std");

const c = @import("xlsxio_c");

pub const SKIP_NONE: c_uint = c.XLSXIOREAD_SKIP_NONE;
pub const SKIP_EMPTY_ROWS: c_uint = c.XLSXIOREAD_SKIP_EMPTY_ROWS;
pub const SKIP_EMPTY_CELLS: c_uint = c.XLSXIOREAD_SKIP_EMPTY_CELLS;
pub const SKIP_ALL_EMPTY: c_uint = c.XLSXIOREAD_SKIP_ALL_EMPTY;
pub const SKIP_EXTRA_CELLS: c_uint = c.XLSXIOREAD_SKIP_EXTRA_CELLS;
pub const SKIP_HIDDEN_ROWS: c_uint = c.XLSXIOREAD_SKIP_HIDDEN_ROWS;

// Custom timestamp type that matches the C library's time_t
pub const Timestamp = struct {
    secs: i64,
};

pub const XlsxioError = error{
    FileNotFound,
    InvalidFile,
    ReadError,
    WriteError,
    SheetNotFound,
    CellNotFound,
    OutOfMemory,
    SheetListNotOpened,
};

pub const Reader = struct {
    handle: ?*?*c.struct_xlsxio_read_struct,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, filename: [:0]const u8) !Reader {
        const handle = c.xlsxioread_open(filename.ptr) orelse return XlsxioError.FileNotFound;
        return Reader{
            .handle = @as(?*?*c.struct_xlsxio_read_struct, @ptrCast(@alignCast(handle))),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Reader) void {
        c.xlsxioread_close(@as(c.xlsxioreader, @ptrCast(@alignCast(self.handle))));
    }

    pub fn isSheet(self: Reader, sheet_name: [:0]const u8) !bool {
        var sheetlist = try self.getSheetList();
        defer sheetlist.deinit();
        while (try sheetlist.next()) |name| {
            defer self.allocator.free(name);
            if (std.mem.eql(u8, sheet_name, name)) return true;
        }
        return false;
    }

    pub fn getSheetList(reader: Reader) !SheetList {
        const handle = c.xlsxioread_sheetlist_open(@as(c.xlsxioreader, @ptrCast(@alignCast(reader.handle)))) orelse return XlsxioError.SheetListNotOpened;
        return SheetList{
            .handle = @as(?*?*c.struct_xlsxio_read_sheetlist_struct, @ptrCast(@alignCast(handle))),
            .allocator = reader.allocator,
        };
    }

    pub const SheetList = struct {
        handle: ?*?*c.struct_xlsxio_read_sheetlist_struct,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *SheetList) void {
            c.xlsxioread_sheetlist_close(@as(c.xlsxioreadersheetlist, @ptrCast(@alignCast(self.handle))));
        }

        pub fn next(self: *SheetList) !?[:0]u8 {
            const value = c.xlsxioread_sheetlist_next(@as(c.xlsxioreadersheetlist, @ptrCast(@alignCast(self.handle)))) orelse return null;
            return try std.mem.Allocator.dupeZ(self.allocator, u8, std.mem.span(value));
        }
    };

    pub fn getSheet(reader: Reader, sheet_name: ?[:0]const u8, flags: c_uint) !Sheet {
        const name_ptr = if (sheet_name) |name| name.ptr else null;
        const handle = c.xlsxioread_sheet_open(@as(c.xlsxioreader, @ptrCast(@alignCast(reader.handle))), name_ptr, flags) orelse return XlsxioError.SheetNotFound;
        return Sheet{
            .handle = @as(?*?*c.struct_xlsxio_read_sheet_struct, @ptrCast(@alignCast(handle))),
            .allocator = reader.allocator,
        };
    }

    pub const Sheet = struct {
        handle: ?*?*c.struct_xlsxio_read_sheet_struct,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Sheet) void {
            c.xlsxioread_sheet_close(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))));
        }

        pub fn lastRow(self: *Sheet) usize {
            return c.xlsxioread_sheet_last_row_index(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))));
        }

        pub fn lastColumn(self: *Sheet) usize {
            return c.xlsxioread_sheet_last_column_index(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))));
        }

        pub fn nextRow(self: *Sheet) bool {
            return c.xlsxioread_sheet_next_row(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle)))) != 0;
        }

        pub fn nextCell(self: *Sheet) !?[]const u8 {
            const value = c.xlsxioread_sheet_next_cell(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle)))) orelse return null;
            defer c.xlsxioread_free(value);

            const len = std.mem.len(value);
            const result = try self.allocator.alloc(u8, len);
            @memcpy(result, value[0..len]);
            return result;
        }

        pub fn nextCellInt(self: *Sheet) !?i64 {
            var value: i64 = 0;
            const success = c.xlsxioread_sheet_next_cell_int(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return value;
        }

        pub fn nextCellFloat(self: *Sheet) !?f64 {
            var value: f64 = 0;
            const success = c.xlsxioread_sheet_next_cell_float(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return value;
        }

        pub fn nextCellString(self: *Sheet) !?[:0]const u8 {
            var value: ?[*]u8 = null;
            const success = c.xlsxioread_sheet_next_cell_string(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            if (value == null) {
                return null;
            }

            defer c.xlsxioread_free(value.?);

            // Manually count string length
            var len: usize = 0;
            while (value.?[len] != 0) : (len += 1) {}

            // Allocate with sentinel
            const result = try self.allocator.allocSentinel(u8, len, 0);
            @memcpy(result, value.?[0..len]);
            return result;
        }

        pub fn nextCellDatetime(self: *Sheet) !?Timestamp {
            var value: i64 = 0;
            const success = c.xlsxioread_sheet_next_cell_datetime(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return Timestamp{ .secs = value };
        }
    };
};

pub const Writer = struct {
    handle: ?*?*c.struct_xlsxio_write_struct,

    pub fn init(filename: [:0]const u8, sheet_name: [:0]const u8) !Writer {
        const handle = c.xlsxiowrite_open(filename.ptr, sheet_name.ptr) orelse return XlsxioError.WriteError;
        return Writer{
            .handle = @as(?*?*c.struct_xlsxio_write_struct, @ptrCast(@alignCast(handle))),
        };
    }

    pub fn deinit(self: *Writer) void {
        _ = c.xlsxiowrite_close(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))));
    }

    pub fn addSheet(self: *Writer, name: [:0]const u8) void {
        c.xlsxiowrite_add_sheet(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), name.ptr);
    }

    pub fn addCellString(self: *Writer, value: [:0]const u8) void {
        c.xlsxiowrite_add_cell_string(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value.ptr);
    }

    pub fn addCellInt(self: *Writer, value: i64) void {
        c.xlsxiowrite_add_cell_int(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value);
    }

    pub fn addCellFloat(self: *Writer, value: f64) void {
        c.xlsxiowrite_add_cell_float(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value);
    }

    pub fn addCellDatetime(self: *Writer, value: Timestamp) void {
        c.xlsxiowrite_add_cell_datetime(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value.secs);
    }

    pub fn nextRow(self: *Writer) void {
        c.xlsxiowrite_next_row(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))));
    }
};

test "basic xlsx read/write" {
    std.log.info("Starting test\n", .{});

    const allocator = std.testing.allocator;
    const test_file = "test.xlsx";
    const test_sheet = "Sheet1";

    std.log.info("Creating test file\n", .{});

    // Write test
    {
        var writer = try Writer.init(test_file, test_sheet);
        defer writer.deinit();

        writer.addCellString("Hello");
        writer.addCellInt(42);
        writer.addCellFloat(3.14);
        writer.addCellDatetime(Timestamp{ .secs = 1737094027 });
        writer.nextRow();
    }

    std.log.info("Test file created\n", .{});

    // Check if file exists
    {
        std.fs.cwd().access(test_file, .{}) catch |err| {
            std.log.err("Error accessing file: {}\n", .{err});
            return err;
        };
    }

    std.log.info("Reading test file\n", .{});

    // Read test
    {
        var reader = try Reader.init(allocator, test_file);
        defer reader.deinit();

        var sheet = try Reader.Sheet.init(&reader, test_sheet);
        defer sheet.deinit();

        try std.testing.expect(sheet.nextRow());

        const cell1 = try sheet.nextCellString();
        try std.testing.expectEqualStrings("Hello", cell1.?);
        allocator.free(cell1.?);

        const cell2 = try sheet.nextCellInt();
        try std.testing.expectEqual(42, cell2.?);

        const cell3 = try sheet.nextCellFloat();
        try std.testing.expectEqual(3.14, cell3.?);

        const cell4 = try sheet.nextCellDatetime();
        try std.testing.expectEqual(@as(i64, 1737094027), cell4.?.secs);
    }

    std.log.info("Test file read\n", .{});

    // Clean up test file
    std.fs.cwd().deleteFile(test_file) catch {};
}
