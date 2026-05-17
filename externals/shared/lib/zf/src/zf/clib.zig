const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

/// rank a given haystack against a slice of needles
export fn rank(
    haystack: [*:0]const u8,
    needles: [*]const [*:0]const u8,
    num_needles: usize,
    case_sensitive: bool,
    plain: bool,
) f64 {
    const string = std.mem.span(haystack);
    const filename = if (plain) null else std.fs.path.basename(string);

    var total_rank: f64 = 0;
    var index: usize = 0;
    while (index < num_needles) : (index += 1) {
        const needle = std.mem.span(needles[index]);
        const strict_path = filter.hasSeparator(needle);
        if (filter.rankNeedle(string, filename, needle, case_sensitive, strict_path)) |r| {
            total_rank += r;
        } else return -1.0;
    }
    return total_rank;
}

/// rank a given haystack against a single needle
export fn rankNeedle(
    haystack: [*:0]const u8,
    filename: ?[*:0]const u8,
    needle: [*:0]const u8,
    case_sensitive: bool,
    strict_path: bool,
) f64 {
    const string = std.mem.span(haystack);
    const name = if (filename != null) std.mem.span(filename) else null;
    const n = std.mem.span(needle);
    if (filter.rankNeedle(string, name, n, case_sensitive, strict_path)) |r| {
        return r;
    } else return -1.0;
}

test "rank exported C library interface" {
    {
        const needles: [2][*:0]const u8 = .{ "a", "z" };
        try testing.expect(rank("abcdefg", &needles, 2, false, false) == -1);
    }
    {
        const needles: [2][*:0]const u8 = .{ "a", "b" };
        try testing.expect(rank("abcdefg", &needles, 2, false, false) != -1);
    }
    {
        const needles: [2][*:0]const u8 = .{ "a", "B" };
        try testing.expect(rank("abcdefg", &needles, 2, true, false) == -1);
    }
    {
        const needles: [2][*:0]const u8 = .{ "a", "B" };
        try testing.expect(rank("aBcdefg", &needles, 2, true, false) != -1);
    }
    {
        const needles: [1][*:0]const u8 = .{"zig"};
        try testing.expect(rank("a/path/to/file", &needles, 2, false, false) == -1);
    }
    {
        const needles: [2][*:0]const u8 = .{ "path", "file" };
        try testing.expect(rank("a/path/to/file", &needles, 2, false, false) != -1);
    }

    try testing.expect(rankNeedle("abcdefg", null, "a", false, false) != -1);
    try testing.expect(rankNeedle("abcdefg", null, "z", false, false) == -1);
    try testing.expect(rankNeedle("abcdefG", null, "G", true, false) != -1);
    try testing.expect(rankNeedle("abcdefg", null, "A", true, false) == -1);
    try testing.expect(rankNeedle("a/path/to/file", "file", "file", false, false) != -1);
    try testing.expect(rankNeedle("a/path/to/file", "file", "zig", false, false) == -1);

    // zero length haystacks and needles
    {
        const needles: [1][*:0]const u8 = .{"a"};
        try testing.expect(rank("", &needles, 1, false, false) == -1);
    }
    try testing.expect(rankNeedle("", null, "a", false, false) == -1);
    {
        const needles: [1][*:0]const u8 = .{""};
        try testing.expect(rank("a", &needles, 1, false, false) == -1);
    }
    try testing.expect(rankNeedle("a", null, "", false, false) == -1);
}

export fn highlight(
    haystack: [*:0]const u8,
    needles: [*]const [*:0]const u8,
    needles_len: usize,
    case_sensitive: bool,
    plain: bool,
    matches: [*]usize,
    matches_len: usize,
) usize {
    const string = std.mem.span(haystack);
    const filename = if (plain) null else std.fs.path.basename(string);
    var matches_slice = matches[0..matches_len];

    var index: usize = 0;
    var needle_index: usize = 0;
    while (needle_index < needles_len) : (needle_index += 1) {
        const needle = std.mem.span(needles[needle_index]);
        const strict_path = filter.hasSeparator(needle);
        const matched = filter.highlightNeedle(string, filename, needle, case_sensitive, strict_path, matches_slice[index..]);
        index += matched.len;
    }

    return index;
}

