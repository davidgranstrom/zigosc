const std = @import("std");

pub const ValueError = error{
    OutOfMemory,
    NullTerminator,
};

pub fn alignedStringLength(n: usize) usize {
    return 4 * (1 + @divFloor(n, 4));
}

pub fn alignedBlobLength(n: usize) usize {
    return 4 * (@divFloor(n + 3, 4));
}

/// Supported OSC types
pub const Type = enum { i, f, s, b, h, t, d, S, c, r, m, T, F, N, I };

/// An OSC value
pub const Value = union(enum) {
    /// Atomic types
    i: i32,
    f: f32,
    s: []const u8,
    b: []const u8,
    /// Extended types
    /// 64 bit big-endian two’s complement integer
    h: i64,
    /// OSC-timetag
    t: u64,
    /// 64 bit (“double”) IEEE 754 floating point number
    d: f64,
    /// Alternate type represented as an OSC-string (for example, for systems that differentiate “symbols” from “strings”)
    S: []const u8,
    /// an ascii character, sent as 32 bits
    c: u32,
    /// 32 bit RGBA color
    r: u32,
    /// 4 byte MIDI message. Bytes from MSB to LSB are: port id, status byte, data1, data2
    m: u32,
    /// True. No bytes are allocated in the argument data.
    TF: bool,
    /// False. No bytes are allocated in the argument data.
    // F: bool,
    /// Nil. No bytes are allocated in the argument data.
    N: void,
    /// Infinitum. No bytes are allocated in the argument data.
    I: f32,

    pub fn encode(self: Value, buf: []u8) ValueError!usize {
        switch (self) {
            .s, .S => |str| {
                const aligned_len = alignedStringLength(str.len);
                if (buf.len < aligned_len)
                    return ValueError.OutOfMemory;
                @memcpy(buf[0..str.len], str);
                @memset(buf[str.len..aligned_len], 0);
                return aligned_len;
            },
            .b => |blob| {
                const len = alignedBlobLength(blob.len);
                const blob_len = Value{ .i = @intCast(blob.len) };
                const offset = try blob_len.encode(buf);
                const start = offset + blob.len;
                const end = offset + len;
                @memcpy(buf[offset .. offset + blob.len], blob);
                @memset(buf[start..end], 0);
                return offset + len;
            },
            .TF, .N, .I => return 0,
            // Scalar values
            inline else => |v| {
                const T = @TypeOf(v);
                const size = @sizeOf(T);
                const length = if (size == 4) u32 else u64;
                if (buf.len < size)
                    return ValueError.OutOfMemory;
                std.mem.writeInt(length, buf[0..size], @bitCast(v), .big);
                return size;
            },
        }
    }

    fn decodeString(buf: []const u8, value: *Value, comptime field_name: []const u8) ValueError!usize {
        if (std.mem.indexOfScalar(u8, buf, 0)) |len| {
            value.* = @unionInit(Value, field_name, buf[0..len]);
            return alignedStringLength(len);
        }
        return ValueError.NullTerminator;
    }

    fn decodeScalar(comptime T: type, buf: []const u8, value: *Value, comptime field_name: []const u8) ValueError!usize {
        const size = @sizeOf(T);
        const DataLen = if (size == 4) u32 else u64;
        value.* = @unionInit(Value, field_name, @bitCast(std.mem.readInt(DataLen, buf[0..size], .big)));
        return size;
    }

    pub fn decode(T: Type, buf: []const u8, value: *Value) ValueError!usize {
        return switch (T) {
            .s => decodeString(buf, value, "s"),
            .S => decodeString(buf, value, "S"),
            .i => decodeScalar(i32, buf, value, "i"),
            .f => decodeScalar(f32, buf, value, "f"),
            .c => decodeScalar(i32, buf, value, "c"),
            .r => decodeScalar(i32, buf, value, "r"),
            .m => decodeScalar(i32, buf, value, "m"),
            .h => decodeScalar(i64, buf, value, "h"),
            .t => decodeScalar(u64, buf, value, "t"),
            .d => decodeScalar(f64, buf, value, "d"),
            .b => {
                var tmp: Value = undefined;
                const offset = try Value.decode(Type.i, buf, &tmp);
                const len: usize = @intCast(tmp.i);
                const size = offset + len;
                value.* = Value{ .b = buf[offset..size] };
                return offset + alignedBlobLength(len);
            },
            .T => {
                value.* = Value{ .TF = true };
                return 0;
            },
            .F => {
                value.* = Value{ .TF = false };
                return 0;
            },
            .N => {
                value.* = Value{ .N = {} };
                return 0;
            },
            .I => {
                value.* = Value{ .I = std.math.inf(f32) };
                return 0;
            },
        };
    }

    pub fn getSize(self: Value) usize {
        return switch (self) {
            .s => |v| alignedStringLength(v.len),
            .S => |v| alignedStringLength(v.len),
            .b => |v| alignedBlobLength(v.len),
            .i, .f, .c, .r, .m => 4,
            .h, .t, .d => 8,
            .TF, .N, .I => 0,
        };
    }
};

test "value encode/decode" {
    const testing = std.testing;

    var buf: [32]u8 = undefined;
    // int
    var value = Value{ .i = 1234 };
    var ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, 4), ret);
    ret = try Value.decode(Type.i, &buf, &value);
    try testing.expectEqual(@as(usize, 4), ret);
    try testing.expectEqual(@as(i32, 1234), value.i);

    // float
    value = Value{ .f = 1.234 };
    ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, 4), ret);
    ret = try Value.decode(Type.f, &buf, &value);
    try testing.expectEqual(@as(usize, 4), ret);
    try testing.expectEqual(@as(f32, 1.234), value.f);

    // string
    value = Value{ .s = "hello world" };
    ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, alignedStringLength(value.s.len)), ret);
    ret = try Value.decode(Type.s, &buf, &value);
    try testing.expectEqual(@as(usize, alignedStringLength(value.s.len)), ret);
    try testing.expectEqualSlices(u8, "hello world", value.s);

    // blob
    value = Value{ .b = &[_]u8{ 0x12, 0x23, 0x00, 0x45 } };
    ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, 4 + alignedBlobLength(value.b.len)), ret);
    ret = try Value.decode(Type.b, &buf, &value);
    try testing.expectEqual(@as(usize, 4 + alignedBlobLength(value.b.len)), ret);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x12, 0x23, 0x00, 0x45 }, value.b);

    // int64
    value = Value{ .h = std.math.maxInt(i64) };
    ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, 8), ret);
    ret = try Value.decode(Type.h, &buf, &value);
    try testing.expectEqual(@as(usize, 8), ret);
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), value.h);

    // timetag
    value = Value{ .t = std.math.maxInt(u64) };
    ret = try value.encode(&buf);
    try testing.expectEqual(@as(usize, 8), ret);
    ret = try Value.decode(Type.t, &buf, &value);
    try testing.expectEqual(@as(usize, 8), ret);
    try testing.expectEqual(@as(u64, std.math.maxInt(u64)), value.t);
}
