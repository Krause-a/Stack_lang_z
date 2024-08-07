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
            try printHelp(stdout);
            try bw.flush(); // don't forget to flush!
            continue;
        }

        const tokens = try tokenize(gpa, input);
        const value = try executeStack(gpa, tokens);

        try stdout.print("\n{s}\n\n", .{value});
        try bw.flush(); // don't forget to flush!
    }
    try stdout.print("\nAll Done\n", .{});
    try bw.flush(); // don't forget to flush!
}

fn printHelp(writer: anytype) !void {
    try writer.print("Spaces seperate inputs. Stacks are added to right to left. Ex: \". + 14 28\" will output 42.\n", .{});
    try writer.print("[[:digit:]]: a value to be put on the value stack.\n", .{});
    try writer.print("plus: pop 2 values from the value stack. Add them and put that value into the value stack.\n", .{});
    try writer.print("minus: pop 2 values from the value stack. Subtract them and put that value into the value stack.\n", .{});
    try writer.print(".: pop and execute the top function from the function stack.\n", .{});
    try writer.print("repeat: pop the top function and the top value (N) and execute the function N times.\n", .{});
    try writer.print("duplicatev: duplicate the top value of the value stack.\n", .{});
    try writer.print("duplicatef: duplicate the top function of the function stack.(Broken sometimes)\n", .{});
    try writer.print("\n\n", .{});
}

const StackType = enum {
    Func,
    Value,
};

const StackPopCount = struct {
    func: u8,
    value: u8,
};

const FuncType = enum {
    Plus,
    Minus,
    DuplicateValue,
    DuplicateFunc,
    Repeat,

    fn getPopCount(self: FuncType) StackPopCount {
        var count_func: u8 = 0;
        var count_value: u8 = 0;
        switch (self) {
            .Plus, .Minus => count_value = 2,
            .DuplicateValue => count_value = 1,
            .DuplicateFunc => count_func = 1,
            .Repeat => {
                count_value = 1;
                count_func = 1;
            },
        }
        return StackPopCount{ .func = count_func, .value = count_value };
    }
};

const Token = union(enum) {
    func: FuncType,
    value: i64,
    execute: void,
    empty: void,
};

fn tokenize(allocator: anytype, string: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    var token_iterator = std.mem.tokenizeSequence(u8, string, " ");
    while (token_iterator.next()) |item| {
        try tokens.append(parseToken(item));
    }
    reverse(tokens.items);
    return tokens.items;
}

fn reverse(slice: anytype) void {
    var i: u64 = 0;
    while (i < slice.len / 2) : (i += 1) {
        const temp = slice[i];
        slice[i] = slice[slice.len - 1 - i];
        slice[slice.len - 1 - i] = temp;
    }
}

fn eq(a: []const u8, b: anytype) bool {
    return std.mem.eql(u8, a, @as([]const u8, b));
}

fn parseToken(single_token_string: []const u8) Token {
    //std.debug.print("single_token_string: {s}\n", .{single_token_string});
    if (eq(single_token_string, "repeat")) {
        return Token{ .func = FuncType.Repeat };
    } else if (eq(single_token_string, "duplicatev")) {
        return Token{ .func = FuncType.DuplicateValue };
    } else if (eq(single_token_string, "duplicatef")) {
        return Token{ .func = FuncType.DuplicateFunc };
    } else if (eq(single_token_string, ".")) {
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
                try executeFunc(allocator, func, &stack_func, &stack_value);
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

fn executeFunc(allocator: anytype, func: FuncType, stack_func: *std.ArrayList(FuncType), stack_value: *std.ArrayList(i64)) !void {
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
        .DuplicateFunc => {
            const a = stack_func.pop();
            try stack_func.append(a);
            try stack_func.append(a);
        },
        .DuplicateValue => {
            const a = stack_value.pop();
            try stack_value.append(a);
            try stack_value.append(a);
        },
        .Repeat => {
            // TODO: Duplicatef works wrong when combined with repeat.
            var repeat_count = stack_value.pop();
            if (repeat_count > 1) {
                const repeat_func = stack_func.pop();
                var list_f = std.ArrayList(FuncType).init(allocator);
                // var list_v = std.ArrayList(i64).init(allocator);
                // Take them both off. put them back on exe, put them back on exe...
                var pop_count = repeat_func.getPopCount();

                while (pop_count.func > 0) : (pop_count.func -= 1) {
                    const f = stack_func.pop();
                    const pop_count_each = f.getPopCount();
                    pop_count.func += pop_count_each.func;
                    pop_count.value += pop_count_each.value;

                    try list_f.append(f);
                }

                // while (pop_count.value > 0) : (pop_count.value -= 1) {
                //     try list_v.append(stack_value.pop());
                // }
                reverse(list_f.items);
                // reverse(list_v.items);

                while (repeat_count > 0) : (repeat_count -= 1) {
                    for (list_f.items) |func_f| {
                        try stack_func.append(func_f);
                    }
                    // for (list_v.items) |func_v| {
                    //     try stack_value.append(func_v);
                    // }
                    try executeFunc(allocator, repeat_func, stack_func, stack_value);
                }
            } else {
                try executeFunc(allocator, stack_func.pop(), stack_func, stack_value);
            }
        },
    }
}

// TODO: Try out writing tests
