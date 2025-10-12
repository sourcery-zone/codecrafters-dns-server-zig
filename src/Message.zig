const std = @import("std");
const testing = std.testing;
pub const Header = @import("message/Header.zig");
pub const Answer = @import("message/Answer.zig");
pub const Question = @import("message/Question.zig");

const Message = @This();

header: Header,
questions: []Question,
answers: ?[]Answer,

pub fn parse(buf: []u8, message_length: usize, allocator: std.mem.Allocator) !Message {
    if (buf.len < 12) return error.ShortResponse;
    const header = Header.fromBytes(buf[0..12]);
    const parsed_questions = try Question.parse(
        buf[0..message_length],
        header.qdcount,
        allocator,
    );
    const questions = parsed_questions.questions;
    errdefer {
        // if we error later, release questions
        for (questions) |*q| q.deinit(allocator);
        allocator.free(questions);
    }

    const answer_start = parsed_questions.final_offset;

    var response = Message{
        .header = header,
        .questions = questions,
        .answers = null,
    };

    if (answer_start < message_length) {
        response.answers = try Answer.parse(
            buf[0..message_length],
            answer_start,
            allocator,
        );
    }
    return response;
}

pub fn toBytes(
    self: Message,
    allocator: std.mem.Allocator,
) ![]u8 {
    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);

    try response.appendSlice(allocator, self.header.toBytes()[0..]);

    for (self.questions) |q| {
        const question = try q.toBytes(allocator);
        defer allocator.free(question);
        try response.appendSlice(allocator, question);
    }

    if (self.answers) |answers| {
        for (answers) |answer| {
            const answer_bytes = try answer.toBytes(allocator);
            defer allocator.free(answer_bytes);
            try response.appendSlice(allocator, answer_bytes);
        }
    }

    return response.toOwnedSlice(allocator);
}

fn mkHeader(q: u16, a: u16) [12]u8 {
    // ID=0x0001, flags=0x0100, QDCOUNT=q, ANCOUNT=a, NS/AR=0
    return .{
        0x00,                      0x01,
        0x01,                      0x00,
        @as(u8, @intCast(q >> 8)), @as(u8, @intCast(q & 0xff)),
        @as(u8, @intCast(a >> 8)), @as(u8, @intCast(a & 0xff)),
        0x00,                      0x00,
        0x00,                      0x00,
    };
}

test "Message.parse: one question, no answers" {
    var buf: [128]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader(1, 0);
    @memcpy(buf[offset .. offset + header.len], &header);
    offset += header.len;

    // QNAME: sourcery.zone
    const qname = "\x08sourcery\x04zone\x00";
    const qname_start = offset; // 12
    @memcpy(buf[offset .. offset + qname.len], qname);
    offset += qname.len;

    // QTYPE=A, QCLASS=IN
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;

    const alloc = testing.allocator;
    const msg = try Message.parse(buf[0..offset], offset, alloc);
    defer {
        for (msg.questions) |q| {
            alloc.free(q.name);
            alloc.free(q.label);
        }
        alloc.free(msg.questions);
        if (msg.answers) |ans| {
            for (ans) |a| {
                alloc.free(a.name);
                alloc.free(a.data);
            }
            alloc.free(ans);
        }
    }

    // Header sanity
    try testing.expectEqual(@as(u16, 1), msg.header.qdcount);
    try testing.expectEqual(@as(u16, 0), msg.header.ancount);

    // Questions parsed
    try testing.expectEqual(@as(usize, 1), msg.questions.len);
    const q = msg.questions[0];
    try testing.expectEqualStrings("sourcery.zone", q.name);
    try testing.expectEqual(@as(usize, qname_start), q.label_start);
    try testing.expectEqual(@as(u16, 1), q.qtype);
    try testing.expectEqual(@as(u16, 1), q.qclass);

    // No answers
    try testing.expect(msg.answers == null);
}

