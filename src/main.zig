const std = @import("std");
const bencode = @import("bencode.zig");

pub fn main() !void {
    const input = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "debian-12.9.0-amd64-netinst.iso.torrent", 4000000);
    defer std.heap.page_allocator.free(input);

    const parsed = try bencode.parse(std.heap.page_allocator, input);
    defer parsed.deinit();

    std.log.info("parsed: {any}", .{parsed.value});
}
