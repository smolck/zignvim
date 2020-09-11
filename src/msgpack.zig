const std = @import("std");
const ArrayList = std.ArrayList;

const Value = union(enum) {
    Uint8: u8,
    Uint16: u16,
    Uint32: u32,
    Uint64: u64,

    Int8: i8,
    Int16: i16,
    Int32: i32,
    Int64: i64,

    Float32: f32,
    Float64: f64,

    Null,

    Bool: bool,
    String: []const u8,

    Array: []const Value,

    Map: *const std.StringHashMap(Value),
};

pub fn toVal(thing: anytype, comptime T_opt: ?type) Value {
    const T = T_opt orelse @TypeOf(thing);
    return switch (T) {
        u8 => Value { .Uint8 = thing },
        u16 => Value { .Uint16 = thing },
        u32 => Value { .Uint32 = thing },
        u64 => Value { .Uint64 = thing },
        i8 => Value { .Int8 = thing },
        i16 => Value { .Int16 = thing },
        i32 => Value { .Int32 = thing },
        i64 => Value { .Int64 = thing },
        f32 => Value { .Float32 = thing },
        f64 => Value { .Float64 = thing },
        bool => Value { .Bool = thing },
        []const u8 => Value { .String = thing },
        []const Value => Value { .Array = thing },
        std.StringHashMap(Value) => Value { .Map = &thing },
        @TypeOf(null) => Value { .Null = {} },
        else => @compileLog("Can't serialize type ", thing, " to msgpack.")
    };
}

pub fn serializeAndAppend(array: *ArrayList(u8), val: Value) anyerror!void {
    switch (val) {
        Value.Null => try array.*.append(0xc0),
        Value.Int8 => |x| {
            if (!(x >= -32)) {
                // Not a fixint, so add start for serializing an int8
                try array.*.append(0xd0);
            }

            try array.*.append(@intCast(u8, @as(i16, x) & 0xFF));
        },
        Value.Int16 => |x| {
            try array.*.append(0xd1);

            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));
        },
        Value.Int32 => |x| {
            try array.*.append(0xd2);

            try array.*.append(@intCast(u8, (x >> 24) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 16) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));
        },
        Value.Int64 => |x| {
            try array.*.append(0xd3);

            try array.*.append(@intCast(u8, (x >> 56) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 48) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 40) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 32) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 24) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 16) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));
        },
        Value.Uint8 => |x| {
            try array.*.append(0xcc);
            try array.*.append(@intCast(u8, @as(i16, x) & 0xFF));
        },
        Value.Uint16 => |x| {
            try array.*.append(0xcd);

            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));

        },
        Value.Uint32 => |x| {
            try array.*.append(0xce);

            try array.*.append(@intCast(u8, (x >> 24) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 16) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));
        },
        Value.Uint64 => |x| {
            try array.*.append(0xcf);

            try array.*.append(@intCast(u8, (x >> 56) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 48) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 40) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 32) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 24) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 16) & 0xFF));
            try array.*.append(@intCast(u8, (x >> 8) & 0xFF));
            try array.*.append(@intCast(u8, x & 0xFF));
        },
        Value.Bool => |x| {
            if (x) {
                try array.*.append(0xc3);
            } else {
                try array.*.append(0xc2);
            }
        },
        Value.Float32 => |x| {
            try array.*.append(0xca);

            var bytes = std.mem.toBytes(x);
            std.mem.reverse(u8, &bytes);

            for (bytes) |byte| {
                // std.debug.warn("BYTE: {}\n", .{byte});
                try array.*.append(byte);
            }
        },
        Value.Float64 => |x| {
            try array.*.append(0xcb);

            // TODO(smolck): Performance? Alternative?
            var bytes = std.mem.toBytes(x);
            std.mem.reverse(u8, &bytes);

            for (bytes) |byte| {
                // std.debug.warn("BYTE: {}\n", .{byte});
                try array.*.append(byte);
            }

        },
        Value.String => |x| {
            if (x.len < 31) {
                // fixstr
                try array.*.append(0xa0 | @intCast(u8, x.len));
            } else if (x.len <= std.math.maxInt(u8)) {
                // str8
                try array.*.append(0xd9);
                try array.*.append(@intCast(u8, x.len));
            } else if (x.len <= std.math.maxInt(u16)) {
                // str16
                try array.*.append(0xd9);

                try array.*.append(@intCast(u8, (x.len >> 8) & 0xFF));
                try array.*.append(@intCast(u8, x.len & 0xFF));
            } else {
                // assume str32
                try array.*.append(0xdb);

                try array.*.append(@intCast(u8, (x.len >> 24) & 0xFF));
                try array.*.append(@intCast(u8, (x.len >> 16) & 0xFF));
                try array.*.append(@intCast(u8, (x.len >> 8) & 0xFF));
                try array.*.append(@intCast(u8, x.len & 0xFF));
            }

            for (x) |byte| {
                try array.*.append(byte);
            }

        },
        Value.Array => |xs| {
            try startArray(array, xs.len);
            for (xs) |x| {
                try serializeAndAppend(array, x);
            }
        },
        Value.Map => |map| {
            var iterator = map.*.iterator();

            try startMap(array, map.*.count());
            while (iterator.next()) |x| {
                try serializeAndAppend(array, toVal(x.key, null));
                try serializeAndAppend(array, x.value);
            }
        }
    }
}

