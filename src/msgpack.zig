const std = @import("std");
const ArrayList = std.ArrayList;

pub fn deserialize(bytes: []const u8) ?[]const u8 {
    const starting_byte = bytes[0];
    if ((starting_byte & 0xF0) == 0x90) {
        // fixarray
        const len = starting_byte & 0xF;
        std.debug.warn("thing, {}, {}\n", .{bytes[1] & 0x1F, bytes[1]});

        return bytes[1..len];
    } else if ((starting_byte & 0xE0) == 0xA0) {
        // fixstr
        const len = starting_byte & 0x1F;
    } else {
    }

    return null;

    // for (bytes) |byte| {
    //     switch (byte) {
    //         // array16
    //         0xdc => {

    //         },
    //         else => @compileError("Deserialization not implemented for type")
    //     }
    // }
}

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
        @TypeOf(null) => Value { .Null = {} },
        else => @compileLog("Can't serialize type ", thing, " to msgpack.")
    };
}

pub fn serializeAndAppend(array: *ArrayList(u8), val: Value) anyerror!void {
    switch (val) {
        Value.Null => try array.*.append(0xc0),
        Value.Int8 => |x| {
            try array.*.append(0xd0);

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
        }
    }
}

// fn pushSerialized(array: *ArrayList(u8), comptime T: type, thing: T) anyerror!void {
// fn pushSerialized(array: *ArrayList(u8), thing: anytype) anyerror!void {
//     const T = @TypeOf(thing);
//     switch (T) {
//         // usize, isize => {
//             // try self.*.current_serialized.append(thing);
//         // },
//         @TypeOf(null) => {
//         },
//         u8, i8 => {
//             if (T == i8) {
//               try array.*.append(0xd0);
//             } else {
//                 try array.*.append(0xcc);
//             }
//
//             try array.*.append(@intCast(u8, @as(i16, thing) & 0xFF));
//         },
//         u16, i16 => {
//             if (T == i16) {
//               try array.*.append(0xd1);
//             } else {
//                 try array.*.append(0xcd);
//             }
//
//             try array.*.append(@intCast(u8, (thing >> 8) & 0xFF));
//             try array.*.append(@intCast(u8, thing & 0xFF));
//         },
//         u32, i32 => {
//             if (T == i32) {
//                 try array.*.append(0xd2);
//             } else {
//                 try array.*.append(0xce);
//             }
//
//             try array.*.append(@intCast(u8, (thing >> 24) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 16) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 8) & 0xFF));
//             try array.*.append(@intCast(u8, thing & 0xFF));
//         },
//         u64, i64 => {
//             if (T == i64) {
//                 try array.*.append(0xd3);
//             } else {
//                 try array.*.append(0xcf);
//             }
//
//             try array.*.append(@intCast(u8, (thing >> 56) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 48) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 40) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 32) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 24) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 16) & 0xFF));
//             try array.*.append(@intCast(u8, (thing >> 8) & 0xFF));
//             try array.*.append(@intCast(u8, thing & 0xFF));
//         },
//         bool => {
//             if (thing) {
//                 try array.*.append(0xc3);
//             } else {
//                 try array.*.append(0xc2);
//             }
//         },
//         f32, f64 => {
//             if (T == f64) {
//                 try array.*.append(0xcb);
//             } else {
//                 // f32
//                 try array.*.append(0xca);
//             }
//
//             // TODO(smolck): Performance? Alternative?
//             var bytes = std.mem.toBytes(thing);
//             std.mem.reverse(u8, &bytes);
//
//             for (bytes) |byte| {
//                 std.debug.warn("BYTE: {}\n", .{byte});
//                 try array.*.append(byte);
//             }
//         },
//         []const u8 => {
//             if (thing.len < 31) {
//                 // fixstr
//                 try array.*.append(0xa0 | @intCast(u8, thing.len));
//             } else if (thing.len <= std.math.maxInt(u8)) {
//                 // str8
//                 try array.*.append(0xd9);
//                 try array.*.append(@intCast(u8, thing.len));
//             } else if (thing.len <= std.math.maxInt(u16)) {
//                 // str16
//                 try array.*.append(0xd9);
//
//                 try array.*.append(@intCast(u8, (thing.len >> 8) & 0xFF));
//                 try array.*.append(@intCast(u8, thing.len & 0xFF));
//             } else {
//                 // assume str32
//                 try array.*.append(0xdb);
//
//                 try array.*.append(@intCast(u8, (thing.len >> 24) & 0xFF));
//                 try array.*.append(@intCast(u8, (thing.len >> 16) & 0xFF));
//                 try array.*.append(@intCast(u8, (thing.len >> 8) & 0xFF));
//                 try array.*.append(@intCast(u8, thing.len & 0xFF));
//             }
//
//             for (thing) |byte| {
//                 try array.*.append(byte);
//             }
//         },
//         else => @compileError("Serialization not implemented for type!")
//         // TODO(smolck): I think work still needs to be done to allow for using
//         // anonymous structs like this, as lists with items of several different
//         // types. Can't seem to implement it yet.
//         // See: https://github.com/ziglang/zig/issues/3915, which I think is a
//         // relevant issue.
//         // {
//         //     const info = @typeInfo(T);
//         //     if (info == .Struct) {
//         //         try startArray(array, info.Struct.fields.len);
//         //         inline for (info.Struct.fields) |field| {
//         //             if (field.default_value) |value| {
//         //                 try pushSerialized(array, value);
//         // TODO(smolck): The last line of this `else if` causes a segfault for some reason,
//         // saying it's a bug in the Zig compiler? Why?
//         //             } else if (@typeInfo(@TypeOf(field)) == .Struct) {
//         //                 const info2 = @typeInfo(@TypeOf(field));
//         //                 std.debug.print("\nINFO: {}\n", .{info2});
//         //                 try pushSerialized(array, value);
//         //             } else {
//         //                 // null
//         //                 try array.*.append(0xc0);
//         //                 std.debug.print("NULL: {}\n", .{@typeInfo(@TypeOf(field))});
//         //             }
//         //         }
//         //     } else {
//         //         std.debug.print("BLAH: {}\n", .{info});
//         //     }
//         // }
//     }
// }

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

pub fn serializeList(allocator: *std.mem.Allocator, values: []Value) !ArrayList(u8) {
    var item_list = ArrayList(u8).init(allocator);
    errdefer item_list.deinit();

    try startArray(&item_list, values.len);
    for (values) |val| {
        try serializeAndAppend(&item_list, val);
    }

    return item_list;
}

pub fn startMap(self: *Msgpack, count: u64) !void {
    if (count <= 15) {
        try self.*.current_serialized.append(0x80 | @intCast(u8, count));
    } else if (count <= std.math.maxInt(u16)) {
    }
}


test "serializes i64" {
}

test "serialization" {
    var a = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer a.deinit();

    const val = try serializeList(&a.allocator, &[_]Value{
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

    std.debug.warn("[", .{});
    for (val.items) |item| {
        std.debug.warn("{}, ", .{item});
    }
    std.debug.warn("]\n", .{});
}
