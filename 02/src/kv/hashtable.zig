const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Hashtable = struct {
    const Self = @This();
    const Entry = struct {
        key: u64,
        val: u64,
    };

    slots: []?Entry,

    pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!Self {
        assert(std.math.isPowerOfTwo(capacity));
        const slots = try gpa.alloc(?Entry, capacity);
        @memset(slots, null);
        return .{ .slots = slots };
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        gpa.free(self.slots);
        self.* = undefined;
    }

    pub fn put(self: *Self, key: u64, val: u64) error{OutOfSpace}!void {
        // Calculate the index
        const mask = self.slots.len - 1;
        var index = key & mask;

        // Probe the slots
        var probes: usize = 0;
        while (probes < self.slots.len) : (probes += 1) {
            if (self.slots[index]) |*entry| {
                if (entry.key == key) {
                    entry.val = val;
                    return;
                }
            } else {
                self.slots[index] = .{
                    .key = key,
                    .val = val,
                };
                return;
            }

            index = (index + 1) & mask;
        }

        return error.OutOfSpace;
    }

    pub fn get(self: *Self, key: u64) ?u64 {
        // Calculate the index
        const mask = self.slots.len - 1;
        var index = key & mask;

        // Probe the slots
        var probes: usize = 0;
        while (probes < self.slots.len) : (probes += 1) {
            if (self.slots[index]) |entry| {
                if (entry.key == key) {
                    return entry.val;
                }
            } else {
                return null;
            }

            index = (index + 1) & mask;
        }

        return null;
    }

    pub fn remove(self: *Self, key: u64) void {
        // Calculate the index
        const mask: usize = self.slots.len - 1;
        var index: u64 = key & mask;

        // Find entry
        var probes: usize = 0;
        while (probes < self.slots.len) : (probes += 1) {
            if (self.slots[index]) |entry| {
                if (entry.key == key) {
                    break;
                }
            } else {
                return;
            }

            index = (index + 1) & mask;
        }

        // Delete entry

        self.slots[index] = null;

        var hole = index;
        var current = (index + 1) & mask;

        probes = 0;
        while (self.slots[current]) |entry| {
            const home: usize = entry.key & mask;

            const distance_to_hole = (hole -% home) & mask;
            const distance_to_current = (current -% home) & mask;

            if (distance_to_hole < distance_to_current) {
                self.slots[hole] = entry;
                self.slots[current] = null;

                hole = current;
            }

            current = (current + 1) & mask;
        }
    }
};

test "init" {
    const gpa = testing.allocator;
    var ht: Hashtable = try .init(gpa, 8);
    defer ht.deinit(gpa);

    try testing.expectEqual(8, ht.slots.len);
    for (ht.slots) |slot| try testing.expectEqual(null, slot);
}

test "put_then_get" {
    const gpa = testing.allocator;
    var ht: Hashtable = try .init(gpa, 8);
    defer ht.deinit(gpa);

    // Run Test
    try ht.put(1, 0);
    try testing.expectEqual(0, ht.get(1));

    try ht.put(2, 5);
    try testing.expectEqual(5, ht.get(2));
}

test "update_key" {
    const gpa = testing.allocator;
    var ht: Hashtable = try .init(gpa, 8);
    defer ht.deinit(gpa);

    // Run Test
    try ht.put(1, 0);
    try ht.put(1, 1);

    // Assert
    // Check if key is updated
    try testing.expectEqual(1, ht.get(1));
    // Check if there is only one filled slot
    var count: usize = 0;

    for (ht.slots) |slot| {
        if (slot != null) count += 1;
    }
    try testing.expectEqual(1, count);
}

test "error_on_full" {
    const gpa = testing.allocator;
    var ht: Hashtable = try .init(gpa, 8);
    defer ht.deinit(gpa);

    for (1..9) |key| {
        try ht.put(key, key + 1);
    }

    try testing.expectError(error.OutOfSpace, ht.put(9, 10));
}

test "entry is deleted" {
    const gpa: Allocator = testing.allocator;
    var ht: Hashtable = try .init(gpa, 8);
    defer ht.deinit(gpa);

    try ht.put(1, 10);
    ht.remove(1);
    try testing.expectEqual(null, ht.get(1));
}
