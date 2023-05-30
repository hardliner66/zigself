// Copyright (c) 2021-2022, sin-ack <sin-ack@protonmail.com>
//
// SPDX-License-Identifier: GPL-3.0-only

const std = @import("std");
const Allocator = std.mem.Allocator;

const Heap = @import("Heap.zig");
const Value = value_import.Value;
const value_import = @import("value.zig");
const stage2_compat = @import("../utility/stage2_compat.zig");
const object_lookup = @import("object_lookup.zig");
const VirtualMachine = @import("VirtualMachine.zig");

// TODO: Unify ObjectType and ObjectRegistry once Zig stops treating it as a dependency loop.
pub const ObjectType = enum(u22) {
    Slots,
    Method,
    Block,
    Activation,
    Array,
    ByteArray,
    Managed,
    Actor,
    ActorProxy,
    Map,
    ForwardedObject,
    // Intrinsic objects
    AddrInfo,
};

/// A registry of object types. Objects within this array will be encoded into
/// the object information word by their index.
pub const ObjectRegistry = union(ObjectType) {
    Slots: @import("objects/slots.zig").Slots,
    Method: @import("objects/method.zig").Method,
    Block: @import("objects/block.zig").Block,
    Activation: @import("objects/activation.zig").Activation,
    Array: @import("objects/array.zig").Array,
    ByteArray: @import("objects/byte_array.zig").ByteArray,
    Managed: @import("objects/managed.zig").Managed,
    Actor: @import("objects/actor.zig").Actor,
    ActorProxy: @import("objects/actor_proxy.zig").ActorProxy,
    // This is the base map object that the map-map uses. It will be extended
    // by other types which require additional data on their maps.
    Map: @import("objects/map.zig").Map,
    // Intrinsic objects
    AddrInfo: @import("objects/intrinsic/addrinfo.zig").AddrInfo,
    // This is a special object type that overwrites the current object when the
    // garbage collector copies the object to a new location.
    ForwardedObject: void,
};

pub fn ObjectT(comptime object_type: ObjectType) type {
    const object_type_name = @tagName(object_type);
    inline for (@typeInfo(ObjectRegistry).Union.fields) |field| {
        if (std.mem.eql(u8, object_type_name, field.name))
            return field.type;
    }

    unreachable;
}

// Ensure that all objects contain the Object type as their first word, either directly
// or via another parent object.
comptime {
    next_object: inline for (@typeInfo(ObjectRegistry).Union.fields) |field| {
        if (std.mem.eql(u8, field.name, "ForwardedObject"))
            continue :next_object;

        var object_first_field = @typeInfo(field.type).Struct.fields[0].type;
        while (@typeInfo(object_first_field) == .Struct) {
            if (object_first_field == Object)
                continue :next_object;
            object_first_field = @typeInfo(object_first_field).Struct.fields[0].type;
        }

        @compileError("!!! Object " ++ @typeName(field.type) ++ " does not contain an object header!");
    }
}

