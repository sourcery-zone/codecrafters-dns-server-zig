const std = @import("std");
const testing = std.testing;

/// Convert "sourcery.zone." or "sourcery.zone" to wire labels.
/// Exactly one heap alloc at the end; OOM-safe.
pub fn name_as_label(name_in: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var buf: [256]u8 = undefined;
    var w: usize = 0;

    // allow trailing dot to mean absolute root
    const s: []const u8 = if (name_in.len > 0 and name_in[name_in.len - 1] == '.') name_in[0 .. name_in.len - 1] else name_in;
    if (s.len == 0) {
        buf[0] = 0;
        return try alloc.dupe(u8, buf[0..1]);
    }

    var it = std.mem.splitScalar(u8, s, '.');
    while (it.next()) |part| {
        if (part.len == 0) return error.EmptyLabel;
        if (part.len > 63) return error.LabelTooLong;
        if (w + 1 + part.len + 1 > buf.len) return error.NameTooLong; // +1 root

        buf[w] = @as(u8, @intCast(part.len));
        w += 1;
        @memcpy(buf[w .. w + part.len], part);
        w += part.len;
    }

    // root terminator
    if (w + 1 > buf.len) return error.NameTooLong;
    buf[w] = 0;
    w += 1;

    return try alloc.dupe(u8, buf[0..w]); // single allocation point
}

test "name_as_label encodes DNS labels (no trailing dot)" {
    const expected = "\x08sourcery\x04zone\x00";

    const allocator = testing.allocator;
    const actual = try name_as_label("sourcery.zone", allocator);
    defer allocator.free(actual);

    try testing.expectEqualStrings(expected, actual);
}

test "name_as_label adds root terminator when name ends with dot" {
    const expected = "\x08sourcery\x04zone\x00";

    const allocator = testing.allocator;
    const actual = try name_as_label("sourcery.zone.", allocator);
    defer allocator.free(actual);

    try testing.expectEqualSlices(u8, expected, actual);
}

pub fn parseLabel(buf: []u8, offset: usize, allocator: std.mem.Allocator) !struct {
    name: []u8,
    offset: usize,
    label_start: usize,
} {
    // var name: std.ArrayList(u8) = .empty;
    // errdefer name.deinit(allocator);
    var out: [256]u8 = undefined;
    var w: usize = 0;

    if (offset >= buf.len) return error.OutOfBounds;

    var current = offset;
    var jumped = false;
    var final_offset = offset;
    var label_start: usize = std.math.maxInt(usize);

    // Safety guard against malformed pointer
    var hop_count: u32 = 0;
    const max_hops: u32 = 128;

    while (true) {
        if (current >= buf.len) break;

        const len_or_ptr = buf[current];

        // Root label terminator
        if (len_or_ptr == 0) {
            if (!jumped) {
                // consume the 0 byte only when were walking the in-place name
                final_offset = current + 1;
            }
            break;
        }

        if ((len_or_ptr & 0xC0) == 0xC0) {
            if (current + 1 >= buf.len) return error.TruncatedPointer;

            // 14-bit pointer: top two bits 11, remaining 6 bits of
            // first byte are high bits
            const ptr: usize = (@as(usize, len_or_ptr & 0x3F) << 8) | @as(usize, buf[current + 1]);

            if (!jumped) {
                jumped = true;
                final_offset = current + 2;
            }

            if (ptr >= buf.len) return error.PointerOutOfBounds;

            current = ptr;

            hop_count += 1;
            if (hop_count > max_hops) return error.PointerLoop;

            continue;
        }

        // Regular Label
        const lab_len: usize = len_or_ptr;
        const lab_start = current + 1;
        const lab_end = lab_start + lab_len;
        if (lab_end > buf.len) return error.TruncatedLabel;

        if (label_start == std.math.maxInt(usize)) {
            label_start = current; // record the first length byte of
            // the resolved name
        }

        // if (out.len != 0) try name.append(allocator, '.');
        // try name.appendSlice(allocator, buf[lab_start..lab_end]);
        @memcpy(out[w .. w + lab_len], buf[lab_start..lab_end]);
        w += lab_len;
        out[w] = '.';
        w += 1;

        current = lab_end;

        if (!jumped) {
            // When not jumping, we advance final_offset along with current
            final_offset = current;
        }
    }

    // If the name began with a pointer, we never set label_start above.
    if (label_start == std.math.maxInt(usize)) {
        // Resolve the first non-pointer target once to set it
        var tmp_cur = offset;
        var guard: u32 = 0;
        while (tmp_cur < buf.len and ((buf[tmp_cur] & 0xC0) == 0xC0)) {
            if (tmp_cur + 1 >= buf.len) break;
            const ptr: usize = (@as(usize, buf[tmp_cur] & 0x3F) << 8) | @as(usize, buf[tmp_cur + 1]);
            tmp_cur = ptr;
            guard += 1;
            if (guard > max_hops) break;
        }
        if (tmp_cur < buf.len) label_start = tmp_cur;
    }

    const name_slice = if (w > 0) out[0 .. w - 1] else out[0..0];
    const owned = try allocator.dupe(u8, name_slice);
    return .{
        .name = owned,
        .offset = final_offset,
        .label_start = label_start,
    };
}

