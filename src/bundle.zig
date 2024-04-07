const std = @import("std");
const Message = @import("message.zig").Message;
const Type = @import("value.zig").Type;
const Value = @import("value.zig").Value;

const ValueError = @import("value.zig").ValueError;
const MessageError = @import("message.zig").MessageError;

pub const BundleError = error{
    MissingBundleIdentifier,
};

const Error = ValueError || MessageError || BundleError;

/// Answers if the encoded data is an OSC bundle
pub fn isBundle(buf: []const u8) bool {
    return std.mem.eql(u8, "#bundle\x00", buf[0..8]);
}

/// Utility structure to encode bundle elements
pub const BundleElement = struct {
    content: union(enum) {
        bundle: *Bundle,
        message: *Message,
    },

    pub fn initMessage(msg: *Message) BundleElement {
        return .{
            .content = .{ .message = msg },
        };
    }

    pub fn initBundle(bundle: *Bundle) BundleElement {
        return .{
            .content = .{ .bundle = bundle },
        };
    }

    pub fn getSize(self: *BundleElement) usize {
        return switch (self.content) {
            .message => |msg| msg.getSize(),
            .bundle => |bundle| bundle.getSize(),
        };
    }

    pub fn encode(self: *BundleElement, buf: []u8) Error!usize {
        const size = switch (self.content) {
            .message => |msg| try msg.encode(buf),
            .bundle => |bundle| try bundle.encode(buf),
        };
        return size;
    }
};

/// An OSC Bundle consists of the OSC-string "#bundle" followed by an OSC Time
/// Tag, followed by zero or more OSC Bundle Elements.
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

    pub fn encode(self: *const Bundle, buf: []u8) Error!usize {
        const header = Value{ .s = "#bundle" };
        var offset = try header.encode(buf);
        offset += try self.timetag.encode(buf[offset..]);
        const element_size = Value{ .i = @intCast(self.element.getSize()) };
        offset += try element_size.encode(buf[offset..]);
        offset += try self.element.encode(buf[offset..]);
        return offset;
    }

    pub fn decode(buf: []const u8, timetag: ?*u64, element_size: ?*usize) Error!usize {
        var offset: usize = 0;
        if (!isBundle(buf))
            return BundleError.MissingBundleIdentifier;
        offset += 8;
        var tmp = Value{ .t = 0 };
        offset += try Value.decode(Type.t, buf[offset..], &tmp);
        if (timetag) |tt| {
            tt.* = tmp.t;
        }
        tmp = Value{ .i = 0 };
        offset += try Value.decode(Type.i, buf[offset..], &tmp);
        if (element_size) |ofs| {
            ofs.* = @intCast(tmp.i);
        }
        return offset;
    }
};

test "bundle encode/decode" {
    const testing = std.testing;

    var buf: [128]u8 = undefined;
    var msg = Message.init("/foo/bar", "ifT", &[_]Value{ .{ .i = 1234 }, .{ .f = 1.234 } }); // 28 bytes
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

    try testing.expect(isBundle(&buf));

    var timetag: u64 = undefined;
    var element_size: usize = undefined;
    var offset = try Bundle.decode(&buf, &timetag, &element_size);
    try testing.expectEqual(@as(usize, 20), offset);
    try testing.expect(isBundle(buf[offset..]));
    offset += try Bundle.decode(buf[offset..], &timetag, &element_size);
    try testing.expectEqual(@as(usize, 40), offset);
    try testing.expect(!isBundle(buf[offset..]));
    offset += try Message.decode(buf[offset..], null, null, null);
    try testing.expectEqual(@as(usize, 68), offset);
    try testing.expectEqual(bundle2.getSize(), offset);
}
