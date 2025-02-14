const std = @import("std");

pub const Token = union(enum) {
    string: []const u8,
    integer: []const u8,
    start_list,
    start_dict,
    terminator,
};

pub const TokenType = enum {
    string,
    integer,
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

    pub fn peekToken(self: *Scanner) !TokenType {
        switch (self.input[self.cursor]) {
            '0'...'9' => return .string,
            'i' => return .integer,
            'd' => return .start_dict,
            'l' => return .start_list,
            'e' => return .terminator,
            else => return error.UnexpectedToken,
        }
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

                            if (slice.len == 0) {
                                // TODO: error here, expected at least 1 digit
                            }

                            const result = Token{ .integer = slice };
                            self.cursor += 1;
                            self.state = .value;
                            return result;
                        }
                    }
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
            const token = try scanner.next();
            if (token != Token.integer) return error.UnexpectedToken;
            const int = try std.fmt.parseInt(T, token.integer, 10);
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
        .Pointer => |ptr| {
            switch (ptr.size) {
                .One => {
                    const value: *ptr.child = try allocator.create(ptr.child);
                    value.* = try innerParse(ptr.child, allocator, scanner);
                    return value;
                },
                .Slice => {
                    switch (try scanner.peekToken()) {
                        .string => {
                            if (ptr.child != u8) {
                                return error.UnexpectedToken;
                            }

                            const token = try scanner.next();
                            return token.string;
                        },
                        .start_list => {
                            if (.start_list != try scanner.next()) return error.UnexpectedToken; // skip `l`
                            var list = std.ArrayList(ptr.child).init(allocator);

                            while (true) {
                                switch (try scanner.peekToken()) {
                                    .terminator => break,
                                    else => {},
                                }

                                const listItem = try innerParse(ptr.child, allocator, scanner);
                                try list.append(listItem);
                            }

                            if (.terminator != try scanner.next()) return error.UnexpectedToken; // skip `e`

                            return try list.toOwnedSlice();
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                else => @compileError("Unable to parse into type Pointer of size '" ++ ptr.size ++ "'"),
            }
        },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn parse(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !Parsed(T) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var scanner = Scanner{
        .input = input,
        .allocator = arena.allocator(),
    };

    const value = try innerParse(T, arena.allocator(), &scanner);

    return Parsed(T){
        .arena = arena,
        .value = value,
    };
}

test "parse integer" {
    const result = try parse(i64, std.testing.allocator, "i5e");
    defer result.deinit();

    try std.testing.expectEqual(5, result.value);
}

test "parse negative integer" {
    const result = try parse(i64, std.testing.allocator, "i-5e");
    defer result.deinit();

    try std.testing.expectEqual(-5, result.value);
}

test "parse nil integer" {
    const result = try parse(i64, std.testing.allocator, "ie");
    defer result.deinit();

    try std.testing.expectEqual(0, result.value);
}

test "parse string" {
    const result = try parse([]const u8, std.testing.allocator, "5:hello");
    defer result.deinit();

    try std.testing.expectEqualStrings("hello", result.value);
}

test "parse empty string" {
    const result = try parse([]const u8, std.testing.allocator, "0:");
    defer result.deinit();

    try std.testing.expectEqualStrings("", result.value);
}

test "parse empty list" {
    const result = try parse([]const i64, std.testing.allocator, "le");
    defer result.deinit();

    try std.testing.expectEqualSlices(i64, &.{}, result.value);
}

test "parse single item list" {
    const result = try parse([]const i64, std.testing.allocator, "li99999ee");
    defer result.deinit();

    try std.testing.expectEqualSlices(i64, &.{99999}, result.value);
}

test "parse multi item list" {
    const result = try parse([]const i64, std.testing.allocator, "li123ei456ei789ee");
    defer result.deinit();

    try std.testing.expectEqualSlices(i64, &.{ 123, 456, 789 }, result.value);
}