test "Message.parse: one question and one compressed A answer" {
    var buf: [256]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader(1, 1);
    @memcpy(buf[offset .. offset + header.len], &header);
    offset += header.len;

    // QNAME: www.example.com
    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset; // 12
    @memcpy(buf[offset .. offset + qname.len], qname);
    offset += qname.len;
    // QTYPE=A, QCLASS=IN
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;

    // ANSWER: NAME=0xC0 0x0C (ptr to 12), TYPE=A, CLASS=IN, TTL=60, RDLEN=4, RDATA=1.2.3.4
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0xC0, 0x0C }); // was 00 0C
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 }); // TYPE A
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 }); // CLASS IN
    offset += 2;
    @memcpy(buf[offset .. offset + 4], &[_]u8{ 0x00, 0x00, 0x00, 0x3C }); // TTL 60
    offset += 4;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x04 }); // was 00 01
    offset += 2;
    const rdata = [_]u8{ 1, 2, 3, 4 };
    @memcpy(buf[offset .. offset + rdata.len], &rdata);
    offset += rdata.len;

    const alloc = testing.allocator;
    const msg = try Message.parse(buf[0..offset], offset, alloc);
    defer {
        for (msg.questions) |q| {
            alloc.free(q.name);
            alloc.free(q.label);
        }
        alloc.free(msg.questions);
        if (msg.answers) |ans| {
            for (ans) |a| {
                alloc.free(a.name);
                alloc.free(a.data);
            }
            alloc.free(ans);
        }
    }

    // Header
    try testing.expectEqual(@as(u16, 1), msg.header.qdcount);
    try testing.expectEqual(@as(u16, 1), msg.header.ancount);

    // Question parsed
    try testing.expectEqual(@as(usize, 1), msg.questions.len);
    try testing.expectEqualStrings("www.example.com", msg.questions[0].name);

    // Answer parsed
    try testing.expect(msg.answers != null);
    const answers = msg.answers.?;
    try testing.expectEqual(@as(usize, 1), answers.len);
    const answer = answers[0];

    try testing.expectEqualStrings("www.example.com", answer.name);
    try testing.expectEqual(@as(u16, 1), answer.type_);
    try testing.expectEqual(@as(u16, 1), answer.class);
    try testing.expectEqual(@as(u32, 60), answer.ttl);
    try testing.expectEqualSlices(u8, &rdata, answer.data);

    // Compression pointer should reference start of QNAME at 12
    try testing.expectEqual(@as(usize, qname_start), answer.label_start);
}

test "Message.toBytes: concatenates header + each question + each answer" {
    var buf: [256]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader(1, 1);
    @memcpy(buf[offset .. offset + header.len], &header);
    offset += header.len;

    // Q: sourcery.zone, A IN
    const qname = "\x08sourcery\x04zone\x00";
    const qname_start = offset;
    @memcpy(buf[offset .. offset + qname.len], qname);
    offset += qname.len;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;

    // ANSWER: pointer to 12, TTL 300, RDATA 93.184.216.34 (example.org)
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0xC0, 0x0C });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 4], &[_]u8{ 0x00, 0x00, 0x01, 0x2C });
    offset += 4;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x04 });
    offset += 2;
    const rdata = [_]u8{ 93, 184, 216, 34 };
    @memcpy(buf[offset .. offset + rdata.len], &rdata);
    offset += rdata.len;

    const allocator = testing.allocator;
    const msg = try Message.parse(buf[0..offset], offset, allocator);

    // Build expected by concatenating component toBytes outputs
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(allocator);

    try expected.appendSlice(allocator, &msg.header.toBytes());
    for (msg.questions) |q| {
        const qb = try q.toBytes(allocator);
        defer allocator.free(qb);
        try expected.appendSlice(allocator, qb);
    }
    if (msg.answers) |ans| {
        for (ans) |a| {
            const ab = try a.toBytes(allocator);
            defer allocator.free(ab);
            try expected.appendSlice(allocator, ab);
        }
    }

    const out = try msg.toBytes(allocator);
    defer allocator.free(out);

    try testing.expectEqualSlices(u8, expected.items, out);

    // Sanity: answer pointer bytes equal pointer to qname_start
    if (msg.answers) |ans| {
        const a = ans[0];
        const hi: u8 = 0xC0 | @as(u8, @intCast((qname_start >> 8) & 0x3F));
        const lo: u8 = @as(u8, @intCast(qname_start & 0xFF));
        const rebuilt = try a.toBytes(allocator);
        defer allocator.free(rebuilt);
        try testing.expectEqual(hi, rebuilt[0]);
        try testing.expectEqual(lo, rebuilt[1]);
    }

    // Cleanup allocations from Message.parse
    defer {
        for (msg.questions) |q| {
            allocator.free(q.name);
            allocator.free(q.label);
        }
        allocator.free(msg.questions);
        if (msg.answers) |ans| {
            for (ans) |a| {
                allocator.free(a.name);
                allocator.free(a.data);
            }
            allocator.free(ans);
        }
    }
}

