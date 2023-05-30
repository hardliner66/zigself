// Copyright (c) 2021-2022, sin-ack <sin-ack@protonmail.com>
//
// SPDX-License-Identifier: GPL-3.0-only

const std = @import("std");
const Allocator = std.mem.Allocator;

const Map = @import("map.zig").Map;
const Heap = @import("../Heap.zig");
const debug = @import("../../debug.zig");
const Object = @import("../object.zig").Object;
const VMByteArray = @import("../ByteArray.zig");
const value_import = @import("../value.zig");
const GenericValue = value_import.Value;
const stage2_compat = @import("../../utility/stage2_compat.zig");
const object_lookup = @import("../object_lookup.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

const LOOKUP_DEBUG = debug.LOOKUP_DEBUG;

pub const ByteArray = extern struct {
    object: Object align(@alignOf(u64)),
    byte_array: GenericValue align(@alignOf(u64)),

    pub const Ptr = stage2_compat.HeapPtr(ByteArray, .Mutable);
    pub const Type = .ByteArray;
    pub const Value = value_import.ObjectValue(ByteArray);

    /// Create an initialized byte array object from the given values.
    pub fn createWithValues(map_map: Map.Ptr, token: *Heap.AllocationToken, actor_id: u31, values: []const u8) ByteArray.Ptr {
        const self = createUninitialized(map_map, token, actor_id, values.len);
        @memcpy(self.getValues(), values);
        return self;
    }

    /// Create an uninitialized byte array object with the given size.
    pub fn createUninitialized(map_map: Map.Ptr, token: *Heap.AllocationToken, actor_id: u31, size: usize) ByteArray.Ptr {
        const byte_array = VMByteArray.createUninitialized(token, size);
        return create(map_map, token, actor_id, byte_array);
    }

    /// Create a byte array object with an existing byte array.
    pub fn create(map_map: Map.Ptr, token: *Heap.AllocationToken, actor_id: u31, byte_array: VMByteArray) ByteArray.Ptr {
        const size = requiredSizeForAllocation(null);
        var memory_area = token.allocate(.Object, size);
        var self = @ptrCast(ByteArray.Ptr, memory_area);
        self.init(actor_id, map_map, byte_array);

        return self;
    }

    fn init(self: ByteArray.Ptr, actor_id: u31, map_map: Map.Ptr, byte_array: VMByteArray) void {
        self.object = .{
            .object_information = .{
                .object_type = .ByteArray,
                .actor_id = actor_id,
            },
            .map = map_map.asValue(),
        };
        self.byte_array = byte_array.asValue();
    }

    pub fn asObjectAddress(self: ByteArray.Ptr) [*]u64 {
        return @ptrCast([*]u64, @alignCast(@alignOf(u64), self));
    }

    pub fn asValue(self: ByteArray.Ptr) GenericValue {
        return GenericValue.fromObjectAddress(self.asObjectAddress());
    }

    pub fn getValues(self: ByteArray.Ptr) []u8 {
        return self.getByteArray().getValues();
    }

    pub fn getLength(self: ByteArray.Ptr) u64 {
        return self.getByteArray().header.length.get();
    }

    pub fn getByteArray(self: ByteArray.Ptr) VMByteArray {
        return self.byte_array.asByteArray();
    }

    pub fn clone(self: ByteArray.Ptr, token: *Heap.AllocationToken, actor_id: u31) ByteArray.Ptr {
        const map_map = self.object.getMap();
        return createWithValues(map_map, token, actor_id, self.getValues());
    }

    pub fn getSizeInMemory(self: ByteArray.Ptr) usize {
        _ = self;
        return requiredSizeForAllocation(null);
    }

    pub fn canFinalize(self: ByteArray.Ptr) bool {
        _ = self;
        return false;
    }

    pub fn finalize(self: ByteArray.Ptr, allocator: Allocator) void {
        _ = self;
        _ = allocator;
        @panic("Attempted to call Array.finalize");
    }

    pub fn lookup(self: ByteArray.Ptr, vm: *VirtualMachine, selector_hash: object_lookup.SelectorHash, previously_visited: ?*const object_lookup.VisitedValueLink) object_lookup.LookupResult {
        _ = self;
        _ = previously_visited;

        if (LOOKUP_DEBUG) std.debug.print("ByteArray.lookup: Looking at traits string\n", .{});
        const string_traits = vm.string_traits.getValue();
        if (selector_hash.regular == object_lookup.parent_hash)
            return object_lookup.LookupResult{ .Regular = string_traits };

        return string_traits.lookupByHash(vm, selector_hash);
    }

    /// Call with null if the byte array object has already been allocated.
    pub fn requiredSizeForAllocation(length: ?usize) usize {
        const required_size = @sizeOf(ByteArray);

        if (length) |l| {
            return required_size + VMByteArray.requiredSizeForAllocation(l);
        }

        return required_size;
    }

    pub fn humanReadableName() []const u8 {
        return "a byte array";
    }
};
