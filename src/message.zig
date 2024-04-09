const std = @import("std");
const Type = @import("value.zig").Type;
const Value = @import("value.zig").Value;
const ValueError = @import("value.zig").ValueError;
const alignedStringLength = @import("value.zig").alignedStringLength;

pub const MessageError = error{
    InvalidTypetag,
    InvalidType,
    NotEnoughValues,
};

const Error = ValueError || MessageError;

pub const Message = struct {
    address: []const u8,
    typetag: []const u8,
    values: ?[]const Value,

    /// Initialize a new message.
    pub fn init(address: []const u8, typetag: []const u8, values: ?[]const Value) Message {
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
        if (self.values) |values| {
            for (values) |value| {
                size += value.getSize();
            }
        }
        return size;
    }

    fn encodeTypetag(self: *Message, buf: []u8) !usize {
        var offset: usize = 0;
        const typetag = Value{ .s = self.typetag };
        if (typetag.s.len == 0) {
            @memcpy(buf[offset .. offset + 4], &[_]u8{ ',', 0, 0, 0 });
            offset += 4;
        } else if (typetag.s[0] != ',') {
            buf[offset] = ',';
            offset += 1;
            @memcpy(buf[offset .. offset + typetag.s.len], typetag.s);
            offset += typetag.s.len;
            const aligned_len = alignedStringLength(1 + typetag.s.len);
            const padding = aligned_len - (1 + typetag.s.len);
            @memset(buf[offset .. offset + padding], 0);
            offset += padding;
        } else {
            offset += try typetag.encode(buf[offset..]);
        }
        return offset;
    }

    /// Encode the message to OSC bytes
    pub fn encode(self: *Message, buf: []u8) Error!usize {
        var offset: usize = 0;
        const address = Value{ .s = self.address };
        offset += try address.encode(buf[0..]);
        offset += try self.encodeTypetag(buf[offset..]);
        if (self.values) |values| {
            for (values) |value| {
                offset += try value.encode(buf[offset..]);
            }
        }
        return offset;
    }

    /// Decode the message to zig types
    pub fn decode(buf: []const u8, address: ?*[]const u8, typetag: ?*[]const u8, values: ?[]Value, num_decoded_values: ?*usize) Error!usize {
        var tmp: Value = undefined;
        var offset = try Value.decode(Type.s, buf[0..], &tmp);
        if (address) |addr| {
            addr.* = tmp.s;
        }
        offset += try Value.decode(Type.s, buf[offset..], &tmp);
        if (tmp.s[0] != ',')
            return MessageError.InvalidTypetag;
        if (typetag) |tag| {
            tag.* = tmp.s[1..];
        }
        var num_decoded: usize = 0;
        for (tmp.s[1..]) |c| {
            if (c == 'T' or c == 'F' or c == 'N' or c == 'I') continue;
            const tag_name = [_]u8{c};
            var tmp_val: Value = undefined;
            if (std.meta.stringToEnum(Type, &tag_name)) |T| {
                offset += try Value.decode(T, buf[offset..], &tmp_val);
                if (values) |vals| {
                    if (num_decoded >= vals.len)
                        return MessageError.NotEnoughValues;
                    vals[num_decoded] = tmp_val;
                    num_decoded += 1;
                }
            } else {
                return MessageError.InvalidType;
            }
        }
        if (num_decoded_values) |num| {
            num.* = num_decoded;
        }
        return offset;
    }
};

test "message encode/decode" {
    const testing = std.testing;

    const values = [_]Value{ .{ .i = 1234 }, .{ .f = 1.234 } };
    var msg = Message.init("/foo/bar", "ifT", &values);
    var buf: [64]u8 = undefined;
    var num_encoded_bytes = try msg.encode(&buf);

    try testing.expectEqual(@as(usize, 0), num_encoded_bytes % 4);
    try testing.expectEqual(num_encoded_bytes, msg.getSize());

    var address: []const u8 = undefined;
    var typetag: []const u8 = undefined;
    var out_values: [2]Value = undefined;

    var num_decoded_values: usize = 0;
    const num_decoded_bytes = try Message.decode(&buf, &address, &typetag, out_values[0..], &num_decoded_values);
    try testing.expectEqual(num_encoded_bytes, num_decoded_bytes);
    try testing.expectEqualSlices(u8, "/foo/bar", address);
    try testing.expectEqualSlices(u8, "ifT", typetag);
    try testing.expectEqual(@as(usize, 2), num_decoded_values);
    try testing.expectEqual(@as(i32, 1234), out_values[0].i);
    try testing.expectEqual(@as(f32, 1.234), out_values[1].f);

    msg = Message.init("/ab", "", null);
    num_encoded_bytes = try msg.encode(&buf);
    try testing.expectEqual(@as(usize, 8), num_encoded_bytes);

    msg = Message.init("/ab", ",", null);
    num_encoded_bytes = try msg.encode(&buf);
    try testing.expectEqual(@as(usize, 8), num_encoded_bytes);

    msg = Message.init("/ab", "ifsbTFN", null);
    num_encoded_bytes = try msg.encode(&buf);
    try testing.expectEqual(@as(usize, 16), num_encoded_bytes);

    msg = Message.init("/ab", ",ifsbTFN", null);
    num_encoded_bytes = try msg.encode(&buf);
    try testing.expectEqual(@as(usize, 16), num_encoded_bytes);
}
