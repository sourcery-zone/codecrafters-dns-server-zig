const std = @import("std");
const net = std.net;
const posix = std.posix;
const Header = @import("message/Header.zig");
const Answer = @import("message/Answer.zig");

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
        const message_id = std.mem.readInt(u16, buf[0..2], .big);
        const question = buf[12..received_bytes];

        const header = Header{
            .id = message_id,
            .qr = 1,
            .opcode = 0,
            .aa = 0,
            .tc = 0,
            .rd = 1,
            .ra = 1,
            .z = 0,
            .rcode = 0,
            .qdcount = 1,
            .ancount = 1, // Number of answers
            .nscount = 0,
            .arcount = 0,
        };
        const answer = Answer{
            .name = "\x0ccodecrafters\x02io",
            .type_ = 1,
            .class = 1,
            .ttl = 60,
            .length = 4,
            .data = "\x08\x08\x08\x08",
        };

        const answer_length = 12 + answer.data.len;
        // TODO feat: answer.len
        var response = try allocator.alloc(u8, 12 + question.len + answer_length);
        defer allocator.free(response);

        var offset: usize = 0;
        @memcpy(response[offset..12], &header.toBytes());
        offset += 12;

        @memcpy(response[offset .. question.len + 12], question);
        offset += question.len;

        const answer_bytes = try answer.toBytes(allocator);
        defer allocator.free(answer_bytes);
        std.debug.print("{}:{}", .{ answer_length, answer_bytes.len });
        @memcpy(
            response[offset .. offset + answer_length],
            answer_bytes,
        );

        _ = try posix.sendto(sock_fd, response, 0, &client_addr, client_addr_len);
    }
}
