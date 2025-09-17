const std = @import("std");
const Header = @This();
const testing = std.testing;

id: u16,
qr: u1,
opcode: u4,
aa: u1,
tc: u1,
rd: u1,
ra: u1,
z: u3,
rcode: u4,
qdcount: u16,
ancount: u16,
nscount: u16,
arcount: u16,

pub fn fromList(input: struct { u16, u1, u4, u1, u1, u1, u1, u3, u4, u16, u16, u16, u16 }) Header {
    return Header{
        .id = input.@"0",
        .qr = input.@"1",
        .opcode = input.@"2",
        .aa = input.@"3",
        .tc = input.@"4",
        .rd = input.@"5",
        .ra = input.@"6",
        .z = input.@"7",
        .rcode = input.@"8",
        .qdcount = input.@"9",
        .ancount = input.@"10",
        .nscount = input.@"11",
        .arcount = input.@"12",
    };
}

pub fn toBytes(self: Header) [12]u8 {
    var result: [12]u8 = undefined;

    std.mem.writeInt(u16, result[0..2], self.id, .big);

    result[2] =
        (@as(u8, self.qr) << 7) |
        (@as(u8, self.opcode) << 3) |
        (@as(u8, self.aa) << 2) |
        (@as(u8, self.tc) << 1) |
        (@as(u8, self.rd));

    result[3] =
        (@as(u8, self.ra) << 7) |
        (@as(u8, self.z) << 4) |
        (@as(u8, self.rcode));

    std.mem.writeInt(u16, result[4..6], self.qdcount, .big);
    std.mem.writeInt(u16, result[6..8], self.ancount, .big);
    std.mem.writeInt(u16, result[8..10], self.nscount, .big);
    std.mem.writeInt(u16, result[10..12], self.arcount, .big);

    return result;
}

test "Header.toBytes sets id and qr" {
    const header = Header.fromList(.{ 1234, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    const expected = [12]u8{ 0x4, 0xd2, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    try testing.expectEqual(expected, header.toBytes());
}
