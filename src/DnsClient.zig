const std = @import("std");
const net = std.net;
const posix = std.posix;
const testing = std.testing;
const Message = @import("Message.zig");
const DnsClient = @This();

pub const Transport = struct {
    sendRecv: *const fn (ctx: *anyopaque, buf: []const u8, addr: net.Address, allocator: std.mem.Allocator) anyerror![]u8,
    ctx: *anyopaque,
};

pub const Client = struct {
    transport: Transport,

    pub fn init(transport: Transport) Client {
        return .{ .transport = transport };
    }

    pub fn query(self: *Client, buf: []const u8, addr: net.Address, allocator: std.mem.Allocator) !Message {
        const bytes = try self.transport.sendRecv(self.transport.ctx, buf, addr, allocator);
        defer allocator.free(bytes);

        if (bytes.len < 12) return error.ShortResponse; // header is 12 bytes
        // std.debug.print("-> external: {x}\n", .{bytes});
        // bytes is owned by us; Message.parse allocates its own structures
        return Message.parse(bytes, bytes.len, allocator);
    }
};

// Default UDP transport used in production
pub const UdpTransport = struct {
    timeout_ms: u32 = 2000,

    pub fn sendRecv(
        ctx: *anyopaque,
        buf: []const u8,
        addr: net.Address,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const self: *UdpTransport = @ptrCast(@alignCast(ctx));
        const fd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        defer posix.close(fd);

        // Optional: set recv timeout
        var tv = posix.timeval{
            .sec = @intCast(self.timeout_ms / 1000),
            .usec = @intCast((self.timeout_ms % 1000) * 1000),
        };
        try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&tv));

        _ = try posix.sendto(fd, buf, 0, &addr.any, addr.getOsSockLen());

        var response: [1500]u8 = undefined;
        const n = try posix.recvfrom(fd, &response, 0, null, null);

        // Return a copy owned by caller
        var out = try allocator.alloc(u8, n);
        @memcpy(out[0..n], response[0..n]);
        return out;
    }
};

// Helper to build a Transport from a UdpTransport that you own by value
pub fn asTransport(t: *UdpTransport) Transport {
    return .{ .sendRecv = UdpTransport.sendRecv, .ctx = t };
}

fn cannedARecordResponse(a: [4]u8, allocator: std.mem.Allocator) ![]u8 {
    return try @import("fixture.zig").aRecordResponse(a, allocator);
}

fn FakeOk_sendRecv(
    ctx: *anyopaque,
    buf: []const u8,
    addr: net.Address,
    allocator: std.mem.Allocator,
) ![]u8 {
    _ = ctx;
    _ = buf;
    _ = addr;
    return try cannedARecordResponse(.{ 1, 2, 3, 4 }, allocator);
}

fn FakeTimeout_sendRecv(
    ctx: *anyopaque,
    buf: []const u8,
    addr: net.Address,
    allocator: std.mem.Allocator,
) ![]u8 {
    _ = ctx;
    _ = buf;
    _ = addr;
    _ = allocator;
    return error.TimeOut;
}

fn FakeBadBytes_sendRecv(
    ctx: *anyopaque,
    buf: []const u8,
    addr: net.Address,
    alloc: std.mem.Allocator,
) ![]u8 {
    _ = ctx;
    _ = buf;
    _ = addr;
    var junk = try alloc.alloc(u8, 8);
    // Deliberately invalid DNS bytes
    junk[0..8].* = .{ 0, 0, 0xff, 0xff, 0, 0, 0, 0 };
    return junk;
}

test "DnsClient.query happy path; no leaks" {
    var a = testing.allocator;

    var fake_ctx: u8 = 0;
    const t = DnsClient.Transport{ .sendRecv = FakeOk_sendRecv, .ctx = &fake_ctx };
    var c = DnsClient.Client.init(t);

    // Minimal valid query bytes; use a fixture from your tests
    const q = try @import("fixture.zig").minimalQuery(a);
    defer a.free(q);

    const addr = net.Address.initIp4(.{ 127, 0, 0, 1 }, 2053);

    var msg = try c.query(q, addr, a);
    defer msg.deinit(a);

    try testing.expect(msg.answers != null);
    const ans = msg.answers.?[0];
    try testing.expectEqual(@as(u16, 1), ans.type_); // A
    try testing.expectEqualSlices(u8, ans.data, &.{ 1, 2, 3, 4 });
}

test "DnsClient.query propagate upstream timeout" {
    var a = testing.allocator;
    var fake_ctx: u8 = 0;
    const t = DnsClient.Transport{ .sendRecv = FakeTimeout_sendRecv, .ctx = &fake_ctx };
    var c = DnsClient.Client.init(t);

    const q = try @import("fixture.zig").minimalQuery(a);
    defer a.free(q);
    const addr = net.Address.initIp4(.{ 8, 8, 8, 8 }, 53);

    try testing.expectError(error.TimeOut, c.query(q, addr, a));
}

test "DnsClient.query rejects malformed bytes" {
    var a = testing.allocator;
    var fake_ctx: u8 = 0;
    const t = DnsClient.Transport{ .sendRecv = FakeBadBytes_sendRecv, .ctx = &fake_ctx };
    var c = DnsClient.Client.init(t);

    const q = try @import("fixture.zig").minimalQuery(a);
    defer a.free(q);
    const addr = net.Address.initIp4(.{ 1, 1, 1, 1 }, 53);

    try std.testing.expectError(error.ShortResponse, c.query(q, addr, a));
}

test "DnsClient.query OOM safe" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(alloc: std.mem.Allocator) !void {
            var fake_ctx: u8 = 0;
            const t = DnsClient.Transport{ .sendRecv = FakeOk_sendRecv, .ctx = &fake_ctx };

            var c = DnsClient.Client.init(t);
            const q = try @import("fixture.zig").minimalQuery(alloc);
            defer alloc.free(q);

            const addr = net.Address.initIp4(.{ 9, 9, 9, 9 }, 53);
            var msg = try c.query(q, addr, alloc);
            defer msg.deinit(alloc);
        }
    }.run, .{});
}
