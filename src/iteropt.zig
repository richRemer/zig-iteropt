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

pub fn OptArg(comptime OptType: type) type {
    return union(enum) {
        argument: []const u8,
        option: OptType,
        terminator: void,
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
                    return .{ .argument = arg };
                } else if (std.mem.eql(u8, "--", arg)) {
                    this.arg = this.args.next();
                    this.terminated = true;
                    return .{ .terminator = undefined };
                } else if (std.mem.eql(u8, "--", arg[0..2])) {
                    return this.nextLong(arg);
                } else if (arg[0] == '-') {
                    return this.nextShort(arg);
                } else {
                    this.arg = this.args.next();
                    return .{ .argument = arg };
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
                    return .{ .option = @unionInit(Option, f.name, undefined) };
                } else if (value == null) {
                    value = this.args.next();
                }

                return .{ .option = @unionInit(Option, f.name, value.?) };
            };

            // TODO: return error somehow
            unreachable;
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

                    return .{ .option = @unionInit(Option, f.name, undefined) };
                } else {
                    const rest = arg[this.offset + 1 ..];

                    value = if (rest.len > 0) rest else this.args.next();
                    this.offset = 0;
                    this.arg = this.args.next();
                    return .{ .option = @unionInit(Option, f.name, value.?) };
                }
            };

            // TODO: return error somehow
            unreachable;
        }
    };
}