fn startArray(array: *ArrayList(u8), count: u64) !void {
    if (count <= 15) {
        try array.*.append(0x90 | @intCast(u8, count));
    } else if (count <= std.math.maxInt(u16)) {
        try array.*.append(0xdc);
        try array.*.append(@intCast(u8, (@intCast(u16, count) >> 8) & 0xFF));
        try array.*.append(@intCast(u8, count & 0xFF));
    } else {
        try array.*.append(0xdd);

        try array.*.append(@intCast(u8, (count >> 24) & 0xFF));
        try array.*.append(@intCast(u8, (count >> 16) & 0xFF));
        try array.*.append(@intCast(u8, (count >> 8) & 0xFF));
        try array.*.append(@intCast(u8, count & 0xFF));
    }
}

pub fn serializeList(allocator: *std.mem.Allocator, values: []const Value) !ArrayList(u8) {
    var item_list = ArrayList(u8).init(allocator);
    errdefer item_list.deinit();

    try startArray(&item_list, values.len);
    for (values) |val| {
        try serializeAndAppend(&item_list, val);
    }

    return item_list;
}

pub fn startMap(array: *ArrayList(u8), count: u64) !void {
    if (count <= 15) {
        try array.*.append(0x80 | @intCast(u8, count));
    } else if (count <= std.math.maxInt(u16)) {
        try array.*.append(0xde);

        try array.*.append(@intCast(u8, (@intCast(u16, count) >> 8) & 0xFF));
        try array.*.append(@intCast(u8, count & 0xFF));
    } else {
        try array.*.append(0xdf);

        try array.*.append(@intCast(u8, (count >> 24) & 0xFF));
        try array.*.append(@intCast(u8, (count >> 16) & 0xFF));
        try array.*.append(@intCast(u8, (count >> 8) & 0xFF));
        try array.*.append(@intCast(u8, count & 0xFF));
    }
}

fn deserializeU16(bytes: []const u8) Value {
    return toVal(@as(u16, bytes[0]) << 8 |
                 @as(u16, bytes[1]), u16);
}

fn deserializeU32(bytes: []const u8) Value {
    return toVal(@as(u32, bytes[0]) << 24 |
                 @as(u32, bytes[1]) << 16 |
                 @as(u32, bytes[2]) << 8  |
                 @as(u32, bytes[3]), u32);
}

