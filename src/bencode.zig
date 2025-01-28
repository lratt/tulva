const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    list: std.ArrayList(Value),
    dict: std.StringHashMap(Value),
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

const Parser = struct {
    input: []const u8,
    cursor: usize,
    allocator: std.mem.Allocator,

    fn parseInteger(self: *Parser) ParseError!Value {
        self.cursor += 1; // skip 'i'

        const start = self.cursor;

        while (self.input[self.cursor] != 'e') : (self.cursor += 1) {}

        const intBuffer = self.input[start..self.cursor];
        const value = try std.fmt.parseInt(i64, intBuffer, 10);

        self.cursor += 1; // skip 'e'

        return Value{ .integer = value };
    }

    fn parseString(self: *Parser) ParseError!Value {
        var lenBuffer = std.ArrayList(u8).init(self.allocator);
        defer lenBuffer.deinit();

        while (self.input[self.cursor] != ':') : (self.cursor += 1) {
            try lenBuffer.append(self.input[self.cursor]);
        }

        const len = try std.fmt.parseInt(usize, lenBuffer.items, 10);

        self.cursor += 1; // skip colon
        const start = self.cursor;
        self.cursor += len;

        return Value{ .string = self.input[start..self.cursor] };
    }

    fn parseList(self: *Parser) ParseError!Value {
        self.cursor += 1; // skip 'l'

        var list = std.ArrayList(Value).init(self.allocator);

        while (self.input[self.cursor] != 'e') {
            const val = try self.parseValue();
            try list.append(val);
        }

        self.cursor += 1; // skip 'e'

        return Value{ .list = list };
    }

    fn parseDict(self: *Parser) ParseError!Value {
        self.cursor += 1; // skip 'd'

        var dict = std.StringHashMap(Value).init(self.allocator);

        while (self.input[self.cursor] != 'e') {
            const key = try self.parseString();
            const val = try self.parseValue();
            try dict.put(key.string, val);
        }

        self.cursor += 1; // skip 'e'

        return Value{ .dict = dict };
    }

    fn parseValue(self: *Parser) ParseError!Value {
        switch (self.input[self.cursor]) {
            '0'...'9' => {
                return try self.parseString();
            },
            'i' => {
                return try self.parseInteger();
            },
            'l' => {
                return try self.parseList();
            },
            'd' => {
                return try self.parseDict();
            },
            else => {
                return error.NotImplemented;
            },
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Parsed(Value) {
    var parsed = Parsed(Value){
        .value = undefined,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    errdefer parsed.arena.deinit();

    var parser = Parser{
        .input = input,
        .cursor = 0,
        .allocator = parsed.arena.allocator(),
    };

    parsed.value = try parser.parseValue();

    return parsed;
}
