const std = @import("std");
const testing = std.testing;

const Hashtable = @import("hashtable.zig").Hashtable;
const wire = @import("wire.zig");

pub const StateMachine = struct {
    const Self = @This();

    ht: Hashtable,

    pub fn init(gpa: std.mem.Allocator, capacity: usize) !Self {
        return .{
            .ht = try Hashtable.init(gpa, capacity),
        };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.ht.deinit(gpa);
        self.* = undefined;
    }

    pub fn input_valid(
        operation: wire.Operation,
        input: []const u8,
    ) bool {
        return switch (operation) {
            .PUT => input.len == @sizeOf(wire.EventType.Put),
            .GET => input.len == @sizeOf(wire.EventType.Get),
            .REMOVE => input.len == @sizeOf(wire.EventType.Remove),
        };
    }

    pub fn apply(
        self: *Self,
        operation: wire.Operation,
        input: []const u8,
        output: []u8,
    ) usize {
        std.debug.assert(input_valid(operation, input));

        const required_output_size: usize = switch (operation) {
            .PUT => @sizeOf(wire.ResultType.Put),
            .GET => @sizeOf(wire.ResultType.Get),
            .REMOVE => @sizeOf(wire.ResultType.Remove),
        };

        std.debug.assert(output.len >= required_output_size);

        switch (operation) {
            .PUT => {
                var request: wire.EventType.Put = undefined;
                @memcpy(std.mem.asBytes(&request), input[0..@sizeOf(wire.EventType.Put)]);
                const result = self.ht.put(request.key, request.value);

                const response = wire.ResultType.Put{
                    .status = if (result) |_| 0 else |_| 1,
                    .reserved = @splat(0),
                };

                @memcpy(output[0..@sizeOf(@TypeOf(response))], std.mem.asBytes(&response));
                return @sizeOf(@TypeOf(response));
            },
            .GET => {
                var request: wire.EventType.Get = undefined;
                @memcpy(std.mem.asBytes(&request), input[0..@sizeOf(wire.EventType.Get)]);
                const value = self.ht.get(request.key);

                const response = wire.ResultType.Get{
                    .value = value orelse 0,
                    .status = if (value != null) 0 else 1,
                    .reserved = @splat(0),
                };

                @memcpy(output[0..@sizeOf(@TypeOf(response))], std.mem.asBytes(&response));
                return @sizeOf(@TypeOf(response));
            },
            .REMOVE => {
                var request: wire.EventType.Remove = undefined;
                @memcpy(std.mem.asBytes(&request), input[0..@sizeOf(wire.EventType.Remove)]);
                self.ht.remove(request.key);

                const response = wire.ResultType.Remove{
                    .status = 0,
                    .reserved = @splat(0),
                };

                @memcpy(output[0..@sizeOf(@TypeOf(response))], std.mem.asBytes(&response));
                return @sizeOf(@TypeOf(response));
            },
        }
    }
};

fn makeInput(comptime T: type, request: T) [@sizeOf(T)]u8 {
    var bytes: [@sizeOf(T)]u8 = undefined;
    @memcpy(&bytes, std.mem.asBytes(&request));
    return bytes;
}

fn readOutput(comptime T: type, bytes: []const u8) T {
    var result: T = undefined;
    @memcpy(std.mem.asBytes(&result), bytes[0..@sizeOf(T)]);
    return result;
}

test "input_valid accepts correctly sized requests" {
    const put = makeInput(wire.EventType.Put, .{
        .key = 42,
        .value = 100,
    });

    const get = makeInput(wire.EventType.Get, .{
        .key = 42,
    });

    const remove = makeInput(wire.EventType.Remove, .{
        .key = 42,
    });

    try testing.expect(StateMachine.input_valid(.PUT, &put));
    try testing.expect(StateMachine.input_valid(.GET, &get));
    try testing.expect(StateMachine.input_valid(.REMOVE, &remove));
}

test "input_valid rejects incorrectly sized requests" {
    const invalid = [_]u8{ 0, 0, 0 };

    try testing.expect(!StateMachine.input_valid(.PUT, &invalid));
    try testing.expect(!StateMachine.input_valid(.GET, &invalid));
    try testing.expect(!StateMachine.input_valid(.REMOVE, &invalid));
}

test "put stores a value that get can retrieve" {
    var sm = try StateMachine.init(testing.allocator, 8);
    defer sm.deinit(testing.allocator);

    const put = makeInput(wire.EventType.Put, .{
        .key = 42,
        .value = 100,
    });

    var output: [@sizeOf(wire.ResultType.Put)]u8 = undefined;

    const written = sm.apply(.PUT, &put, &output);
    try testing.expectEqual(output.len, written);

    const put_result = readOutput(wire.ResultType.Put, &output);
    try testing.expectEqual(@as(u8, 0), put_result.status);

    const get = makeInput(wire.EventType.Get, .{
        .key = 42,
    });

    var get_output: [@sizeOf(wire.ResultType.Get)]u8 = undefined;

    const get_written = sm.apply(.GET, &get, &get_output);
    try testing.expectEqual(get_output.len, get_written);

    const get_result = readOutput(wire.ResultType.Get, &get_output);
    try testing.expectEqual(@as(u64, 100), get_result.value);
    try testing.expectEqual(@as(u8, 0), get_result.status);
}

test "get returns failure for a missing key" {
    var sm = try StateMachine.init(testing.allocator, 8);
    defer sm.deinit(testing.allocator);

    const get = makeInput(wire.EventType.Get, .{
        .key = 42,
    });

    var output: [@sizeOf(wire.ResultType.Get)]u8 = undefined;

    _ = sm.apply(.GET, &get, &output);

    const result = readOutput(wire.ResultType.Get, &output);

    try testing.expectEqual(@as(u8, 1), result.status);
}

test "remove deletes a previously stored key" {
    var sm = try StateMachine.init(testing.allocator, 8);
    defer sm.deinit(testing.allocator);

    const put = makeInput(wire.EventType.Put, .{
        .key = 42,
        .value = 100,
    });

    var put_output: [@sizeOf(wire.ResultType.Put)]u8 = undefined;
    _ = sm.apply(.PUT, &put, &put_output);

    const remove = makeInput(wire.EventType.Remove, .{
        .key = 42,
    });

    var remove_output: [@sizeOf(wire.ResultType.Remove)]u8 = undefined;
    _ = sm.apply(.REMOVE, &remove, &remove_output);

    const get = makeInput(wire.EventType.Get, .{
        .key = 42,
    });

    var get_output: [@sizeOf(wire.ResultType.Get)]u8 = undefined;
    _ = sm.apply(.GET, &get, &get_output);

    const result = readOutput(wire.ResultType.Get, &get_output);

    try testing.expectEqual(@as(u8, 1), result.status);
}

test "put updates an existing value" {
    var sm = try StateMachine.init(testing.allocator, 8);
    defer sm.deinit(testing.allocator);

    var output: [@sizeOf(wire.ResultType.Put)]u8 = undefined;

    const first = makeInput(wire.EventType.Put, .{
        .key = 42,
        .value = 100,
    });

    _ = sm.apply(.PUT, &first, &output);

    const second = makeInput(wire.EventType.Put, .{
        .key = 42,
        .value = 200,
    });

    _ = sm.apply(.PUT, &second, &output);

    const get = makeInput(wire.EventType.Get, .{
        .key = 42,
    });

    var get_output: [@sizeOf(wire.ResultType.Get)]u8 = undefined;
    _ = sm.apply(.GET, &get, &get_output);

    const result = readOutput(wire.ResultType.Get, &get_output);

    try testing.expectEqual(@as(u64, 200), result.value);
}
