const std = @import("std");

pub const Token = union(enum) {
    string: []const u8,
    integer: []const u8,
    start_list,
    start_dict,
    terminator,
};

pub const ParseError = error{ OutOfMemory, InvalidCharacter, NotImplemented, Overflow };

pub fn Parsed(comptime T: type) type {
    return struct {
        value: T,
        arena: std.heap.ArenaAllocator,

        pub fn deinit(self: @This()) void {
            self.arena.deinit();
        }
    };
}

const State = enum {
    value,
    string,
    integer,
};

pub const Scanner = struct {
    state: State = .value,
    input: []const u8 = "",
    cursor: usize = 0,
    value_start: usize = undefined,
    allocator: std.mem.Allocator,

    fn takeValueSlice(self: *Scanner) []const u8 {
        const slice = self.input[self.value_start..self.cursor];
        self.value_start = self.cursor;
        return slice;
    }

    pub fn next(self: *Scanner) !Token {
        state_loop: while (true) {
            switch (self.state) {
                .value => {
                    switch (self.input[self.cursor]) {
                        '0'...'9' => {
                            self.state = .string;
                            self.value_start = self.cursor;
                            continue :state_loop;
                        },
                        'i' => {
                            self.cursor += 1;
                            self.state = .integer;
                            self.value_start = self.cursor;
                            continue :state_loop;
                        },
                        'd' => {
                            self.cursor += 1;
                            return Token.start_dict;
                        },
                        'l' => {
                            self.cursor += 1;
                            return Token.start_list;
                        },
                        'e' => {
                            self.cursor += 1;
                            return Token.terminator;
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .integer => {
                    while (self.cursor < self.input.len) : (self.cursor += 1) {
                        if (self.input[self.cursor] == 'e') {
                            const slice = self.takeValueSlice();
                            const result = Token{ .integer = slice };
                            self.cursor += 1;
                            self.state = .value;
                            return result;
                        }
                    }
                    return error.NotImplemented;
                },
                .string => {
                    while (self.cursor < self.input.len and self.input[self.cursor] != ':') : (self.cursor += 1) {}
                    const lenSlice = self.takeValueSlice();
                    const len = try std.fmt.parseInt(usize, lenSlice, 10);

                    self.cursor += 1; // skip `:`

                    self.value_start = self.cursor;
                    self.cursor += len;
                    const slice = self.takeValueSlice();

                    self.state = .value;

                    return Token{ .string = slice };
                },
            }
        }
    }
};

pub fn innerParse(comptime T: type, allocator: std.mem.Allocator, scanner: *Scanner) !T {
    switch (@typeInfo(T)) {
        .Int => {
            const intSlice = try scanner.next();
            if (intSlice != Token.integer) return error.UnexpectedToken;
            const int = try std.fmt.parseInt(T, intSlice, 10);
            return int;
        },
        .Struct => |info| {
            if (info.is_tuple) {
                return error.NotImplemented;
            }

            if (.start_dict != try scanner.next()) return error.UnexpectedToken;

            var t: T = undefined;

            while (true) {
                const keyToken = try scanner.next();
                const keyName = switch (keyToken) {
                    .string => |s| s,
                    .terminator => return t,
                    else => return error.UnexpectedToken,
                };

                inline for (info.fields) |field| {
                    if (std.mem.eql(u8, field.name, keyName)) {
                        @field(t, field.name) = try innerParse(field.type, allocator, scanner);
                        break;
                    }
                }
            }

            return error.NotImplemented;
        },
        .Array => |info| {
            if (info.child != u8) return error.UnexpectedToken;
            var t: T = undefined;
            const token = try scanner.next();
            const str = switch (token) {
                .string => |s| s,
                else => return error.UnexpectedToken,
            };
            @memcpy(t[0..str.len], str);
            return t;
        },
        .Pointer => |info| {
            if (info.child != u8) return error.UnexpectedToken;
            const token = try scanner.next();
            const str = switch (token) {
                .string => |s| s,
                else => return error.UnexpectedToken,
            };
            var list = std.ArrayList(u8).init(allocator);
            try list.appendSlice(str);
            return list.toOwnedSlice();
        },
        // else => {
        //     return error.NotImplemented;
        // },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
}
//
// pub fn parse(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !Parsed(T) {
//     var parsed = Parsed(T){
//         .value = undefined,
//         .arena = std.heap.ArenaAllocator.init(allocator),
//     };
//     errdefer parsed.arena.deinit();
//
//     const scanner = Scanner{
//         .input = input,
//         .allocator = parsed.arena.allocator(),
//     };
//
//     parsed.value = try innerParse(T, scanner.arena.allocator(), scanner);
//
//     return parsed;
// }
