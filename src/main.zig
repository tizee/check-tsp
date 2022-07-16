const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const path = std.fs.path;
const ArrayList = std.ArrayList;
const heap = std.heap;
const page_allocator = heap.page_allocator;
const File = fs.File;
const Reader = std.io.Reader;
const stdout = std.io.getStdOut().writer();
const process = std.process;
const testing = std.testing;

var a: std.mem.Allocator = undefined;
pub fn main() anyerror!void {
    var arena = heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    a = arena.allocator();
    var arg_iter = process.args();

    _ = arg_iter.skip();

    const dir_arg = try (arg_iter.next(a) orelse {
        debug.print("expect the first argument to be path to a directory/file\n", .{});
        return error.InvalidArgs;
    });
    const file_path = try path.resolve(a, &[_][]const u8{dir_arg});
    const file = fs.openFileAbsolute(file_path, .{}) catch |err| {
        debug.print("file or directory does not exist!", .{});
        return err;
    };
    const stat = try file.stat();
    switch (stat.kind) {
        .File => {
            try checkFile(file_path);
        },
        .Directory => {
            try checkDir(file_path);
        },
        else => {
            try stdout.print("Unsupported file types\n", .{});
        },
    }
}

// path could be a relative path and should be a path to a directory
// Note that this behavior is determined by the cwd().OpenDir
fn checkDir(dir_path: []const u8) anyerror!void {
    var cwd = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer cwd.close();

    var cwd_iter = cwd.iterate();
    while (try cwd_iter.next()) |entry| {
        var file_path_buf: [1024]u8 = undefined;
        const file_path = try cwd.realpath(entry.name, &file_path_buf);
        switch (entry.kind) {
            .File => {
                try checkFile(file_path);
                try stdout.print("\n", .{});
            },
            .Directory => {
                try checkDir(file_path);
            },
            else => {},
        }
    }
}

// check whether it contains trailing spaces
// TODO spawn threads for each file
fn checkFile(file_path: []const u8) !void {
    var file = try fs.openFileAbsolute(file_path, .{});
    var lines = ArrayList(u32).init(a);
    const reader = file.reader();
    // reverse order release lines -> release file
    defer file.close();
    defer lines.deinit();

    try getLinesOfTrailingSpaces(&reader, &lines);
    if (lines.items.len > 0) {
        try stdout.print("\x1b[0;31m{s}\x1b[0;0m\n", .{file_path});
        for (lines.items) |line| {
            try stdout.print("\x1b[1;32m{}\x1b[0m\n", .{line});
        }
    }
}

// return the line numbers of which lines contain the trailing spaces
fn getLinesOfTrailingSpaces(reader: anytype, lines: *ArrayList(u32)) anyerror!void {
    var line_number: u32 = 1;
    var trailing_space: bool = false;
    while (true) {
        const byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };
        switch (byte) {
            ' ' => {
                trailing_space = true;
            },
            '\n' => {
                if (trailing_space) {
                    try lines.append(line_number);
                }
                trailing_space = false;
                line_number += 1;
            },
            else => {
                trailing_space = false;
            },
        }
    }
}

test "check trailing spaces" {
    const testing_allocator = testing.allocator;
    var fis = std.io.fixedBufferStream(" \n \n \n\n\n\n");
    var lines = ArrayList(u32).init(testing_allocator);
    defer lines.deinit();

    const reader = fis.reader();
    try getLinesOfTrailingSpaces(&reader, &lines);
    try testing.expect(lines.items.len == 3);
}

test "no trailing spaces" {
    const testing_allocator = testing.allocator;
    var fis = std.io.fixedBufferStream("\n\n\n");
    var lines = ArrayList(u32).init(testing_allocator);
    defer lines.deinit();

    const reader = fis.reader();
    try getLinesOfTrailingSpaces(&reader, &lines);
    try testing.expect(lines.items.len == 0);
}