export fn highlightNeedle(
    haystack: [*:0]const u8,
    filename: ?[*:0]const u8,
    needle: [*:0]const u8,
    case_sensitive: bool,
    strict_path: bool,
    matches: [*]usize,
    matches_len: usize,
) usize {
    const string = std.mem.span(haystack);
    const name = if (filename != null) std.mem.span(filename) else null;
    const n = std.mem.span(needle);
    const matches_slice = matches[0..matches_len];
    const matched = filter.highlightNeedle(string, name, n, case_sensitive, strict_path, matches_slice);
    return matched.len;
}

fn testHighlight(
    expectedMatches: []const usize,
    haystack: [*:0]const u8,
    needles: []const [*:0]const u8,
    case_sensitive: bool,
    plain: bool,
    matches_buf: []usize,
) !void {
    const len = highlight(haystack, needles.ptr, needles.len, case_sensitive, plain, matches_buf.ptr, matches_buf.len);
    try testing.expectEqualSlices(usize, expectedMatches, matches_buf[0..len]);
}

test "highlight exported C library interface" {
    var matches_buf: [128]usize = undefined;

    try testHighlight(&.{ 0, 5 }, "abcdef", &.{ "a", "f" }, false, false, &matches_buf);
    try testHighlight(&.{ 0, 5 }, "abcdeF", &.{ "a", "F" }, true, false, &matches_buf);
    try testHighlight(&.{ 2, 3, 4, 5, 10, 11, 12, 13 }, "a/path/to/file", &.{ "path", "file" }, false, false, &matches_buf);

    var len = highlightNeedle("abcdef", null, "a", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{0}, matches_buf[0..len]);
    len = highlightNeedle("abcdeF", null, "F", true, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{5}, matches_buf[0..len]);
    len = highlightNeedle("a/path/to/file", "file", "file", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{ 10, 11, 12, 13 }, matches_buf[0..len]);

    // highlights with basename trailing slashes
    len = highlightNeedle("s/", "s", "s", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{0}, matches_buf[0..len]);
    len = highlightNeedle("/this/is/path/not/a/file/", "file", "file", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{ 20, 21, 22, 23 }, matches_buf[0..len]);

    // disconnected highlights
    try testHighlight(&.{ 0, 2, 3 }, "ababab", &.{"aab"}, false, false, &matches_buf);
    try testHighlight(&.{ 6, 8, 9 }, "abbbbbabab", &.{"aab"}, false, false, &matches_buf);
    try testHighlight(&.{ 0, 2, 6 }, "abcdefg", &.{"acg"}, false, false, &matches_buf);
    try testHighlight(&.{ 2, 3, 4, 5, 9, 10 }, "__init__.py", &.{"initpy"}, false, false, &matches_buf);

    // small buffer to ensure highlighting doesn't go out of range when the needles overflow
    var small_buf: [4]usize = undefined;
    try testHighlight(&.{ 0, 1, 2, 3 }, "abcd", &.{ "ab", "cd", "abcd" }, false, false, &small_buf);
    try testHighlight(&.{ 0, 1, 2, 1 }, "wxyz", &.{ "wxy", "xyz" }, false, false, &small_buf);

    // zero length haystacks and needles
    try testHighlight(&.{}, "", &.{"a"}, false, false, &matches_buf);
    len = highlightNeedle("", null, "a", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{}, matches_buf[0..len]);
    try testHighlight(&.{}, "a", &.{""}, false, false, &matches_buf);
    len = highlightNeedle("a", null, "", false, false, &matches_buf, matches_buf.len);
    try testing.expectEqualSlices(usize, &.{}, matches_buf[0..len]);
}
