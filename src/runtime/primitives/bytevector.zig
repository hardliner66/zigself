// Copyright (c) 2021, sin-ack <sin-ack@protonmail.com>
//
// SPDX-License-Identifier: GPL-3.0-only

const std = @import("std");
const Allocator = std.mem.Allocator;

const Heap = @import("../heap.zig");
const Value = @import("../value.zig").Value;
const Object = @import("../object.zig");
const Completion = @import("../completion.zig");
const ByteVector = @import("../byte_vector.zig");
const environment = @import("../environment.zig");
const SourceRange = @import("../../language/source_range.zig");
const runtime_error = @import("../error.zig");
const InterpreterContext = @import("../interpreter.zig").InterpreterContext;

/// Print the given ByteVector to stdout, followed by a newline.
pub fn StringPrint(
    allocator: Allocator,
    heap: *Heap,
    tracked_receiver: Heap.Tracked,
    arguments: []Heap.Tracked,
    source_range: SourceRange,
    context: *InterpreterContext,
) !Completion {
    _ = heap;
    _ = arguments;
    _ = context;

    const writer = std.io.getStdOut().writer();

    // FIXME: Don't ignore errors.
    const receiver = tracked_receiver.getValue();
    switch (receiver.getType()) {
        .Integer => {
            writer.print("{d}", .{receiver.asInteger()}) catch unreachable;
        },
        .FloatingPoint => {
            writer.print("{d}", .{receiver.asFloatingPoint()}) catch unreachable;
        },
        .ObjectReference => {
            if (!(receiver.asObject().isByteVectorObject())) {
                return Completion.initRuntimeError(allocator, source_range, "Expected ByteVector as the receiver of _StringPrint", .{});
            }

            writer.print("{s}", .{receiver.asObject().asByteVectorObject().getValues()}) catch unreachable;
        },
        else => unreachable,
    }

    return Completion.initNormal(environment.globalNil());
}

/// Return the size of the byte vector in bytes.
pub fn ByteVectorSize(
    allocator: Allocator,
    heap: *Heap,
    tracked_receiver: Heap.Tracked,
    arguments: []Heap.Tracked,
    source_range: SourceRange,
    context: *InterpreterContext,
) !Completion {
    _ = heap;
    _ = arguments;
    _ = context;

    const receiver = tracked_receiver.getValue();
    if (!(receiver.isObjectReference() and receiver.asObject().isByteVectorObject())) {
        return Completion.initRuntimeError(allocator, source_range, "Expected ByteVector as _ByteVectorSize receiver", .{});
    }

    return Completion.initNormal(Value.fromInteger(@intCast(i64, receiver.asObject().asByteVectorObject().getValues().len)));
}

/// Return a byte at the given (integer) position of the receiver, which is a
/// byte vector. Fails if the index is out of bounds or if the receiver is not a
/// byte vector.
pub fn ByteAt(
    allocator: Allocator,
    heap: *Heap,
    tracked_receiver: Heap.Tracked,
    arguments: []Heap.Tracked,
    source_range: SourceRange,
    context: *InterpreterContext,
) !Completion {
    _ = heap;
    _ = context;

    const receiver = tracked_receiver.getValue();
    const argument = arguments[0].getValue();

    if (!(receiver.isObjectReference() and receiver.asObject().isByteVectorObject())) {
        return Completion.initRuntimeError(allocator, source_range, "Expected ByteVector as _ByteAt: receiver", .{});
    }

    if (!argument.isInteger()) {
        return Completion.initRuntimeError(allocator, source_range, "Expected integer as _ByteAt: argument", .{});
    }

    const values = receiver.asObject().asByteVectorObject().getValues();
    const position = @intCast(usize, argument.asInteger());
    if (position < 0 or position >= values.len) {
        return Completion.initRuntimeError(
            allocator,
            source_range,
            "Argument passed to _ByteAt: is out of bounds for this receiver (passed {d}, size {d})",
            .{ position, values.len },
        );
    }

    return Completion.initNormal(Value.fromInteger(values[position]));
}

/// Place the second argument at the position given by the first argument on the
/// byte vector receiver. Fails if the index is out of bounds or if the receiver
/// is not a byte vector.
pub fn ByteAt_Put(
    allocator: Allocator,
    heap: *Heap,
    tracked_receiver: Heap.Tracked,
    arguments: []Heap.Tracked,
    source_range: SourceRange,
    context: *InterpreterContext,
) !Completion {
    _ = heap;
    _ = context;

    const receiver = tracked_receiver.getValue();
    const first_argument = arguments[0].getValue();
    const second_argument = arguments[1].getValue();

    if (!(receiver.isObjectReference() and receiver.asObject().isByteVectorObject())) {
        return Completion.initRuntimeError(allocator, source_range, "Expected ByteVector as _ByteAt:Put: receiver", .{});
    }

    if (!first_argument.isInteger()) {
        return Completion.initRuntimeError(allocator, source_range, "Expected integer as first _ByteAt:Put: argument", .{});
    }
    if (!second_argument.isInteger()) {
        return Completion.initRuntimeError(allocator, source_range, "Expected integer as second _ByteAt:Put: argument", .{});
    }

    var values = receiver.asObject().asByteVectorObject().getValues();
    const position = @intCast(usize, first_argument.asInteger());
    const new_value = second_argument.asInteger();

    if (position < 0 or position >= values.len) {
        return Completion.initRuntimeError(
            allocator,
            source_range,
            "First argument passed to _ByteAt:Put: is out of bounds for this receiver (passed {d}, size {d})",
            .{ position, values.len },
        );
    }

    if (new_value < 0 or new_value > 255) {
        return Completion.initRuntimeError(allocator, source_range, "New value passed to _ByteAt:Put: cannot be cast to a byte", .{});
    }

    values[position] = @intCast(u8, new_value);

    return Completion.initNormal(receiver);
}

/// Copy the byte vector receiver with a new size. Size cannot exceed the
/// receiver's size.
pub fn ByteVectorCopySize(
    allocator: Allocator,
    heap: *Heap,
    tracked_receiver: Heap.Tracked,
    arguments: []Heap.Tracked,
    source_range: SourceRange,
    context: *InterpreterContext,
) !Completion {
    _ = context;

    const receiver = tracked_receiver.getValue();
    var argument = arguments[0].getValue();

    if (!(receiver.isObjectReference() and receiver.asObject().isByteVectorObject())) {
        return Completion.initRuntimeError(allocator, source_range, "Expected ByteVector as _ByteVectorCopySize: receiver", .{});
    }

    if (!argument.isInteger()) {
        return Completion.initRuntimeError(allocator, source_range, "Expected Integer as _ByteVectorCopySize: argument", .{});
    }

    var values = receiver.asObject().asByteVectorObject().getValues();
    const size = argument.asInteger();
    if (size >= values.len) {
        return Completion.initRuntimeError(allocator, source_range, "_ByteVectorCopySize: argument exceeds receiver's size", .{});
    }

    if (size < 0) {
        return Completion.initRuntimeError(allocator, source_range, "_ByteVectorCopySize: argument must be positive", .{});
    }

    try heap.ensureSpaceInEden(
        ByteVector.requiredSizeForAllocation(@intCast(u64, size)) +
            Object.Map.ByteVector.requiredSizeForAllocation() +
            Object.ByteVector.requiredSizeForAllocation(),
    );

    const byte_vector = try ByteVector.createFromString(heap, values[0..@intCast(u64, size)]);
    const byte_vector_map = try Object.Map.ByteVector.create(heap, byte_vector);
    return Completion.initNormal((try Object.ByteVector.create(heap, byte_vector_map)).asValue());
}
