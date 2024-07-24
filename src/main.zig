const std = @import("std");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const gpa = std.heap.page_allocator;
    var stdin = std.io.getStdIn().reader();
    var input: []u8 = "";
    const exit: []const u8 = "exit";
    var input_buffer = std.ArrayList(u8).init(gpa);
    defer input_buffer.deinit();

    while (!std.mem.eql(u8, exit, input)) {
        input_buffer.shrinkAndFree(0);

        const input_buffer_writer = input_buffer.writer();

        try stdin.streamUntilDelimiter(input_buffer_writer, '\n', null);
        input = input_buffer.items;

        if (std.mem.eql(u8, exit, input)) {
            break;
        }
        if (eq(input, "help") or eq(input, "h")) {
            // TODO: add a help mapping for all functions
        }

        const tokens = try tokenize(gpa, input);
        const value = try executeStack(gpa, tokens);

        try stdout.print("\n{s}\n\n", .{value});
        try bw.flush(); // don't forget to flush!
    }
    try stdout.print("\nAll Done\n", .{});
    try bw.flush(); // don't forget to flush!
}

const FuncType = enum {
    Plus,
    Minus,
};

const Token = union(enum) {
    func: FuncType,
    value: i64,
    execute: void,
    empty: void,
};

fn tokenize(allocator: anytype, string: []const u8) ![]Token {
    var i: u32 = 0;
    var string_buffer = std.ArrayList(u8).init(allocator);
    defer string_buffer.deinit();
    var tokens = std.ArrayList(Token).init(allocator);
    while (i < string.len) : (i += 1) {
        if (string[i] == ' ') {
            //Close and parse token
            try tokens.append(parseToken(string_buffer.items));
            string_buffer.shrinkAndFree(0);
        } else {
            //Add to string buffer
            try string_buffer.append(string[i]);
        }
    }
    if (string_buffer.items.len > 0) {
        try tokens.append(parseToken(string_buffer.items));
    }
    // TODO: Reverse the order of these items!
    // It might exist already as a function, otherwise make my own!
    return tokens.items;
}

fn eq(a: []u8, b: anytype) bool {
    return std.mem.eql(u8, a, @as([]const u8, b));
}

fn parseToken(single_token_string: []u8) Token {
    //std.debug.print("single_token_string: {s}\n", .{single_token_string});
    if (eq(single_token_string, ".")) {
        return Token.execute;
    } else if (eq(single_token_string, "+") or eq(single_token_string, "plus") or eq(single_token_string, "add")) {
        return Token{ .func = FuncType.Plus };
    } else if (eq(single_token_string, "-") or eq(single_token_string, "minus") or eq(single_token_string, "subtract")) {
        return Token{ .func = FuncType.Minus };
    } else if (std.fmt.parseInt(i64, single_token_string, 10) catch null) |v| {
        return Token{ .value = v };
    }
    return Token.empty;
}

fn executeStack(allocator: anytype, tokens: []const Token) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    var stack_func = std.ArrayList(FuncType).init(allocator);
    var stack_value = std.ArrayList(i64).init(allocator);
    for (tokens) |token| {
        switch (token) {
            .func => |func| {
                //std.debug.print("Found func {s}\n", .{@tagName(func)});
                try stack_func.append(func);
            },
            .value => |value| {
                //std.debug.print("Found value {d}\n", .{value});
                try stack_value.append(value);
            },
            .empty => {},
            .execute => {
                const func = stack_func.pop();
                try executeFunc(func, &stack_func, &stack_value);
            },
        }
    }
    var once = true;
    for (stack_func.items) |func| {
        if (!once) {
            try list.append(' ');
        }
        once = false;
        try list.appendSlice(@tagName(func));
    }
    if (list.items.len > 0) {
        try list.append('\n');
    }
    once = true;
    for (stack_value.items) |value| {
        if (!once) {
            try list.append(' ');
        }
        once = false;
        const str = try tokenToString(allocator, Token{ .value = value });
        try list.appendSlice(str);
    }
    return list.items;
}

fn tokenToString(allocator: anytype, token: Token) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    var buffer: [50]u8 = undefined;
    var formatted_string: []u8 = undefined;
    switch (token) {
        .func => |func| {
            formatted_string = try std.fmt.bufPrint(buffer[0..], "{s}", .{@tagName(func)});
        },
        .value => |value| {
            formatted_string = try std.fmt.bufPrint(buffer[0..], "{d}", .{value});
        },
        .empty => {
            formatted_string = try std.fmt.bufPrint(buffer[0..], "Empty", .{});
        },
        .execute => {
            formatted_string = try std.fmt.bufPrint(buffer[0..], "Execute", .{});
        },
    }
    try list.appendSlice(formatted_string);
    return list.items;
}

fn executeFunc(func: FuncType, stack_func: *std.ArrayList(FuncType), stack_value: *std.ArrayList(i64)) !void {
    _ = stack_func;
    switch (func) {
        .Plus => {
            const a = stack_value.pop();
            const b = stack_value.pop();
            try stack_value.append(a + b);
        },
        .Minus => {
            const a = stack_value.pop();
            const b = stack_value.pop();
            try stack_value.append(a - b);
        },
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
