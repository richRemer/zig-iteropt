const std = @import("std");
const OptIterator = @import("iteropt.zig").OptIterator;

const OptionIterator = OptIterator(
    "vqo:",
    &.{
        "verbose",
        "quiet",
        "output:",
    },
);

pub const AppConfig = struct {
    verbose: bool = false,
    output: ?[]const u8 = null,
};

pub fn main() void {
    var config = AppConfig{};
    var args = std.process.args();
    var it = OptionIterator.init(&args);

    while (it.next()) |opt_arg| switch (opt_arg) {
        .terminator => {},
        .argument => |arg| std.debug.print("argument: {s}\n", .{arg}),
        .option => |opt| switch (opt) {
            .o, .output => |output| config.output = output,
            .q, .quiet => config.verbose = false,
            .v, .verbose => config.verbose = true,
        },
    };

    std.debug.print("{any}\n", .{config});
}
