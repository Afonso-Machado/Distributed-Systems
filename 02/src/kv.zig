pub const Hashtable = @import("kv/hashtable.zig").Hashtable;
pub const StateMachine = @import("kv/state_machine.zig").StateMachine;

test {
    _ = @import("kv/hashtable.zig");
    _ = @import("kv/state_machine.zig");
    _ = @import("kv/wire.zig");
}