/// The generic object that can be cast into a more specific type. This is the
/// core of all objects on the object segment of the ZigSelf heap.
pub const Object = extern struct {
    object_information: ObjectInformation align(@alignOf(u64)),
    map: Value align(@alignOf(u64)),

    pub const Ptr = stage2_compat.HeapPtr(Object, .Mutable);

    const ObjectMarker = u2;
    // FIXME: Define this in a more actor-central place.
    pub const ActorID = u31;
    pub const Reachability = enum(u1) { Local, Global };
    pub const ObjectInformation = packed struct(u64) {
        object_marker: ObjectMarker = @enumToInt(Value.ValueType.ObjectMarker),
        object_type: ObjectType,
        // This can be used by downstream objects to store extra data.
        //
        // FIXME: Right now any downstream object can use this. We need a proper
        //        partitioning schema in order to this becoming a spaghettified
        //        mess of "who owns what".
        extra: u8 = 0,
        actor_id: ActorID,
        reachability: Reachability = .Local,
    };

    /// Delegate to the correct method for each object type.
    fn delegate(self: Ptr, comptime ReturnType: type, comptime name: []const u8, args: anytype) ReturnType {
        return switch (self.object_information.object_type) {
            .ForwardedObject => unreachable,
            inline else => |t| @call(.auto, @field(ObjectT(t), name), .{@ptrCast(ObjectT(t).Ptr, self)} ++ args),
        };
    }

    /// Cast the given address to an object.
    pub fn fromAddress(address: [*]u64) Ptr {
        const as_object = @ptrCast(Ptr, address);
        if (as_object.object_information.object_marker != @enumToInt(Value.ValueType.ObjectMarker)) {
            std.debug.panic("!!! Object.fromAddress got an address ({*}) that does NOT contain an object marker ({x})!", .{ address, address[0] });
        }

        return as_object;
    }

    // Reflective operations

    /// If the object is of the given type, return it as that type. Otherwise return null.
    pub fn asType(self: Ptr, comptime object_type: ObjectType) ?ObjectT(object_type).Ptr {
        if (self.object_information.object_type != object_type) {
            return null;
        }

        return @ptrCast(ObjectT(object_type).Ptr, self);
    }

    /// Return the object as the given type, panicking in safe release modes if
    /// it's not the correct type. In release modes without runtime safety,
    /// asking for an object of different type is undefined behavior.
    pub fn mustBeType(self: Ptr, comptime object_type: ObjectType) ObjectT(object_type).Ptr {
        if (std.debug.runtime_safety) {
            if (self.asType(object_type)) |ptr| {
                return ptr;
            }

            std.debug.panic("!!! mustBeType tried to cast a {*} of type '{s}' to type '{s}'!", .{ self, @tagName(self.object_information.object_type), @tagName(object_type) });
        }

        return @ptrCast(ObjectT(object_type).Ptr, self);
    }

    /// Return the address of this object.
    pub fn getAddress(self: Ptr) [*]u64 {
        return @ptrCast([*]u64, self);
    }

    /// Return this object as a Value.
    pub fn asValue(self: Ptr) Value {
        return Value.fromObjectAddress(self.getAddress());
    }

    // Delegate methods

    /// Get the size of this object in memory. Includes *only* the memory in object
    /// segment.
    pub fn getSizeInMemory(self: Ptr) usize {
        return self.delegate(usize, "getSizeInMemory", .{});
    }

    /// Return whether this object can be finalized.
    pub fn canFinalize(self: Ptr) bool {
        return self.delegate(bool, "canFinalize", .{});
    }

    /// Finalize this object. Skip if the object does not support finalization.
    pub fn finalize(self: Ptr, allocator: Allocator) void {
        std.debug.assert(self.canFinalize());
        // FIXME: This forces the finalize method to be defined on objects that
        //        don't support finalization. Find a way that can avoid forcing
        //        the definition of the useless finalize method.
        self.delegate(void, "finalize", .{allocator});
    }

    /// Create a new shallow copy of this object. The map is not affected.
    pub fn clone(self: Ptr, token: *Heap.AllocationToken, actor_id: u31) Allocator.Error!Ptr {
        // NOTE: Inlining the delegation here because we need to cast the result into the generic object type.
        return switch (self.object_information.object_type) {
            .ForwardedObject => unreachable,
            inline else => |t| {
                if (!@hasDecl(ObjectT(t), "clone")) unreachable;

                const result_or_error = @ptrCast(ObjectT(t).Ptr, self).clone(token, actor_id);
                const result = if (@typeInfo(@TypeOf(result_or_error)) == .ErrorUnion) try result_or_error else result_or_error;
                return @ptrCast(Object.Ptr, result);
            },
        };
    }

    pub fn lookup(self: Ptr, vm: *VirtualMachine, selector_hash: object_lookup.SelectorHash, previously_visited: ?*const object_lookup.VisitedValueLink) object_lookup.LookupResult {
        return self.delegate(object_lookup.LookupResult, "lookup", .{ vm, selector_hash, previously_visited });
    }

    // Forwarded objects

    pub fn isForwarded(self: Ptr) bool {
        return self.object_information.object_type == .ForwardedObject;
    }

    pub fn getForwardAddress(self: Ptr) [*]u64 {
        std.debug.assert(self.isForwarded());
        return self.map.asObjectAddress();
    }

    /// Set the given address as the forwarding address of this object.
    /// **Overwrites the current object type.**
    pub fn forwardObjectTo(self: Ptr, address: [*]u64) void {
        std.debug.assert(!self.isForwarded());

        self.object_information.object_type = .ForwardedObject;
        self.map = Value.fromObjectAddress(address);
    }

    /// Get the map for this object.
    pub fn getMap(self: Ptr) ObjectT(.Map).Ptr {
        var object = self.map.asObject();

        // XXX: If we're currently in the middle of scavenging, then our map
        //      probably has already been scavenged into the target space and
        //      a forward reference has been placed in its location instead.
        //      We should get the forwarded object.
        if (object.isForwarded()) {
            object = fromAddress(object.getForwardAddress());
        }

        return object.mustBeType(.Map);
    }
};
