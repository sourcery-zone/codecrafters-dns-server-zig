const std = @import("std");
const net = std.net;
const posix = std.posix;
const Header = @import("message/Header.zig");
const Answer = @import("message/Answer.zig");
const Question = @import("message/Question.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        // if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
        // std.testing.expect(status != .leak) catch @panic("A memory leak!");
        if (status == .leak) @panic("A memory leak");
    }
    const allocator = gpa.allocator();

    const sock_fd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
    defer posix.close(sock_fd);

    // Since the tester restarts your program quite often, setting SO_REUSEADDR
    // ensures that we don't run into 'Address already in use' errors
    const reuse: c_int = 1;
    try posix.setsockopt(sock_fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&reuse));

    const addr = net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 2053);
    try posix.bind(sock_fd, &addr.any, addr.getOsSockLen());

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    std.debug.print("Logs from your program will appear here!\n", .{});

    var buf: [1024]u8 = undefined;
    while (true) {
        var client_addr: posix.sockaddr = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const received_bytes = try posix.recvfrom(sock_fd, &buf, 0, &client_addr, &client_addr_len);
        const qheader = Header.fromBytes(buf[0..12]);
        std.debug.print("{s}\n{x}\n", .{ buf[0..received_bytes], buf[0..received_bytes] });

        const questions = try Question.parse(
            buf[12..received_bytes],
            qheader.qdcount,
            allocator,
        );

        const header = Header{
            .id = qheader.id,
            .qr = 1,
            .opcode = qheader.opcode,
            .aa = 0,
            .tc = 0,
            .rd = qheader.rd,
            .ra = 1,
            .z = 0,
            .rcode = if (qheader.opcode == 0) 0 else 4,
            .qdcount = qheader.qdcount,
            .ancount = qheader.qdcount, // Number of answers
            .nscount = 0,
            .arcount = 0,
        };

        var answers: std.ArrayList(Answer) = .empty;
        defer answers.deinit(allocator);

        var question_length: usize = 0;
        var answer_length: usize = 0;
        for (questions) |q| {
            const answer = Answer{
                .name = q.label,
                .label_start = q.label_start,
                .type_ = q.qtype,
                .class = q.qclass,
                .ttl = 60,
                .length = 4, // NOTE should it be hard coded?
                .data = "\x08\x08\x08\x08",
            };

            try answers.append(allocator, answer);
            // TODO feat: answer.len
            // 2 bytes for compressed name, 10 for details, and the rest data type
            answer_length += answer.answer_length();
            question_length += q.raw.len;
        }

        var response = try allocator.alloc(u8, 12 + question_length + answer_length);
        defer allocator.free(response);

        var offset: usize = 0;
        // add `header` to `response`
        @memcpy(response[offset..12], &header.toBytes());
        offset += 12;

        // add `question` to `response`
        // TODO refactor variable names
        for (questions) |q| {
            const question = q.raw;
            @memcpy(
                response[offset .. offset + question.len],
                question,
            );
            offset += question.len;
        }

        // add `answer` to `response`
        for (answers.items) |answer| {
            const answer_bytes = try answer.toBytes(allocator);
            defer allocator.free(answer_bytes);
            @memcpy(
                response[offset .. offset + answer_bytes.len],
                answer_bytes,
            );
            offset += answer_bytes.len;
        }

        _ = try posix.sendto(sock_fd, response, 0, &client_addr, client_addr_len);
    }
}
