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
            size += value.getSize();
        }
        return size;
    }

    /// Encode the message to OSC bytes
    pub fn encode(self: *const Message, buf: []u8) Error!usize {
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
    pub fn decode(buf: []const u8, address: ?*[]const u8, typetag: ?*[]const u8, values: ?[]Value) Error!usize {
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
        for (tmp.s[1..], 0..) |c, i| {
            if (c == 'T' or c == 'F' or c == 'N' or c == 'I') continue;
            const tag_name = [_]u8{c};
            var tmp_val: Value = undefined;
            if (std.meta.stringToEnum(Type, &tag_name)) |T| {
                offset += try Value.decode(T, buf[offset..], &tmp_val);
                if (values) |vals| {
                    if (i >= vals.len)
                        return MessageError.NotEnoughValues;
                    vals[i] = tmp_val;
                }
            } else {
                return MessageError.InvalidType;
            }
        }
        return offset;
    }
};

test "message encode/decode" {
    const testing = std.testing;

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
