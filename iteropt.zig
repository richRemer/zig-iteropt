const std = @import("std");
const Type = std.builtin.Type;

fn sum_lens(comptime strings: []const [:0]const u8) usize {
    comptime var sum: usize = 0;
    for (strings) |string| sum += string.len;
    return sum;
}

pub fn Opt(
    comptime shorts: [:0]const u8,
    comptime longs: []const [:0]const u8,
) type {
    const fields_max_len = shorts.len + longs.len;
    const names_max_len = sum_lens(longs) + longs.len;

    comptime var i = 0;
    comptime var names_offset = 0;
    comptime var names_buffer: [names_max_len]u8 = undefined;
    comptime var enum_fields: [fields_max_len]Type.EnumField = undefined;
    comptime var union_fields: [fields_max_len]Type.UnionField = undefined;

    for (shorts) |ch| {
        switch (ch) {
            '0'...'9', 'a'...'z', 'A'...'Z' => {
                const has_arg = shorts.len > i and shorts[i + 1] == ':';
                const T = if (has_arg) []const u8 else void;

                enum_fields[i] = Type.EnumField{
                    .name = &[1:0]u8{ch},
                    .value = i,
                };

                union_fields[i] = Type.UnionField{
                    .name = &[1:0]u8{ch},
                    .type = T,
                    .alignment = @alignOf(T),
                };

                i += 1;
            },
            ':' => {},
            else => @compileError("short option '" ++ ch ++ "' invalid"),
        }
    }

    for (longs) |long| {
        const has_arg = long[long.len - 1] == ':';
        const name_len = if (has_arg) long.len - 1 else long.len;
        const T = if (has_arg) []const u8 else void;

        @memcpy(names_buffer[names_offset..][0..name_len], long[0..name_len]);
        names_buffer[names_offset + name_len] = 0;

        const c_name: [*c]u8 = @ptrCast(names_buffer[names_offset..]);
        const name: [:0]const u8 = std.mem.sliceTo(c_name, 0);

        enum_fields[i] = Type.EnumField{
            .name = name,
            .value = i,
        };

        union_fields[i] = Type.UnionField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
        };

        i += 1;
        names_offset += name_len + 1;
    }

    return @Type(.{
        .@"union" = .{
            .layout = .auto,
            .fields = union_fields[0..i],
            .decls = &[0]Type.Declaration{},
            .tag_type = @Type(.{
                .@"enum" = .{
                    .tag_type = u8,
                    .fields = enum_fields[0..i],
                    .decls = &[0]Type.Declaration{},
                    .is_exhaustive = true,
                },
            }),
        },
    });
}

pub fn OptArg(comptime Option: type) type {
    return union(enum) {
        argument: []const u8,
        option: Option,
        terminator: void,
        usage: Usage,
    };
}

