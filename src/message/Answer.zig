const std = @import("std");
const testing = std.testing;
const Label = @import("./Label.zig");
const Answer = @This();

name: []const u8,
type_: u16,
label_start: usize,
class: u16,
ttl: u32,
data: []const u8,

pub fn parse(
    buf: []u8,
    start_offset: usize,
    allocator: std.mem.Allocator,
) ![]Answer {
    var offset = start_offset;
    var list: std.ArrayList(Answer) = .empty;
    errdefer {
        for (list.items) |*a| a.deinit(allocator);
        list.deinit(allocator);
    }

    // Parse NAME — own its memory only inside this scope until we append
    {
        // 1) Parse NAME (owns .name already)
        const parsed_label = try Label.parseLabel(buf, start_offset, allocator);
        errdefer allocator.free(parsed_label.name);
        offset = parsed_label.offset;

        // 2) Ensure RR header (TYPE, CLASS, TTL, TDLEN) is present
        if (offset + 10 > buf.len) return error.TruncatedRRHeader;

        const atype = std.mem.readInt(u16, buf[offset..][0..2], .big);
        offset += 2;
        const aclass = std.mem.readInt(u16, buf[offset..][0..2], .big);
        offset += 2;
        const ttl = std.mem.readInt(u32, buf[offset..][0..4], .big);
        offset += 4;
        const rdlen = std.mem.readInt(u16, buf[offset..][0..2], .big);
        offset += 2;

        const rdlen_usize: usize = @intCast(rdlen);
        if (offset + rdlen_usize > buf.len) return error.TruncatedRdata;

        // 3) Make an OWNED copy of RDATA (so it outlives the source buffer)
        const data_copy: []u8 = try allocator.alloc(u8, rdlen);
        errdefer allocator.free(data_copy);
        @memcpy(data_copy, buf[offset .. offset + rdlen_usize]);

        const answer = Answer{
            .name = parsed_label.name,
            .type_ = atype,
            .class = aclass,
            .ttl = ttl,
            .data = data_copy,
            .label_start = parsed_label.label_start,
        };

        // 5) Return a slice of one (can extend to many later)
        try list.append(allocator, answer);
    }

    return list.toOwnedSlice(allocator);
}

pub fn deinit(self: *const Answer, allocator: std.mem.Allocator) void {
    if (self.name.len > 0) allocator.free(self.name);
    if (self.name.len > 0) allocator.free(self.data);
}

pub fn toBytes(self: Answer, allocator: std.mem.Allocator) ![]u8 {
    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);

    // Add compressed label to response
    const hi: u8 = 0xc0 | @as(u8, @intCast((self.label_start >> 8) & 0x3f));
    const lo: u8 = @intCast(self.label_start & 0xff);
    try response.appendSlice(allocator, &[2]u8{ hi, lo });

    try response.append(allocator, @intCast(self.type_ >> 8));
    try response.append(allocator, @intCast(self.type_ & 0xff));
    try response.append(allocator, @intCast(self.class >> 8));
    try response.append(allocator, @intCast(self.class & 0xff));
    try response.append(allocator, @intCast((self.ttl >> 24) & 0xff));
    try response.append(allocator, @intCast((self.ttl >> 16) & 0xff));
    try response.append(allocator, @intCast((self.ttl >> 8) & 0xff));
    try response.append(allocator, @intCast(self.ttl & 0xff));
    try response.append(allocator, @intCast((self.data.len >> 8) & 0xff));
    try response.append(allocator, @intCast(self.data.len & 0xff));
    try response.appendSlice(allocator, self.data);

    return response.toOwnedSlice(allocator);
}

pub fn answer_length(self: Answer) usize {
    return 12 + self.data.len;
}

// TODO DRY
fn mkHeader1Question() [12]u8 {
    // ID=0x0001, flags=0x0100, QDCOUNT=1, ANCOUNT=1 (set ANCOUNT=1 to be realistic)
    return .{
        0x00, 0x01,
        0x01, 0x00,
        0x00, 0x01, // QDCOUNT = 1
        0x00, 0x01, // ANCOUNT = 1
        0x00, 0x00,
        0x00, 0x00,
    };
}

