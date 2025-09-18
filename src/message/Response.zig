const std = @import("std");
const testing = std.testing;

const Response = @This();

name: []const u8,
type_: u16,
class: u16,
ttl: u32,
length: u16,
data: []const u8,

pub fn toBytes(self: Response) [512]u8 {
    var response: [512]u8 = undefined;

    // TODO consider checking up until the null byte
    var offset = self.name.len;
    @memcpy(response[0..offset], self.name[0..offset]);

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
    const name_str = "sourcery.zone";
    var name_buffer: [name_str.len]u8 = undefined;
    @memcpy(&name_buffer, name_str);

    const response = Response{
        .name = name_str,
        .type_ = 1,
        .class = 1,
        .ttl = 60,
        .length = 4,
        .data = "8.8.8.8",
    };

    // const expected = [_]u8{ "sourcery.zone", 1, 1, 60, 4, "\x08\x08\x08\x08" };
    // try testing.expectEqual(expected, response.toBytes());
    // std.debug.print("{any}", .{response.toBytes()});

    const response_bytes = response.toBytes();
    try testing.expectEqualSlices(u8, name_str, response_bytes[0..name_str.len]);
}