pub fn OptIterator(
    comptime shorts: [:0]const u8,
    comptime longs: []const [:0]const u8,
) type {
    return struct {
        args: *std.process.ArgIterator,
        arg: ?[]const u8 = null,
        terminated: bool = false,
        offset: usize = 0,

        pub const Option = Opt(shorts, longs);
        pub const OptionArgument = OptArg(Option);

        pub fn init(args: *std.process.ArgIterator) @This() {
            return .{
                .args = args,
                .arg = args.next(),
            };
        }

        pub fn next(this: *@This()) ?OptionArgument {
            if (this.arg) |arg| {
                if (this.terminated) {
                    this.arg = this.args.next();
                    return argument(Option, arg);
                } else if (std.mem.eql(u8, "--", arg)) {
                    this.arg = this.args.next();
                    this.terminated = true;
                    return terminator(Option);
                } else if (std.mem.eql(u8, "--", arg[0..2])) {
                    return this.nextLong(arg);
                } else if (arg[0] == '-') {
                    return this.nextShort(arg);
                } else {
                    this.arg = this.args.next();
                    return argument(Option, arg);
                }
            } else {
                return null;
            }
        }

        // TODO: handle bad data and other errors
        fn nextLong(this: *@This(), arg: []const u8) OptionArgument {
            defer this.arg = this.args.next();

            const fields = @typeInfo(Option).@"union".fields;
            var name: []const u8 = arg[2..];
            var value: ?[]const u8 = null;

            if (std.mem.indexOfScalar(u8, arg, '=')) |index| {
                name = arg[2..index];
                value = arg[index + 1 ..];
            }

            inline for (fields) |f| if (std.mem.eql(u8, name, f.name)) {
                if (void == std.meta.TagPayloadByName(Option, f.name)) {
                    if (value) |val| {
                        return usage(Option, .unexpected_argument, arg, f.name, val);
                    } else {
                        return flag(Option, f.name);
                    }
                }

                value = value orelse this.args.next();

                if (value) |val| {
                    return option(Option, f.name, val);
                } else {
                    return usage(Option, .missing_argument, arg, f.name, null);
                }
            };

            return usage(Option, .unknown_option, arg, name, value);
        }

        // TODO: handle bad data and other errors
        fn nextShort(this: *@This(), arg: []const u8) OptionArgument {
            // skip initial '-'
            if (this.offset == 0) this.offset = 1;

            const fields = @typeInfo(Option).@"union".fields;
            const name = arg[this.offset..][0..1];
            var value: ?[]const u8 = null;

            inline for (fields) |f| if (std.mem.eql(u8, name, f.name)) {
                if (void == std.meta.TagPayloadByName(Option, f.name)) {
                    if (this.offset + 1 == arg.len) {
                        this.offset = 0;
                        this.arg = this.args.next();
                    } else {
                        this.offset += 1;
                    }

                    return flag(Option, f.name);
                } else {
                    const rest = arg[this.offset + 1 ..];

                    value = if (rest.len > 0) rest else this.args.next();
                    this.offset = 0;
                    this.arg = this.args.next();

                    if (value) |val| {
                        return option(Option, f.name, val);
                    } else {
                        return usage(Option, .missing_argument, arg, name, null);
                    }
                }
            };

            return usage(Option, .unknown_option, arg, name, value);
        }
    };
}

pub const Usage = struct {
    @"error": UsageError,
    argument: []const u8,
    option: []const u8,
    value: ?[]const u8,
};

pub const UsageError = enum(u8) {
    unknown_option,
    missing_argument,
    unexpected_argument,
};

fn argument(comptime Option: type, arg: []const u8) OptArg(Option) {
    return .{ .argument = arg };
}

fn flag(comptime Option: type, comptime opt: []const u8) OptArg(Option) {
    return .{ .option = @unionInit(Option, opt, undefined) };
}

fn option(
    comptime Option: type,
    comptime opt: []const u8,
    val: []const u8,
) OptArg(Option) {
    return .{ .option = @unionInit(Option, opt, val) };
}

fn terminator(comptime Option: type) OptArg(Option) {
    return .{ .terminator = undefined };
}

fn usage(
    comptime Option: type,
    err: UsageError,
    arg: []const u8,
    opt: []const u8,
    val: ?[]const u8,
) OptArg(Option) {
    return .{ .usage = .{
        .@"error" = err,
        .argument = arg,
        .option = opt,
        .value = val,
    } };
}

test "simple positional arguments" {
    const Iterator = OptIterator("vqo:", &.{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_case = try TestCase.init(&arena, &.{ "cmd", "foo", "bar" });
    defer test_case.deinit();

    var args = std.process.ArgIterator.init();
    var it = Iterator.init(&args);

    const first_arg = it.next().?;
    const second_arg = it.next().?;
    const third_arg = it.next().?;
    const end = it.next();

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(first_arg));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(first_arg));
    try std.testing.expectEqualSlices(u8, "cmd", first_arg.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(second_arg));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(second_arg));
    try std.testing.expectEqualSlices(u8, "foo", second_arg.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(third_arg));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(third_arg));
    try std.testing.expectEqualSlices(u8, "bar", third_arg.argument);

    try std.testing.expectEqual(null, end);
}

