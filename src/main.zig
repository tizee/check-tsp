const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const path = std.fs.path;
const ArrayList = std.ArrayList;
const heap = std.heap;
const page_allocator = heap.page_allocator;
const Reader = std.io.Reader;

const process = std.process;
const testing = std.testing;
const BUF_SIZE = 8 * (1 << 10);

var stdout: std.io.BufferedWriter(BUF_SIZE, std.fs.File.Writer) = undefined;
var a: std.mem.Allocator = undefined;
const TITLE_FORMAT = "\x1b[0;31m{s}\x1b[0;0m\n";
const LINE_FORMAT = "\x1b[1;32m{}\x1b[0m\n";

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
    stdout = .{ .unbuffered_writer = std.io.getStdOut().writer() };
    const stdout_stream = stdout.writer();

    const stat = try file.stat();
    switch (stat.kind) {
        .File => {
            try checkFile(file_path);
        },
        .Directory => {
            try checkDir(file_path);
        },
        else => {
            try stdout_stream.writeAll("Unsupported file types\n");
            try stdout.flush();
        },
    }
}

// path could be a relative path and should be a path to a directory
// Note that this behavior is determined by the cwd().OpenDir
fn checkDir(dir_path: []const u8) anyerror!void {
    var cwd = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer cwd.close();

    var cwd_iter = cwd.iterate();
    var file_path_buf: [1024]u8 = undefined;
    while (try cwd_iter.next()) |entry| {
        const file_path = try cwd.realpath(entry.name, &file_path_buf);
        switch (entry.kind) {
            .File => {
                try checkFile(file_path);
            },
            .Directory => {
                try checkDir(file_path);
            },
            else => {
                continue;
            },
        }
    }
}

// check whether it contains trailing spaces
fn checkFile(file_path: []const u8) !void {
    var file = try fs.openFileAbsolute(file_path, .{});
    var lines = ArrayList(u32).init(a);

    const stdout_stream = stdout.writer();
    const reader = file.reader();
    // reverse order release lines -> release file
    defer file.close();
    defer lines.deinit();

    try getLinesOfTrailingSpaces(&reader, &lines);
    if (lines.items.len > 0) {
        try stdout_stream.print(TITLE_FORMAT, .{file_path});
        for (lines.items) |line| {
            try stdout_stream.print(LINE_FORMAT, .{line});
        }
        try stdout_stream.writeAll("\n");
    }
    try stdout.flush();
}

// return the line numbers of which lines contain the trailing spaces
fn getLinesOfTrailingSpaces(reader: anytype, lines: *ArrayList(u32)) anyerror!void {
    var line_number: u32 = 1;
    var pre_byte: u8 = '\n';

    while (true) {
        const byte = reader.readByte() catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        if (byte == '\n') {
            if (pre_byte == ' ') {
                try lines.append(line_number);
            }
            line_number += 1;
        }
        pre_byte = byte;
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