test "Answer.parse: compressed A answer pointing to QNAME at 0x000C" {
    var msg: [256]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader1Question();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    // Question: www.example.com, type A, class IN
    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset;
    @memcpy(msg[offset .. offset + qname.len], qname);
    offset += qname.len;

    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 }); // QTYPE A
    offset += 2;

    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 }); // QCLASS IN
    offset += 2;

    // Answer: NAME -> 0x000C, TYPE=A, CLASS=IN, TTL=60, TDLEN=4, RDATA=1.2.3.4
    const ans_start = offset;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0xC0, 0x0C }); // compression pointer to offset 12
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 }); // TYPE A
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 }); // QCLASS IN
    offset += 2;
    @memcpy(msg[offset .. offset + 4], &[4]u8{ 0x00, 0x00, 0x00, 0x3C }); // TTL 60
    offset += 4;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x04 }); // RDLENGT
    offset += 2;
    const rdata = [_]u8{ 1, 2, 3, 4 };
    @memcpy(msg[offset .. offset + rdata.len], &rdata);
    offset += rdata.len;

    const allocator = testing.allocator;
    const answers = try Answer.parse(msg[0..offset], ans_start, allocator);
    defer {
        for (answers) |a| {
            allocator.free(a.name);
            allocator.free(a.data);
        }
        allocator.free(answers);
    }

    try testing.expectEqual(@as(usize, 1), answers.len);
    const answer = answers[0];

    try testing.expectEqualStrings("www.example.com", answer.name);
    try testing.expectEqual(@as(u16, 1), answer.type_);
    try testing.expectEqual(@as(u16, 1), answer.class);
    try testing.expectEqual(@as(u32, 60), answer.ttl);
    try testing.expectEqualSlices(u8, &rdata, answer.data);

    // The label_start for emitting a pointer should be 12 (start of
    // QNAME) If this assertion fails and shows 24, you are
    // double-adding the header size.
    try testing.expectEqual(@as(usize, qname_start), answer.label_start);
}

test "Answer.toBytes: reproduces original bytes including 0xC0 0x0C pointer" {
    var msg: [256]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader1Question();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset;
    @memcpy(msg[offset .. offset + qname.len], qname);
    offset += qname.len;
    @memcpy(msg[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[_]u8{ 0x00, 0x01 });
    offset += 2;

    const ans_start = offset;
    const original_ans = "\xC0\x0C\x00\x01\x00\x01\x00\x00\x00\x3C\x00\x04\x01\x02\x03\x04";
    @memcpy(msg[offset .. offset + original_ans.len], original_ans);
    offset += original_ans.len;

    const alloc = testing.allocator;
    const answers = try Answer.parse(msg[0..offset], ans_start, alloc);
    defer {
        for (answers) |a| {
            alloc.free(a.name);
            alloc.free(a.data);
        }
        alloc.free(answers);
    }
    const answer = answers[0];

    const out = try answer.toBytes(alloc);
    defer alloc.free(out);

    // Expect exact match to the original answer bytes
    try testing.expectEqualSlices(u8, original_ans, out);

    // And sanity check: pointer bytes are 0xC0 0x0C
    try testing.expect(out.len >= 2);
    try testing.expectEqual(@as(u8, 0xC0), out[0]);
    try testing.expectEqual(@as(u8, 0x0C), out[1]);

    // Guard against accidental drift if qname_start changes
    const expected_hi: u8 = 0xC0 | @as(u8, @intCast((qname_start >> 8) & 0x3F));
    const expected_lo: u8 = @as(u8, @intCast(qname_start & 0xFF));
    try testing.expectEqual(expected_hi, out[0]);
    try testing.expectEqual(expected_lo, out[1]);
}

test "Answer.answer_length: equals 12 header bytes of RR + RDATA" {
    // Construct an Answer struct directly
    const answer = Answer{
        .name = "www.example.com",
        .type_ = 1,
        .class = 1,
        .ttl = 300,
        .data = &[_]u8{ 93, 184, 216, 34 }, // 93.184.216.34
        .label_start = 12, // typical pointer to the first question
    };

    try testing.expectEqual(@as(usize, 12 + answer.data.len), answer.answer_length());
}
