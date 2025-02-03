const std = @import("std");
const bencode = @import("bencode.zig");

const InnerTestStruct = struct {
    hello: []u8,
};

const TestStruct = struct {
    abc: []u8,
    inner: InnerTestStruct,
};

pub fn main() !void {
    // const input = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "debian-12.9.0-amd64-netinst.iso.torrent", 4000000);
    // defer std.heap.page_allocator.free(input);
    //
    // const parsed = try bencode.parse(std.heap.page_allocator, input);
    // defer parsed.deinit();
    //
    // std.log.info("parsed: {any}", .{parsed.value});
    // const input = "10:abcdefghij";
    // const input = "10:abcdefghiji10555135e";
    const input = "d3:abc3:def5:innerd5:hello5:worldee";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var scanner = bencode.Scanner{
        .input = input,
        .allocator = arena.allocator(),
    };

    const val = try bencode.innerParse(TestStruct, arena.allocator(), &scanner);

    std.log.info("val: {any}", .{val});
    std.log.info("val: {s}", .{val.abc});
    std.log.info("inner: {any}", .{val.inner});
    std.log.info("inner: {s}", .{val.inner.hello});
}
