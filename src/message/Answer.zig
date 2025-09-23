const std = @import("std");
const testing = std.testing;

const Answer = @This();

name: []const u8,
type_: u16,
class: u16,
ttl: u32,
length: u16,
data: []const u8,

pub fn toBytes(self: Answer, allocator: std.mem.Allocator) ![]u8 {
    var response = try allocator.alloc(u8, 12 + self.data.len);

    var offset: usize = 2;
    @memcpy(response[0..offset], &[2]u8{ 0xc0, 0x0c });

    std.mem.writeInt(u16, response[offset..][0..2], self.type_, .big);
    offset += 2;

    std.mem.writeInt(u16, response[offset..][0..2], self.class, .big);
    offset += 2;

    std.mem.writeInt(u32, response[offset..][0..4], self.ttl, .big);
    offset += 4;

    std.mem.writeInt(u16, response[offset..][0..2], self.length, .big);
    offset += 2;

    @memcpy(response[offset .. offset + self.data.len], self.data);

    return response;
}

test "toBytes" {
    const response = Answer{
        .name = "sourcery.zone",
        .type_ = 1,
        .class = 1,
        .ttl = 60,
        .length = 4,
        .data = "8.8.8.8",
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var offset: usize = 0;
    const response_bytes = try response.toBytes(allocator);
    try testing.expectEqualSlices(
        u8,
        &[2]u8{ 0xC0, 0x0C },
        response_bytes[0..2],
    );
    offset += 2;

    const expectBigInt = struct {
        fn f(t: type, expected: anytype, actual: anytype) !void {
            const type_ = std.mem.readInt(t, actual, .big);
            try testing.expectEqual(expected, type_);
        }
    }.f;

    try expectBigInt(u16, response.type_, response_bytes[offset .. offset + 2][0..2]);
    offset += 2;
    try expectBigInt(u16, response.class, response_bytes[offset .. offset + 2][0..2]);
    offset += 2;
    try expectBigInt(u32, response.ttl, response_bytes[offset .. offset + 4][0..4]);
    offset += 4;

    try expectBigInt(u16, response.length, response_bytes[offset .. offset + 2][0..2]);
    offset += 2;
    try testing.expectEqualSlices(
        u8,
        response.data,
        response_bytes[offset .. offset + response.data.len],
    );
}