// TODO(smolck): Maybe make allocator more general (or not explicitly an
// ArenaAllocator)? Needs to be an ArenaAllocator though basically, because
// otherwise there will be memory leaks from nested values not getting freed
// (or any values for that matter).
pub fn deserialize(allocator: *std.heap.ArenaAllocator, bytes: []const u8) anyerror!Value {
    const starting_byte = bytes[0];
    if ((starting_byte & 0xE0) == 0xA0) {
        // Fixstr
        const len = starting_byte & 0x1F;
        return toVal(bytes[1..len+1], []const u8);

    } else if ((starting_byte & 0xF0) == 0x90) {
        // Fixarray
        const len = starting_byte & 0xF;
        var values = try ArrayList(Value).initCapacity(&allocator.*.allocator, len);

        var i: usize = 1;
        while (i < len+1) : (i += 1) {
            try values.append(try deserialize(allocator, bytes[i..len+1]));
        }

        return toVal(values.toOwnedSlice(), []const Value);

    } else if ((starting_byte & 0xE0) == 0xE0) {
        // Negative fixnum
        return toVal(@intCast(i8, @intCast(i16, starting_byte) - 256), i8);
    } else if (starting_byte <= std.math.maxInt(i8)) {
        // Positive fixnum
        return toVal(@bitCast(i8, starting_byte), i8);
    }

    switch (starting_byte) {
        0xdc => {
            // Array16
            var len: usize = deserializeU16(bytes[1..3]).Uint16;
            var values = try ArrayList(Value).initCapacity(&allocator.*.allocator, len);
            const new_bytes = bytes[3..len+3];

            var i: usize = 0;
            while (i < len) : (i += 1) {
                try values.append(try deserialize(allocator, new_bytes[i..len]));
            }

            return toVal(values.toOwnedSlice(), []const Value);
        },
        0xdd => {
            // Array32
            var len: usize = deserializeU32(bytes[1..5]).Uint32;
            var values = try ArrayList(Value).initCapacity(&allocator.*.allocator, len);
            const new_bytes = bytes[5..len+5];

            var i: usize = 0;
            while (i < len) : (i += 1) {
                try values.append(try deserialize(allocator, new_bytes[i..len]));
            }

            return toVal(values.toOwnedSlice(), []const Value);
        },
        else => return Value { .Null = {}}
    }
}

test "serializes i64" {
}

test "deserializes array16" {
    std.testing.log_level = std.log.Level.debug;

    const expected: Value = toVal(&[_]Value{
        toVal("hello", []const u8),
        toVal("goodbye", []const u8),
        toVal(6, i8),
    }, []const Value);
    var serialized = try serializeList(std.testing.allocator, expected.Array);
    const bytes = serialized.toOwnedSlice();

    // std.log.debug("\nBYTES: [", .{});
    // for (bytes) |byte| {
    //     std.log.debug("{}, ", .{byte});
    // }
    // std.log.debug("]\n", .{});

    defer std.testing.allocator.free(bytes);

    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const deserialized = try deserialize(&allocator, bytes);

    std.testing.expectEqual(deserialized, expected);
}

test "deserializes negative fixnum" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);

    const deserialized = try deserialize(&allocator, &[_]u8 {
        // -32 in msgpack, so right at the boundary of what a negative fixint
        // can be (any less and it would be an int8).
        224
    });

    const expected: i8 = -32;

    std.testing.expectEqual(expected, deserialized.Int8);
}

test "deserializes array32 with fixnums" {
    std.testing.log_level = std.log.Level.debug;

    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    const deserialized = try deserialize(&allocator, &[_]u8{
         221, 0, 0, 0, 3, 1, 2, 3
    });

    const expected = &[_]Value{
        toVal(1, i8),
        toVal(2, i8),
        toVal(3, i8)
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
        165, 104, 101, 108, 108, 111
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
        toVal(&[_]Value {
            toVal(false, null),
            toVal("hello there", []const u8),
            toVal(&[_]Value {
                toVal("Even more nesting", []const u8),
                toVal(567, i16),
                toVal(false, null),
                toVal(null, null)
            }, []const Value)
        }, []const Value),
    });
    defer val.deinit();

    // std.debug.warn("[", .{});
    // for (val.items) |item| {
    //     std.debug.warn("{}, ", .{item});
    // }
    // std.debug.warn("]\n", .{});
}