test "Message: parsed bytes independent of source buffer" {
    var buf: [256]u8 = undefined;
    // ... build header+question+answer exactly as before into pkt[0..i]
    var offset: usize = 0;

    const header = mkHeader(1, 1);
    @memcpy(buf[offset .. offset + header.len], &header);
    offset += header.len;

    // Q: sourcery.zone, A IN
    const qname = "\x08sourcery\x04zone\x00";
    @memcpy(buf[offset .. offset + qname.len], qname);
    offset += qname.len;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;

    // ANSWER: pointer to 12, TTL 300, RDATA 93.184.216.34 (example.org)
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0xC0, 0x0C });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(buf[offset .. offset + 4], &[_]u8{ 0x00, 0x00, 0x01, 0x2C });
    offset += 4;
    @memcpy(buf[offset .. offset + 2], &[_]u8{ 0x00, 0x04 });
    offset += 2;
    const rdata = [_]u8{ 76, 76, 21, 21 };
    @memcpy(buf[offset .. offset + rdata.len], &rdata);
    offset += rdata.len;

    const alloc = testing.allocator;
    const msg = try Message.parse(buf[0..offset], offset, alloc);
    defer msg.deinit(alloc);

    // nuke the source buffer; if msg holds slices, they’re now zeroed
    @memset(buf[0..offset], 0);

    const out = try msg.toBytes(alloc); // should still equal original if data was owned
    defer alloc.free(out);

    // expect last 4 bytes are the original RDATA (e.g., 76.76.21.21)
    try testing.expectEqualSlices(u8, "\x4c\x4c\x15\x15", out[out.len - 4 ..]);

    // free owned fields
}

pub fn deinit(self: *const Message, allocator: std.mem.Allocator) void {
    for (self.questions) |q| {
        allocator.free(q.name);
        allocator.free(q.label);
    }
    allocator.free(self.questions);
    // answers
    if (self.answers) |ans| {
        for (ans) |a| {
            allocator.free(a.name); // Label.parseLabel allocated this
            allocator.free(a.data); // <-- the new owned RDATA copy
        }
        allocator.free(ans);
    }
}

test "compressed second question parses" {
    const a = std.testing.allocator;
    var storage: [128]u8 = undefined;
    const msg = try std.fmt.hexToBytes(storage[0..], "21ae0100000200000000000003616263116c6f6e67617373646f6d61696e6e616d6503636f6d000001000103646566c01000010001");

    var res = try Message.parse(msg, msg.len, a);
    defer res.deinit(a);

    try std.testing.expectEqual(@as(u16, 2), res.header.qdcount);
    try std.testing.expectEqualStrings("abc.longassdomainname.com", res.questions[0].name);
    try std.testing.expectEqualStrings("def.longassdomainname.com", res.questions[1].name);
}
