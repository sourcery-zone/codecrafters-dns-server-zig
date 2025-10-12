const std = @import("std");
const testing = std.testing;
const Label = @import("Label.zig");

const Question = @This();

name: []u8,
label: []u8,
label_start: usize,
qtype: u16,
qclass: u16,
raw: []u8,
len: usize,

pub fn parse(
    buf: []u8,
    count: usize,
    allocator: std.mem.Allocator,
) !struct { questions: []Question, final_offset: usize } {
    var list: std.ArrayList(Question) = .empty;

    errdefer {
        for (list.items) |*q| deinit(q, allocator);
        list.deinit(allocator);
    }

    var i: usize = 0;
    var offset: usize = 12; // to skip the header
    var final_offset: usize = 0;

    while (i < count) : (i += 1) {
        const first_offset = offset;
        const parsed_label = try Label.parseLabel(buf, first_offset, allocator);
        // if we fail later in this iteration *before* moving
        // ownership into the list, make sure parsed_label.name is
        // freed.
        errdefer allocator.free(parsed_label.name);
        offset = parsed_label.offset;

        // Bounds guards for qtype/qclass
        if (offset + 4 > buf.len) return error.TruncatedSection;
        const qtype = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
        offset += 2;
        const qclass = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
        offset += 2;

        // Convert presentation name -> wire labels we own
        const owned_label: []u8 = try Label.name_as_label(parsed_label.name, allocator);
        errdefer allocator.free(owned_label);

        const question = Question{
            .name = parsed_label.name,
            .label = owned_label,
            .label_start = first_offset,
            .qtype = qtype,
            .qclass = qclass,
            .raw = buf[first_offset..offset],
            .len = parsed_label.name.len + 4,
        };
        // Once append succeeds, ownership lives in list.items[last];
        // the errdefers above will not run unless an error occurs
        // before this point.
        try list.append(allocator, question);

        final_offset = offset;
    }

    return .{
        .questions = try list.toOwnedSlice(allocator),
        .final_offset = final_offset,
    };
}

pub fn deinit(self: *Question, allocator: std.mem.Allocator) void {
    if (self.label.len != 0) allocator.free(self.label);
    if (self.label.len != 0) allocator.free(self.name);
}

pub fn toBytes(self: Question, allocator: std.mem.Allocator) ![]u8 {
    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);

    try response.appendSlice(allocator, self.label);

    var qtype_buf: [2]u8 = undefined;
    var qclass_buf: [2]u8 = undefined;

    std.mem.writeInt(u16, &qtype_buf, self.qtype, .big);
    std.mem.writeInt(u16, &qclass_buf, self.qclass, .big);

    try response.appendSlice(allocator, &qtype_buf);
    try response.appendSlice(allocator, &qclass_buf);

    return response.toOwnedSlice(allocator);
}

// TODO DRY
fn mkHeader() [12]u8 {
    // ID=0x0001, flags=0x0100, QDCOUNT=1, others 0
    return .{
        0x00, 0x01,
        0x01, 0x00,
        0x00, 0x01,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
    };
}

test "Question.parse: parses single question and tracks offsets" {
    var msg: [128]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    // QNAME = sourcery.zone
    const qname = "\x08sourcery\x04zone\x00";
    const qname_start = offset;
    @memcpy(msg[qname_start .. qname_start + qname.len], qname);
    offset += qname.len;

    // QTYPE=A, QCLASS=IN
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 });
    offset += 2;

    const allocator = testing.allocator;
    const parsed = try Question.parse(msg[0..offset], 1, allocator);
    defer {
        for (parsed.questions) |question| {
            allocator.free(question.name);
            allocator.free(question.label);
        }
        allocator.free(parsed.questions);
    }

    try testing.expectEqual(@as(usize, 1), parsed.questions.len);
    const question = parsed.questions[0];

    try testing.expectEqualStrings("sourcery.zone", question.name);
    try testing.expectEqualSlices(u8, "\x08sourcery\x04zone\x00", question.label);
    try testing.expectEqual(@as(usize, qname_start), question.label_start);

    try testing.expectEqual(@as(u16, 1), question.qtype);
    try testing.expectEqual(@as(u16, 1), question.qclass);

    // raw must be the exact question bytes from the messae
    const expected_raw = "\x08sourcery\x04zone\x00\x00\x01\x00\x01";
    try testing.expectEqualSlices(u8, expected_raw, question.raw);

    // final_offset should point right after QCLASS
    try testing.expectEqual(@as(usize, 12 + expected_raw.len), parsed.final_offset);

    // toBytes currently emits label + QTYPE + QCLASS (no trailing 0)
    const rebuilt = try question.toBytes(allocator);
    defer allocator.free(rebuilt);

    try testing.expectEqualSlices(u8, expected_raw, rebuilt);
}

test "Question.parse: parses two questions back-to-back and advances final_offset" {
    var msg: [256]u8 = undefined;
    var offset: usize = 0;

    // Header with QDCOUNT=2
    var header = mkHeader();
    header[4] = 0x00;
    header[5] = 0x02;
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    // Q1: www.example.com A IN
    const q1name = "\x03www\x07example\x03com\x00";
    const q1_start = offset;
    @memcpy(msg[q1_start .. offset + q1name.len], q1name);
    offset += q1name.len;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 });
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 });
    offset += 2;

    // Q2: sourcery.zone AAAA IN
    const q2name = "\x08sourcery\x04zone\x00";
    const q2_start = offset;
    @memcpy(msg[q2_start .. offset + q2name.len], q2name);
    offset += q2name.len;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x1c });
    offset += 2;
    @memcpy(msg[offset .. offset + 2], &[2]u8{ 0x00, 0x01 });
    offset += 2;

    const allocator = testing.allocator;
    const parsed = try Question.parse(msg[0..offset], 2, allocator);
    defer {
        for (parsed.questions) |question| {
            allocator.free(question.name);
            allocator.free(question.label);
        }
        allocator.free(parsed.questions);
    }

    try testing.expectEqual(@as(usize, 2), parsed.questions.len);

    // Q1 checks
    {
        const q = parsed.questions[0];
        try testing.expectEqualStrings("www.example.com", q.name);
        try testing.expectEqual(@as(u16, 1), q.qtype);
        try testing.expectEqual(@as(u16, 1), q.qclass);
        try testing.expectEqual(@as(usize, q1_start), q.label_start);
        try testing.expectEqualSlices(u8, q1name[0..q1name.len], q.label);
        try testing.expectEqualSlices(u8, "\x03www\x07example\x03com\x00\x00\x01\x00\x01", q.raw);
    }

    // Q2 checks
    {
        const q = parsed.questions[1];
        try testing.expectEqualStrings("sourcery.zone", q.name);
        try testing.expectEqual(@as(u16, 0x001c), q.qtype);
        try testing.expectEqual(@as(u16, 1), q.qclass);
        try testing.expectEqual(@as(usize, q2_start), q.label_start);
        try testing.expectEqualSlices(u8, "\x08sourcery\x04zone\x00", q.label);
        try testing.expectEqualSlices(u8, "\x08sourcery\x04zone\x00\x00\x1c\x00\x01", q.raw);
    }

    // final_offset = end of Q2
    try testing.expectEqual(@as(usize, offset), parsed.final_offset);

    // Round-trip the bytes for Q2
    const rebuilt = try parsed.questions[1].toBytes(allocator);
    defer allocator.free(rebuilt);
    try testing.expectEqualSlices(u8, "\x08sourcery\x04zone\x00\x00\x1c\x00\x01", rebuilt);
}
