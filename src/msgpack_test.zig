const std = @import("std");
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const deserialize = msgpack.deserialize;
const toVal = msgpack.toVal;
const serializeList = msgpack.serializeList;

test "serializes and deserializes f32, and f64" {
    // Serializing
    const expected = &[_]u8{
        148, 202, 68,  13, 248,
        229, 202, 196, 13, 248,
        229, 203, 65,  33, 84,
        141, 135, 43,  2,  12,
        203, 193, 33,  84, 141,
        135, 43,  2,   12,
    };

    const serialized = try msgpack.serializeList(std.testing.allocator, &[_]Value{
        toVal(567.889, f32),
        toVal(-567.889, f32),
        toVal(567878.764, f64),
        toVal(-567878.764, f64),
    });
    defer serialized.deinit();

    std.testing.expectEqualSlices(u8, serialized.items, expected);

    // Deserializing
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const deserialized = (try deserialize(&allocator, serialized.items)).Array;
    std.testing.expectEqual(deserialized[0].Float32, 567.889);
    std.testing.expectEqual(deserialized[1].Float32, -567.889);
    std.testing.expectEqual(deserialized[2].Float64, 567878.764);
    std.testing.expectEqual(deserialized[3].Float64, -567878.764);
}

test "deserializes u8, u16, u32, u64" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const expected: []const Value = &[_]Value{
        toVal(8, u8),
        toVal(7699, u16),
        toVal(7870887, u32),
        toVal(8798787097890789, u64),
    };

    const byte_list = try msgpack.serializeList(std.testing.allocator, expected);
    defer byte_list.deinit();

    const deserialized = (try deserialize(&allocator, byte_list.items)).Array;

    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        std.testing.expectEqual(expected[i], deserialized[i]);
    }
}

test "deserializes fixarray" {
    std.testing.log_level = std.log.Level.debug;

    const expected: Value = toVal(&[_]Value{
        toVal("hello", []const u8),
        toVal("goodbye", []const u8),
        toVal(6, i8),
    }, []const Value);
    var serialized = try serializeList(std.testing.allocator, expected.Array);
    const bytes = serialized.toOwnedSlice();

    defer std.testing.allocator.free(bytes);

    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const deserialized = try deserialize(&allocator, bytes);

    std.testing.expectEqual(deserialized.Array.len, expected.Array.len);
    std.testing.expectEqualStrings(deserialized.Array[0].String, expected.Array[0].String);
    std.testing.expectEqualStrings(deserialized.Array[1].String, expected.Array[1].String);
    std.testing.expectEqual(deserialized.Array[2].Int8, expected.Array[2].Int8);
}

test "deserializes negative fixnum" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);

    const deserialized = try deserialize(&allocator, &[_]u8{
    // -32 in msgpack, so right at the boundary of what a negative fixint
    // can be (any less and it would be an int8).
    224});

    const expected: i8 = -32;

    std.testing.expectEqual(expected, deserialized.Int8);
}

test "deserializes array32 with fixnums" {
    std.testing.log_level = std.log.Level.debug;

    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const deserialized = try deserialize(&allocator, &[_]u8{
        221, 0, 0, 0, 3, 1, 2, 3,
    });

    const expected = &[_]Value{
        toVal(1, i8),
        toVal(2, i8),
        toVal(3, i8),
    };

    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        std.testing.expectEqual(expected[i].Int8, deserialized.Array[i].Int8);
    }
}

test "deserializes 'hello'" {
    std.testing.log_level = std.log.Level.debug;

    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const val = try deserialize(&allocator, &[_]u8{
        165, 104, 101, 108, 108, 111,
    });

    var i: usize = 0;
    const expected_bytes = "hello";
    while (i < expected_bytes.len) : (i += 1) {
        std.testing.expectEqual(expected_bytes[i], val.String[i]);
    }
}

test "serialization" {
    var test_allocator = std.testing.allocator;
    var a = std.heap.ArenaAllocator.init(test_allocator);
    defer a.deinit();

    var map = std.StringHashMap(Value).init(test_allocator);
    defer map.deinit();

    try map.put("stuff", toVal(5, i8));
    try map.put("stuff more", toVal(-200.9877, f32));
    try map.put("stuff more more", toVal("wassup yo?", []const u8));
    try map.put("stuff more more more", toVal(false, null));

    const val = try serializeList(test_allocator, &[_]Value{
        toVal(map, null),
        toVal(64, i8),
        toVal(true, null),
        toVal(832, u16),
        toVal(&[_]Value{
            toVal(false, null),
            toVal("hello there", []const u8),
            toVal(&[_]Value{
                toVal("Even more nesting", []const u8),
                toVal(567, i16),
                toVal(false, null),
                toVal(null, null),
            }, []const Value),
        }, []const Value),
    });
    defer val.deinit();

    // std.debug.warn("[", .{});
    // for (val.items) |item| {
    //     std.debug.warn("{}, ", .{item});
    // }
    // std.debug.warn("]\n", .{});
}
