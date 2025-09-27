const std = @import("std");

const Question = @This();

name: []u8,
qtype: u16,
qclass: u16,
raw: []u8,

pub fn parse(buf: []u8) struct { question: Question, next: usize } {
    var offset: usize = 0;

    while (offset < buf.len and buf[offset] != 0) {
        const label_length = buf[offset];
        offset += 1 + label_length;
    }

    const name = buf[0..offset];
    offset += 1;
    const qtype = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
    offset += 2;
    const qclass = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
    offset += 2;

    return .{
        .question = Question{
            .name = name,
            .qtype = qtype,
            .qclass = qclass,
            .raw = buf[0..offset],
        },
        .next = offset,
    };
}
