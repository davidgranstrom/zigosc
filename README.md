# zigosc

`zigosc` is a [OSC 1.0](https://opensoundcontrol.stanford.edu/spec-1_0.html) serialization library with no dynamic memory allocation.

## Progress

**Serialization**

- [x] Types
- [x] Message
- [x] Bundle

## Build

See `zig build -h` for build options.

```
zig build
```

## Testing

```
zig build test --summary all
```

## Example usage

```zig
const std = @import("std");
const zigosc = @import("zigosc");
const Message = zigosc.Message;
const Value = zigosc.Value;

pub fn main() !void {
    var buf: [128]u8 = undefined;

    // Encode message
    const values = [_]Value{
        .{ .i = 777 },
        .{ .f = 3.14 },
        .{ .s = "hi" },
        .{ .b = &[_]u8{ 0x12, 0x00, 0x23 } },
    };
    var msg = Message.init("/addr", "ifsbTFNI", &values);
    var num_bytes = try msg.encode(&buf);
    const data = buf[0..num_bytes]; // serialized OSC data, suitable for transmission

    // Decode message
    var address: []const u8 = undefined;
    var typetag: []const u8 = undefined;
    var out_values: [8]Value = undefined;
    var num_decoded_values: usize = 0;
    num_bytes = try Message.decode(data, &address, &typetag, &out_values, &num_decoded_values);

    // Inspect
    std.debug.print("address = {s} typetag = {s}\n", .{ address, typetag });
    for (num_decoded_values, 0..) |_, i| {
        std.debug.print("value[{}] = {}\n", .{ i, out_values[i] });
    }
}
```

## License

```
MIT License

Copyright (c) 2024 David Granström

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
