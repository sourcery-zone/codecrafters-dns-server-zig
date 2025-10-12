const std = @import("std");
const net = std.net;
const Arguments = @This();

server: net.Address,

pub fn parse() !@This() {
    var args = std.process.args();

    _ = args.next(); // the executable name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--resolver")) {
            if (args.next()) |addr| {
                if (std.mem.lastIndexOf(u8, addr, ":")) |colon| {
                    var ip: [4]u8 = undefined;
                    var parts = std.mem.splitAny(u8, addr[0..colon], ".");
                    for (&ip) |*p| {
                        p.* = try std.fmt.parseInt(u8, parts.next().?, 10);
                    }
                    const port = try std.fmt.parseInt(u16, addr[colon + 1 ..], 10);
                    return .{ .server = net.Address.initIp4(ip, port) };
                }
            }
        }
    }

    return .{ .server = net.Address.initIp4([4]u8{ 1, 1, 1, 1 }, 53) };
}
