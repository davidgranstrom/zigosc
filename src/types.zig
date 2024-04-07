const std = @import("std");
const testing = std.testing;

/// Util
fn alignedStringLength(n: usize) usize {
    return 4 * (1 + @divFloor(n, 4));
}

fn alignedBlobLength(n: usize) usize {
    return 4 * (@divFloor(n + 3, 4));
}

/// Supported OSC types
pub const Type = enum { i, f, s, b, h, t, d, S, c, r, m, T, F, N, I };

pub const Value = union(Type) {
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
    T: void,
    /// False. No bytes are allocated in the argument data.
    F: void,
    /// Nil. No bytes are allocated in the argument data.
    N: void,
    /// Infinitum. No bytes are allocated in the argument data.
    I: void,
    // /// Indicates the beginning of an array. The tags following are for data in the Array until a close brace tag is reached.
    // @"[": void,
    // /// Indicates the end of an array.
    // @"]": void,

    pub fn encode(self: Value, buf: []u8) !usize {
        switch (self) {
            .s, .S => |str| {
                const aligned_len = alignedStringLength(str.len);
                if (buf.len < aligned_len)
                    return error.OutOfMemory;
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
            .T, .F, .N, .I => return 0,
            // Scalar values
            inline else => |v| {
                const T = @TypeOf(v);
                const size = @sizeOf(T);
                const length = if (size == 4) u32 else u64;
                if (buf.len < size)
                    return error.OutOfMemory;
                std.mem.writeInt(length, buf[0..size], @bitCast(v), .big);
                return size;
            },
        }
    }

    fn decodeString(buf: []const u8, value: *Value, comptime field_name: []const u8) !usize {
        if (std.mem.indexOfScalar(u8, buf, 0)) |len| {
            value.* = @unionInit(Value, field_name, buf[0..len]);
            return alignedStringLength(len);
        }
        return error.InvalidString;
    }

    pub fn decode(T: Type, buf: []const u8, value: *Value) !usize {
        switch (T) {
            inline else => |t| {
                switch (t) {
                    .s => return decodeString(buf, value, "s"),
                    .S => return decodeString(buf, value, "S"),
                    .b => {
                        var tmp: Value = undefined;
                        const offset = try Value.decode(Type.i, buf, &tmp);
                        const len: usize = @intCast(tmp.i);
                        const size = offset + len;
                        value.* = Value{ .b = buf[offset..size] };
                        return offset + alignedBlobLength(len);
                    },
                    .T, .F, .N, .I => {
                        value.* = @unionInit(Value, @tagName(t), {});
                        return 0;
                    },
                    .i, .f, .c, .r, .m => {
                        value.* = @unionInit(Value, @tagName(t), @bitCast(std.mem.readInt(u32, buf[0..4], .big)));
                        return 4;
                    },
                    .h, .t, .d => {
                        value.* = @unionInit(Value, @tagName(t), @bitCast(std.mem.readInt(u64, buf[0..8], .big)));
                        return 8;
                    },
                }
            },
        }
    }
};

pub const Message = struct {
    address: []const u8,
    typetag: []const u8,
    values: []const Value,

    /// Initialize a new message.
    pub fn init(address: []const u8, typetag: []const u8, values: []const Value) Message {
        return .{
            .address = address,
            .typetag = typetag,
            .values = values,
        };
    }

    pub fn getSize(self: *const Message) usize {
        var size: usize = 0;
        size += alignedStringLength(self.address.len);
        const pad: usize = if (self.typetag[0] != ',') 1 else 0;
        size += alignedStringLength(pad + self.typetag.len);
        for (self.values) |value| {
            size += switch (value) {
                .s => alignedStringLength(value.s.len),
                .S => alignedStringLength(value.S.len),
                .b => alignedBlobLength(value.b.len),
                .i, .f, .c, .r, .m => 4,
                .h, .t, .d => 8,
                .T, .F, .N, .I => 0,
            };
        }
        return size;
    }

    /// Encode the message to OSC bytes
    pub fn encode(self: *const Message, buf: []u8) !usize {
        const address = Value{ .s = self.address };
        var offset = try address.encode(buf[0..]);
        const typetag = Value{ .s = self.typetag };
        if (typetag.s[0] != ',') {
            buf[offset] = ',';
            const tmp_offset = try typetag.encode(buf[1 + offset ..]);
            offset += alignedStringLength(tmp_offset + 1);
        } else {
            offset += try typetag.encode(buf[offset..]);
        }
        for (self.values) |value| {
            offset += try value.encode(buf[offset..]);
        }
        return offset;
    }

    /// Decode the message to zig types
    pub fn decode(buf: []const u8, address: ?*[]const u8, typetag: ?*[]const u8, values: ?[]Value) !usize {
        var tmp: Value = undefined;
        var offset = try Value.decode(Type.s, buf[0..], &tmp);
        if (address) |addr| {
            addr.* = tmp.s;
        }
        offset += try Value.decode(Type.s, buf[offset..], &tmp);
        if (tmp.s[0] != ',')
            return error.InvalidTypetag;
        if (typetag) |tag| {
            tag.* = tmp.s[1..];
        }
        if (values) |vals| {
            for (tmp.s[1..], 0..) |c, i| {
                if (c == 'T' or c == 'F' or c == 'N' or c == 'I') continue;
                const tag_name = [_]u8{c};
                if (std.meta.stringToEnum(Type, &tag_name)) |T| {
                    offset += try Value.decode(T, buf[offset..], &vals[i]);
                } else {
                    return error.InvalidType;
                }
            }
        }
        return offset;
    }
};

const OSCError = error{
    Encode,
    OutOfMemory,
};

pub const BundleElement = struct {
    size: Value,
    content: union(enum) {
        bundle: *const Bundle,
        message: *const Message,
    },

    pub fn initMessage(msg: *const Message) BundleElement {
        return .{
            .content = .{ .message = msg },
            .size = Value{ .i = 0 },
        };
    }

    pub fn initBundle(bundle: *Bundle) BundleElement {
        return .{
            .content = .{ .bundle = bundle },
            .size = Value{ .i = 0 },
        };
    }

    pub fn getSize(self: *BundleElement) usize {
        return switch (self.content) {
            .message => |msg| msg.getSize(),
            .bundle => |bundle| bundle.getSize(),
        };
    }

    pub fn encode(self: *BundleElement, buf: []u8) OSCError!usize {
        const size = switch (self.content) {
            .message => |msg| try msg.encode(buf),
            .bundle => |bundle| try bundle.encode(buf),
        };
        self.size.i = @intCast(size);
        return size;
    }

    pub fn decode(buf: []const u8) !usize {
        _ = buf;
    }
};

pub const Bundle = struct {
    timetag: Value,
    element: *BundleElement,

    pub fn init(timetag: u64, element: *BundleElement) Bundle {
        return .{
            .timetag = Value{ .t = timetag },
            .element = element,
        };
    }

    pub fn getSize(self: *const Bundle) usize {
        var size: usize = 20; // #bundle (8) + timetag (8) + size (4)
        size += self.element.getSize();
        return size;
    }

    pub fn encode(self: *const Bundle, buf: []u8) !usize {
        const header = Value{ .s = "#bundle" };
        var offset = try header.encode(buf);
        offset += try self.timetag.encode(buf[offset..]);
        const element_size = Value{ .i = @intCast(self.element.getSize()) };
        offset += try element_size.encode(buf[offset..]);
        offset += try self.element.encode(buf[offset..]);
        return offset;
    }
};

test "bundle" {
    var buf: [128]u8 = undefined;
    const msg = Message.init("/foo/bar", "ifT", &[_]Value{ .{ .i = 1234 }, .{ .f = 1.234 } }); // 28 bytes
    var element = BundleElement.initMessage(&msg);
    var bundle = Bundle.init(0, &element);

    var num_encoded_bytes = try bundle.encode(&buf);
    try testing.expectEqual(@as(usize, 0), num_encoded_bytes % 4);
    try testing.expectEqual(msg.getSize() + 20, num_encoded_bytes); // #bundle (8) + timetag (8) + size (4)
    const first_bundle_size = num_encoded_bytes;

    var nested_bundle = BundleElement.initBundle(&bundle);
    var bundle2 = Bundle.init(0, &nested_bundle);
    num_encoded_bytes = try bundle2.encode(&buf);
    try testing.expectEqual(@as(usize, 68), first_bundle_size + 20);
    try testing.expectEqual(@as(usize, 68), bundle2.getSize());
}

test "message" {
    const values = [_]Value{ .{ .i = 1234 }, .{ .f = 1.234 } };
    var msg = Message.init("/foo/bar", "ifT", &values); // 12 + 8 + 4 + 4
    var buf: [64]u8 = undefined;
    const num_encoded_bytes = try msg.encode(&buf);

    try testing.expectEqual(@as(usize, 0), num_encoded_bytes % 4);
    try testing.expectEqual(num_encoded_bytes, msg.getSize());

    var address: []const u8 = undefined;
    var typetag: []const u8 = undefined;
    var out_values: [2]Value = undefined;

    const num_decoded_bytes = try Message.decode(&buf, &address, &typetag, out_values[0..]);
    try testing.expectEqual(num_encoded_bytes, num_decoded_bytes);
    try testing.expectEqualSlices(u8, "/foo/bar", address);
    try testing.expectEqualSlices(u8, "ifT", typetag);
    try testing.expectEqual(@as(i32, 1234), out_values[0].i);
    try testing.expectEqual(@as(f32, 1.234), out_values[1].f);
}

test "value encode/decode" {
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
