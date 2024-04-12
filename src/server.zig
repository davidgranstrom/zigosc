const std = @import("std");

fn matchRange(address: []const u8, pattern: []const u8) bool {
    var range = std.mem.trimLeft(u8, pattern, "[");
    range = std.mem.trimRight(u8, range, "]");
    if (range.len == 0)
        return false;
    const negate = std.mem.startsWith(u8, range, "!");
    var sub_range = std.mem.tokenizeScalar(u8, range, '-');
    const sub_start = sub_range.next();
    const sub_end = sub_range.next();
    if (sub_start) |start| {
        if (sub_end) |end| {
            const start_index: usize = if (start[0] == '!' and start.len > 1) 1 else 0;
            if (address[0] >= start[start_index] and address[0] <= end[0])
                return !negate;
        }
    }
    if (std.mem.indexOfAny(u8, address, range)) |_| {
        return !negate;
    }
    return negate;
}

/// Match an OSC message address with a server method address pattern
fn match(address: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, address))
        return true;

    var address_parts = std.mem.tokenizeScalar(u8, address, '/');
    var pattern_parts = std.mem.tokenizeScalar(u8, pattern, '/');

    while (address_parts.next()) |addr_part| {
        const ptn = pattern_parts.next().?;
        if (!std.mem.eql(u8, addr_part, ptn)) {
            const is_range = std.mem.startsWith(u8, ptn, "[") and std.mem.endsWith(u8, ptn, "]");
            const is_group = std.mem.startsWith(u8, ptn, "{") and std.mem.endsWith(u8, ptn, "}");
            if (is_range and !matchRange(addr_part, ptn)) {
                return false;
            } else if (is_group) {
                //
            }
        }
    }
    return true;
}

test "range pattern matching" {
    const testing = std.testing;
    try testing.expect(match("/foo/a", "/foo/[abcd]"));
    try testing.expect(!match("/foo/e", "/foo/[abcd]"));
    try testing.expect(match("/foo/e", "/foo/[!abcd]"));
    try testing.expect(match("/foo/4/bar", "/foo/[1-4]/bar"));
    try testing.expect(!match("/foo/a/bar", "/foo/[1-4]/bar"));
    try testing.expect(match("/foo/x/bar", "/foo/[a-z]/bar"));
    try testing.expect(match("/foo/1/bar", "/foo/[!a-z]/bar"));
}
