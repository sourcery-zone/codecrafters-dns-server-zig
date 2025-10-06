const std = @import("std");

const Question = @This();

name: []u8,
label: []u8,
label_start: usize,
qtype: u16,
qclass: u16,
raw: []u8,
len: usize,

fn parseLabel(buf: []u8, offset: usize, allocator: std.mem.Allocator) !struct {
    name: []u8,
    offset: usize,
} {
    var name: std.ArrayList(u8) = .empty;
    defer name.deinit(allocator);

    var current_offset = offset;
    var jumped = false;
    var final_offset = offset;

    while (current_offset < buf.len and buf[current_offset] != 0) {
        const label_size = buf[current_offset];

        if ((label_size & 0xc0) == 0xc0) {
            if (current_offset + 1 >= buf.len) {
                break;
            }

            if (!jumped) {
                jumped = true;
                final_offset = current_offset + 2;
            }

            const first_byte_adr = (@as(usize, label_size & 0x3f));
            const second_byte_adr = buf[current_offset + 1];

            // TODO refactor. This now requires the user to take care
            // of removing the first 12 bytes.
            current_offset = (first_byte_adr | second_byte_adr) - 12;

            continue;
        }

        const label_start = current_offset + 1;
        if (label_start + label_size > buf.len) {
            break;
        }

        const label = buf[label_start .. label_start + label_size];
        std.debug.print("-> {s}\n", .{label});

        if (name.items.len > 0) {
            try name.append(allocator, '.');
        }

        try name.appendSlice(allocator, label);

        current_offset = label_start + label_size;
        if (!jumped) {
            final_offset = current_offset;
        }
    }

    if (!jumped and final_offset + 1 < buf.len) {
        final_offset += 1;
    }

    return .{ .name = try name.toOwnedSlice(allocator), .offset = final_offset };
}

pub fn parse(
    buf: []u8,
    count: usize,
    allocator: std.mem.Allocator,
) ![]Question {
    var questions: std.ArrayList(Question) = .empty;
    defer questions.deinit(allocator);

    var i: usize = 0;
    var offset: usize = 0;
    while (i < count) : (i += 1) {
        const first_offset = offset;
        const parsed_label = try parseLabel(buf, first_offset, allocator);
        offset = parsed_label.offset;

        const qtype = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
        offset += 2;
        const qclass = std.mem.readInt(u16, buf[offset .. offset + 2][0..2], .big);
        offset += 2;

        const question = Question{
            .name = parsed_label.name,
            .label = try name_as_label(parsed_label.name, allocator),
            .label_start = first_offset + 12,
            .qtype = qtype,
            .qclass = qclass,
            .raw = buf[first_offset..offset],
            .len = parsed_label.name.len + 4,
        };

        try questions.append(allocator, question);
    }

    return questions.toOwnedSlice(allocator);
}

fn name_as_label(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);
    var it = std.mem.splitAny(u8, name, ".");
    while (it.next()) |value| {
        try response.append(allocator, @as(u8, @intCast(value.len)));
        try response.appendSlice(allocator, value);
    }

    return response.toOwnedSlice(allocator);
}

// pub fn toBytes(self: Question, allocator: std.mem.Allocator) ![]u8 {
//     var response = try allocator.alloc(u8, 4 + self.name.len);

//     var offset: usize = 2;
//     @memcpy(response[0..offset], &[2]u8{ 0xc0, 0x0c });

//     std.mem.writeInt(u16, response[offset..][0..2], self.type_, .big);
//     offset += 2;

//     std.mem.writeInt(u16, response[offset..][0..2], self.class, .big);
//     offset += 2;

//     std.mem.writeInt(u32, response[offset..][0..4], self.ttl, .big);
//     offset += 4;

//     std.mem.writeInt(u16, response[offset..][0..2], self.length, .big);
//     offset += 2;

//     @memcpy(response[offset .. offset + self.data.len], self.data);

//     return response;
// }
