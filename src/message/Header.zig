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

pub fn init(
    id: ?u16,
    qr: ?u1,
    opcode: ?u4,
    aa: ?u1,
    tc: ?u1,
    rd: ?u1,
    ra: ?u1,
    z: ?u3,
    rcode: ?u4,
    qdcount: ?u16,
    ancount: ?u16,
    nscount: ?u16,
    arcount: ?u16,
) Header {
    return Header{
        .id = id orelse 0,
        .qr = qr orelse 0,
        .opcode = opcode orelse 0,
        .aa = aa orelse 0,
        .tc = tc orelse 0,
        .rd = rd orelse 0,
        .ra = ra orelse 0,
        .z = z orelse 0,
        .rcode = rcode orelse 0,
        .qdcount = qdcount orelse 0,
        .ancount = ancount orelse 0,
        .nscount = nscount orelse 0,
        .arcount = arcount orelse 0,
    };
}

pub fn fromBytes(buf: []u8) Header {
    var offset: usize = 0;
    const id = std.mem.readInt(u16, buf[offset..2][0..2], .big);
    offset += 2;

    const qr: u1 = @intCast(buf[offset] >> 7);
    const opcode: u4 = @intCast((buf[offset] & 0x78) >> 3);
    const aa: u1 = @intCast((buf[offset] & 0x4) >> 2);
    const tc: u1 = @intCast((buf[offset] & 0x2) >> 1);
    const rd: u1 = @intCast(buf[offset] & 0x1);
    offset += 1;

    const ra: u1 = @intCast(buf[offset] >> 7);
    const z: u3 = @intCast((buf[offset] & 0x70) >> 4);
    const rcode: u4 = @intCast(buf[offset] & 0x0F);
    offset += 1;

    const qdcount = std.mem.readInt(
        u16,
        buf[offset .. offset + 2][0..2],
        .big,
    );
    offset += 2;
    const ancount = std.mem.readInt(
        u16,
        buf[offset .. offset + 2][0..2],
        .big,
    );
    offset += 2;
    const nscount = std.mem.readInt(
        u16,
        buf[offset .. offset + 2][0..2],
        .big,
    );
    offset += 2;
    const arcount = std.mem.readInt(
        u16,
        buf[offset .. offset + 2][0..2],
        .big,
    );
    offset += 2;

    return Header{
        .id = id,
        .qr = qr,
        .opcode = opcode,
        .aa = aa,
        .tc = tc,
        .rd = rd,
        .ra = ra,
        .z = z,
        .rcode = rcode,
        .qdcount = qdcount,
        .ancount = ancount,
        .nscount = nscount,
        .arcount = arcount,
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

test "init: sets parameters" {
    const H = Header.init(1, 1, 3, 1, 1, 1, 1, 7, 9, 10, 11, 12, 13);
    try testing.expectEqual(1, H.id);
    try testing.expectEqual(1, H.qr);
    try testing.expectEqual(3, H.opcode);
    try testing.expectEqual(1, H.aa);
    try testing.expectEqual(1, H.tc);
    try testing.expectEqual(1, H.rd);
    try testing.expectEqual(1, H.ra);
    try testing.expectEqual(7, H.z);
    try testing.expectEqual(9, H.rcode);
    try testing.expectEqual(10, H.qdcount);
    try testing.expectEqual(11, H.ancount);
    try testing.expectEqual(12, H.nscount);
    try testing.expectEqual(13, H.arcount);
}

test "init: sets default value for null parameters" {
    const H = Header.init(
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
    );
    try testing.expectEqual(0, H.id);
    try testing.expectEqual(0, H.qr);
    try testing.expectEqual(0, H.opcode);
    try testing.expectEqual(0, H.aa);
    try testing.expectEqual(0, H.tc);
    try testing.expectEqual(0, H.rd);
    try testing.expectEqual(0, H.ra);
    try testing.expectEqual(0, H.z);
    try testing.expectEqual(0, H.rcode);
    try testing.expectEqual(0, H.qdcount);
    try testing.expectEqual(0, H.ancount);
    try testing.expectEqual(0, H.nscount);
    try testing.expectEqual(0, H.arcount);
}

test "Header.toBytes sets id and qr" {
    const header = Header.init(1234, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    const expected = [12]u8{ 0x4, 0xd2, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    try testing.expectEqual(expected, header.toBytes());
}
