const std = @import("std");

// Builds a minimal DNS query for "abc.example.com" type A (id=0x1e7c)
pub fn minimalQuery(alloc: std.mem.Allocator) ![]u8 {
    const query: [33]u8 = .{
        0x1e, 0x7c, // ID
        0x01, 0x00, // flags: recursion desired
        0x00, 0x01, // QDCOUNT = 1
        0x00, 0x00, // ANCOUNT
        0x00, 0x00, // NSCOUNT
        0x00, 0x00, // ARCOUNT
        0x03, 'a',
        'b',  'c',
        0x07, 'e',
        'x',  'a',
        'm',  'p',
        'l',  'e',
        0x03, 'c',
        'o',  'm',
        0x00, // root
        0x00, 0x01, // QTYPE = A
        0x00, 0x01, // QCLASS = IN
    };
    const out = try alloc.alloc(u8, query.len);
    @memcpy(out, query[0..]);
    return out;
}

// Builds a minimal DNS response for the same question, one A record answer.
// Answer IP provided as parameter.
pub fn aRecordResponse(a: [4]u8, alloc: std.mem.Allocator) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);

    // Header
    try buf.appendSlice(alloc, &[_]u8{
        0x1e, 0x7c, // ID
        0x81, 0x80, // flags: qr=1, rd=1, ra=1, no error
        0x00, 0x01, // QDCOUNT=1
        0x00, 0x01, // ANCOUNT=1
        0x00, 0x00, // NSCOUNT
        0x00, 0x00, // ARCOUNT
    });

    // Question section
    try buf.appendSlice(alloc, &[_]u8{
        0x03, 'a', 'b', 'c',
        0x07, 'e', 'x', 'a',
        'm',  'p', 'l', 'e',
        0x03, 'c', 'o', 'm',
        0x00, // root
        0x00, 0x01, // QTYPE = A
        0x00, 0x01, // QCLASS = IN
    });

    // Answer section
    try buf.appendSlice(alloc, &[_]u8{
        0xc0, 0x0c, // Name: pointer to offset 12 (start of qname)
        0x00, 0x01, // TYPE = A
        0x00, 0x01, // CLASS = IN
        0x00, 0x00, 0x00, 0x3c, // TTL = 60
        0x00, 0x04, // RDLENGTH = 4
        a[0], a[1], a[2], a[3], // RDATA = provided IP
    });

    return buf.toOwnedSlice(alloc);
}
