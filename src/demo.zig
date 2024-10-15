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
    const stderr = std.io.getStdErr().writer();

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
        .usage => |use| {
            const message = switch (use.@"error") {
                .unknown_option => "unknown option",
                .missing_argument => "missing argument for option",
                .unexpected_argument => "unexpected argument for option",
            };

            stderr.print("{s} -- {s}\n", .{ message, use.option }) catch {};
            std.process.exit(1);
        },
    };

    std.debug.print("{any}\n", .{config});
}