test "short options" {
    const Iterator = OptIterator("vqo:", &.{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_case = try TestCase.init(&arena, &.{ "cmd", "-v", "-qo", "file" });
    defer test_case.deinit();

    var args = std.process.ArgIterator.init();
    var it = Iterator.init(&args);

    const cmd = it.next().?;
    const first_opt = it.next().?;
    const second_opt = it.next().?;
    const third_opt = it.next().?;
    const end = it.next();

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(cmd));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(cmd));
    try std.testing.expectEqualSlices(u8, "cmd", cmd.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(first_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(first_opt));
    try std.testing.expectEqualSlices(u8, "v", @tagName(first_opt.option));

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(second_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(second_opt));
    try std.testing.expectEqualSlices(u8, "q", @tagName(second_opt.option));

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(third_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(third_opt));
    try std.testing.expectEqualSlices(u8, "o", @tagName(third_opt.option));
    try std.testing.expectEqualSlices(u8, "file", third_opt.option.o);

    try std.testing.expectEqual(null, end);
}

test "short options with value" {
    const Iterator = OptIterator("vqo:", &.{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_case = try TestCase.init(&arena, &.{ "cmd", "-vofile", "-q" });
    defer test_case.deinit();

    var args = std.process.ArgIterator.init();
    var it = Iterator.init(&args);

    const cmd = it.next().?;
    const first_opt = it.next().?;
    const second_opt = it.next().?;
    const third_opt = it.next().?;
    const end = it.next();

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(cmd));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(cmd));
    try std.testing.expectEqualSlices(u8, "cmd", cmd.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(first_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(first_opt));
    try std.testing.expectEqualSlices(u8, "v", @tagName(first_opt.option));

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(second_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(second_opt));
    try std.testing.expectEqualSlices(u8, "o", @tagName(second_opt.option));
    try std.testing.expectEqualSlices(u8, "file", second_opt.option.o);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(third_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(third_opt));
    try std.testing.expectEqualSlices(u8, "q", @tagName(third_opt.option));

    try std.testing.expectEqual(null, end);
}

test "long options" {
    const Iterator = OptIterator("", &.{ "flag", "with-val:" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_case = try TestCase.init(&arena, &.{ "cmd", "--flag", "--with-val", "val" });
    defer test_case.deinit();

    var args = std.process.ArgIterator.init();
    var it = Iterator.init(&args);

    const cmd = it.next().?;
    const first_opt = it.next().?;
    const second_opt = it.next().?;
    const end = it.next();

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(cmd));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(cmd));
    try std.testing.expectEqualSlices(u8, "cmd", cmd.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(first_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(first_opt));
    try std.testing.expectEqualSlices(u8, "flag", @tagName(first_opt.option));

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(second_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(second_opt));
    try std.testing.expectEqualSlices(u8, "with-val", @tagName(second_opt.option));
    try std.testing.expectEqualSlices(u8, "val", second_opt.option.@"with-val");

    try std.testing.expectEqual(null, end);
}

test "long options with value" {
    const Iterator = OptIterator("", &.{ "flag", "with-val:" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_case = try TestCase.init(&arena, &.{ "cmd", "--flag", "--with-val=val" });
    defer test_case.deinit();

    var args = std.process.ArgIterator.init();
    var it = Iterator.init(&args);

    const cmd = it.next().?;
    const first_opt = it.next().?;
    const second_opt = it.next().?;
    const end = it.next();

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(cmd));
    try std.testing.expectEqualSlices(u8, "argument", @tagName(cmd));
    try std.testing.expectEqualSlices(u8, "cmd", cmd.argument);

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(first_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(first_opt));
    try std.testing.expectEqualSlices(u8, "flag", @tagName(first_opt.option));

    try std.testing.expectEqual(Iterator.OptionArgument, @TypeOf(second_opt));
    try std.testing.expectEqualSlices(u8, "option", @tagName(second_opt));
    try std.testing.expectEqualSlices(u8, "with-val", @tagName(second_opt.option));
    try std.testing.expectEqualSlices(u8, "val", second_opt.option.@"with-val");

    try std.testing.expectEqual(null, end);
}

const TestCase = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    argv: [][*:0]u8,
    saved_argv: [][*:0]u8,

    pub fn init(
        arena: *std.heap.ArenaAllocator,
        args: []const [:0]const u8,
    ) !TestCase {
        const allocator = arena.allocator();
        const argv = try allocator.alloc([*:0]u8, args.len);

        for (args, 0..) |arg, i| {
            argv[i] = try allocator.dupeZ(u8, arg);
        }

        const saved_argv = std.os.argv;
        std.os.argv = argv;

        return .{
            .arena = arena,
            .allocator = allocator,
            .argv = argv,
            .saved_argv = saved_argv,
        };
    }

    pub fn deinit(this: TestCase) void {
        std.os.argv = this.saved_argv;
    }
};
