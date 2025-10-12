const std = @import("std");
const net = std.net;
const posix = std.posix;
const Arguments = @import("Arguments.zig");
const Message = @import("Message.zig");
const DnsClient = @import("DnsClient.zig");

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

    const arguments = try Arguments.parse();

    var udp = DnsClient.UdpTransport{ .timeout_ms = 1500 };
    var client = DnsClient.Client.init(DnsClient.asTransport(&udp));

    var buf: [1024]u8 = undefined;
    while (true) {
        var client_addr: posix.sockaddr = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const received_bytes = try posix.recvfrom(sock_fd, &buf, 0, &client_addr, &client_addr_len);

        const request = try Message.parse(buf[0..received_bytes], received_bytes, allocator);
        defer request.deinit(allocator);

        const header = Message.Header{
            .id = request.header.id,
            .qr = 1,
            .opcode = request.header.opcode,
            .aa = 0,
            .tc = 0,
            .rd = request.header.rd,
            .ra = 1,
            .z = 0,
            .rcode = if (request.header.opcode == 0) 0 else 4,
            .qdcount = request.header.qdcount,
            .ancount = request.header.qdcount, // Number of answers
            .nscount = 0,
            .arcount = 0,
        };

        var answers: std.ArrayList(Message.Answer) = .empty;
        defer answers.deinit(allocator);

        var question_length: usize = 0;
        var answer_length: usize = 0;

        // std.debug.print("-> {x}\n", .{buf[0..received_bytes]});
        for (request.questions) |q| {
            var qbuf: [512]u8 = undefined;
            const qwire = try makeQuestion(qbuf[0..], request, q);
            const response = try client.query(
                qwire,
                arguments.server,
                allocator,
            );
            defer response.deinit(allocator);

            const dump = try response.toBytes(allocator);
            defer allocator.free(dump);
            // std.debug.print("-> internal:{x}\n", .{dump});

            // NEW: derive rcode from upstream; default to NOERROR
            // const upstream_rcode: u4 = response.header.rcode;

            //const res_answers = response.answers orelse @panic("upstream had no answers");
            if (response.answers) |arr| {
                const src = arr[0].data;
                const rdata = try allocator.alloc(u8, src.len);
                errdefer allocator.free(rdata);
                @memcpy(rdata, src);

                // std.debug.print("++ {s} - {x}\n", .{ q.label, rdata });
                const ans = Message.Answer{
                    .name = q.label,
                    .label_start = q.label_start,
                    .type_ = q.qtype,
                    .class = q.qclass,
                    .ttl = 60,
                    .data = rdata,
                };

                try answers.append(allocator, ans);
                answer_length += ans.answer_length();
            }

            // OWN the RDATA
            question_length += q.raw.len;
        }

        const answers_list = try answers.toOwnedSlice(allocator);
        defer allocator.free(answers_list);

        const msg = Message{ .header = header, .questions = request.questions, .answers = answers_list };
        const response_bytes = try msg.toBytes(allocator);
        defer allocator.free(response_bytes);

        _ = try posix.sendto(
            sock_fd,
            response_bytes,
            0,
            &client_addr,
            client_addr_len,
        );

        for (msg.answers.?) |*ans| {
            allocator.free(ans.data);
            //            ans.deinit(allocator);
        }
    }
}

fn makeQuestion(out: []u8, request: Message, question: Message.Question) ![]u8 {
    var w: usize = 0;
    // header: reuse i, rd, qdcount=1
    if (w + 2 > out.len) return error.BufferTooSmall;
    std.mem.writeInt(u16, out[w..][0..2], request.header.id, .big);
    w += 2;

    // FLAGS: QR=0, RD from request, rest 0
    const flags: u16 = if (request.header.rd == 1) 0x0100 else 0x0000;
    if (w + 2 > out.len) return error.BufferTooSmall;
    std.mem.writeInt(u16, out[w..][0..2], flags, .big);
    w += 2;

    // QDCOUNT=1, AN/NS/AR=0
    if (w + 8 > out.len) return error.BufferTooSmall;
    std.mem.writeInt(u16, out[w..][0..2], 1, .big); // QDCOUNT=1
    w += 2;
    std.mem.writeInt(u16, out[w..][0..2], 0, .big); // ANCOUNT
    w += 2;
    std.mem.writeInt(u16, out[w..][0..2], 0, .big); // NSCOUNT
    w += 2;
    std.mem.writeInt(u16, out[w..][0..2], 0, .big); // ARCOUNT
    w += 2;

    // question section: use q.label (wire labels, ends with 0)
    if (w + question.label.len > out.len) return error.BufferTooSmall;
    @memcpy(out[w .. w + question.label.len], question.label);
    w += question.label.len;

    if (w + 4 > out.len) return error.BufferTooSmall;
    std.mem.writeInt(u16, out[w..][0..2], question.qtype, .big);
    w += 2;
    std.mem.writeInt(u16, out[w..][0..2], question.qclass, .big);
    w += 2;

    return out[0..w];
}
