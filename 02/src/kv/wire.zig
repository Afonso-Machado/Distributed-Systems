const std = @import("std");
const testing = std.testing;

pub const Operation = enum(u8) { GET, PUT, REMOVE };

pub const EventType = struct {
    pub const Get = extern struct {
        key: u64,
    };

    pub const Put = extern struct {
        key: u64,
        value: u64,
    };

    pub const Remove = extern struct { key: u64 };
};

pub const ResultType = struct {
    pub const Put = extern struct {
        status: u8,
        reserved: [7]u8 = @splat(0),
    };

    pub const Get = extern struct {
        value: u64,
        status: u8,
        reserved: [7]u8 = @splat(0),
    };

    pub const Remove = extern struct {
        status: u8,
        reserved: [7]u8 = @splat(0),
    };
};

test "wire body sizes" {
    try testing.expectEqual(16, @sizeOf(EventType.Put));
    try testing.expectEqual(8, @sizeOf(EventType.Get));
    try testing.expectEqual(8, @sizeOf(EventType.Remove));

    try testing.expectEqual(8, @sizeOf(ResultType.Put));
    try testing.expectEqual(16, @sizeOf(ResultType.Get));
    try testing.expectEqual(8, @sizeOf(ResultType.Remove));
}