fn mkHeader() [12]u8 {
    return .{
        0x00, 0x01, // ID
        0x01, 0x00, // flags
        0x00, 0x01, // QDCOUNT = 1
        0x00, 0x00, // ANCOUNT
        0x00, 0x00, // NSCOUNT
        0x00, 0x00, // ARCOUNT
    };
}

test "parseLabel: plain QNAME from full message at offset 12" {
    var msg: [64]u8 = undefined;
    var offset: usize = 0;

    const header: [12]u8 = mkHeader();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset;
    @memcpy(msg[offset .. offset + qname.len], qname);
    offset += qname.len;

    const allocator = testing.allocator;
    const actual = try parseLabel(msg[0..offset], qname_start, allocator);
    defer allocator.free(actual.name);

    try testing.expectEqualStrings("www.example.com", actual.name);
    try testing.expectEqual(qname_start + qname.len, actual.offset); // consumed trailing 0
    try testing.expectEqual(qname_start, actual.label_start);
}

test "parseLabel: compressed NAME points back to 0x000C" {
    var msg: [96]u8 = undefined;
    var offset: usize = 0;

    var header = mkHeader();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset; // 12
    @memcpy(msg[offset .. offset + qname.len], qname);
    offset += qname.len;

    // Some test bytes before the answer NAME
    const pad_len: usize = 5;
    @memset(msg[offset .. offset + pad_len], 0xAA);
    offset += pad_len;

    const name_at = offset;
    msg[offset] = 0xC0;
    msg[offset + 1] = 0x0C;
    offset += 2;

    const allocator = testing.allocator;
    const actual = try parseLabel(msg[0..offset], name_at, allocator);
    defer allocator.free(actual.name);

    try testing.expectEqualStrings("www.example.com", actual.name);
    try testing.expectEqual(name_at + 2, actual.offset); // jumped: caller continues after pointer
    try testing.expectEqual(qname_start, actual.label_start);
}

test "parseLabel: chained pointers resolve and keep final_offset at first jump site" {
    var msg: [128]u8 = undefined;
    var offset: usize = 0;

    const header = mkHeader();
    @memcpy(msg[offset .. offset + header.len], &header);
    offset += header.len;

    const qname = "\x03www\x07example\x03com\x00";
    const qname_start = offset;
    @memcpy(msg[offset .. offset + qname.len], qname);
    offset += qname.len;

    // Place an intermediate pointer A -> 0x000C
    const ptrA_at = offset;
    msg[offset] = 0xC0;
    msg[offset + 1] = 0x0C; // A
    offset += 2;

    // Now the name under test B -> A
    const ptrB_at = offset;
    // Pointer to ptrA_at; encode as 14-bit offset
    const high: u8 = 0xC0 | @as(u8, @intCast((ptrA_at >> 8) & 0x3F));
    const low: u8 = @as(u8, @intCast(ptrA_at & 0xFF));
    msg[offset] = high;
    msg[offset + 1] = low;
    offset += 2;

    const allocator = testing.allocator;
    const actual = try parseLabel(msg[0..offset], ptrB_at, allocator);
    defer allocator.free(actual.name);

    try testing.expectEqualStrings("www.example.com", actual.name);
    try testing.expectEqual(ptrB_at + 2, actual.offset);
    try testing.expectEqual(qname_start, actual.label_start);
}

test "compile all decls" {
    std.testing.refAllDecls(@This());
}
