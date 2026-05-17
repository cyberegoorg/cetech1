//! zf.zig
//! The zf fuzzy finding algorithm
//! Inspired by https://github.com/garybernhardt/selecta

const filter = @import("filter.zig");
const std = @import("std");
const testing = std.testing;

test {
    _ = @import("clib.zig");
    _ = @import("filter.zig");
}

pub const RankOptions = struct {
    /// Set to false for case insensitive ranking.
    case_sensitive: bool = true,

    /// If true, the zf filepath algorithms are disabled (useful for matching arbitrary strings)
    plain: bool = false,
};

/// rank a given haystack against a slice of needles
pub fn rank(
    haystack: []const u8,
    needles: []const []const u8,
    opts: RankOptions,
) ?f64 {
    const filename = if (opts.plain) null else std.fs.path.basename(haystack);

    // the haystack must contain all of the characters (in order) in each needle.
    // each needle's rank is summed. if any needle does not match the haystack is ignored.
    var sum: f64 = 0;
    for (needles) |needle| {
        const strict_path = !opts.plain and filter.hasSeparator(needle);
        if (filter.rankNeedle(haystack, filename, needle, opts.case_sensitive, strict_path)) |r| {
            sum += r;
        } else return null;
    }

    // all needles matched and the best ranks for each needle are summed
    return sum;
}

pub const RankNeedleOptions = struct {
    /// Set to false for case insensitive ranking.
    case_sensitive: bool = true,

    /// Set to true when the needle has path separators in it
    strict_path: bool = false,

    /// Set to the filename (basename) of the haystack for filepath matching
    filename: ?[]const u8 = null,
};

/// rank a given haystack against a single needle
pub fn rankNeedle(
    haystack: []const u8,
    needle: []const u8,
    opts: RankNeedleOptions,
) ?f64 {
    return filter.rankNeedle(haystack, opts.filename, needle, opts.case_sensitive, opts.strict_path);
}

test "rank library interface" {
    try testing.expect(rank("abcdefg", &.{ "a", "z" }, .{}) == null);
    try testing.expect(rank("abcdefg", &.{ "a", "b" }, .{}) != null);
    try testing.expect(rank("abcdefg", &.{ "a", "B" }, .{}) == null);
    try testing.expect(rank("aBcdefg", &.{ "a", "B" }, .{}) != null);
    try testing.expect(rank("a/path/to/file", &.{"zig"}, .{}) == null);
    try testing.expect(rank("a/path/to/file", &.{ "path", "file" }, .{}) != null);

    try testing.expect(rankNeedle("abcdefg", "a", .{}) != null);
    try testing.expect(rankNeedle("abcdefg", "z", .{}) == null);
    try testing.expect(rankNeedle("abcdefG", "G", .{}) != null);
    try testing.expect(rankNeedle("abcdefg", "A", .{}) == null);
    try testing.expect(rankNeedle("a/path/to/file", "file", .{ .filename = "file" }) != null);
    try testing.expect(rankNeedle("a/path/to/file", "zig", .{ .filename = "file" }) == null);

    // zero length haystacks and needles
    try testing.expect(rank("", &.{"a"}, .{}) == null);
    try testing.expect(rankNeedle("", "a", .{}) == null);
    try testing.expect(rank("a", &.{""}, .{}) == null);
    try testing.expect(rankNeedle("a", "", .{}) == null);
}

// Maybe all that needs to be done is to sort the highlight integers? That would probably save some work in implementation
// Or maybe could sort and then make ranges out of the pairs? Return a list of ranges?
// for the Zig api that could be reasonable... but the C api maybe not
// sorting as a minimum for sure

/// Remove duplicate match indexes. Assumes input is sorted.
fn deduplicateMatches(matches: []usize) []usize {
    if (matches.len < 2) return matches;

    var end: usize = 1;
    for (matches[1..]) |value| {
        if (value != matches[end - 1]) {
            matches[end] = value;
            end += 1;
        }
    }
    return matches[0..end];
}

test deduplicateMatches {
    {
        var matches: [0]usize = .{};
        try testing.expectEqualSlices(usize, &.{}, deduplicateMatches(&matches));
    }
    {
        var matches: [1]usize = .{ 1 };
        try testing.expectEqualSlices(usize, &.{ 1 }, deduplicateMatches(&matches));
    }
    {
        var matches: [2]usize = .{ 1, 2 };
        try testing.expectEqualSlices(usize, &.{ 1, 2 }, deduplicateMatches(&matches));
    }
    {
        var matches: [2]usize = .{ 1, 1 };
        try testing.expectEqualSlices(usize, &.{ 1 }, deduplicateMatches(&matches));
    }
    {
        var matches: [4]usize = .{ 1, 2, 3, 3 };
        try testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, deduplicateMatches(&matches));
    }
    {
        var matches: [4]usize = .{ 1, 2, 2, 3 };
        try testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, deduplicateMatches(&matches));
    }
    {
        var matches: [8]usize = .{ 0, 1, 1, 2, 2, 2, 3, 4 };
        try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4 }, deduplicateMatches(&matches));
    }
}

/// compute matching ranges given a haystack and a slice of needles
pub fn highlight(
    haystack: []const u8,
    needles: []const []const u8,
    matches: []usize,
    opts: RankOptions,
) []usize {
    const filename = if (opts.plain) null else std.fs.path.basename(haystack);

    var index: usize = 0;
    for (needles) |needle| {
        const strict_path = !opts.plain and filter.hasSeparator(needle);
        const matched = filter.highlightNeedle(haystack, filename, needle, opts.case_sensitive, strict_path, matches[index..]);
        index += matched.len;
    }

    if (needles.len == 1) {
        return matches[0..index];
    }

    // When there is more than one needle, matches may overlap. The matched indices are what
    // matter so we sort and deduplicate. This extra computation is fine because highlighting
    // is usually only done for a small number of haystacks.
    std.mem.sortUnstable(usize, matches[0..index], {}, std.sort.asc(usize));
    return deduplicateMatches(matches[0..index]);
}

/// compute matching ranges given a haystack and a single needle
/// Matches are guaranteed to be in ascending order.
pub fn highlightNeedle(
    haystack: []const u8,
    needle: []const u8,
    matches: []usize,
    opts: RankNeedleOptions,
) []const usize {
    return filter.highlightNeedle(haystack, opts.filename, needle, opts.case_sensitive, opts.strict_path, matches);
}

test "highlight library interface" {
    var matches_buf: [128]usize = undefined;

    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdef", &.{ "a", "f" }, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 0, 5 }, highlight("abcdeF", &.{ "a", "F" }, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 10, 11, 12, 13 }, highlight("a/path/to/file", &.{ "path", "file" }, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 4, 5, 6, 7, 8, 9, 10 }, highlight("lib/ziglyph/zig.mod", &.{"ziglyph"}, &matches_buf, .{}));

    try testing.expectEqualSlices(usize, &.{0}, highlightNeedle("abcdef", "a", &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{5}, highlightNeedle("abcdeF", "F", &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 10, 11, 12, 13 }, highlightNeedle("a/path/to/file", "file", &matches_buf, .{ .filename = "file" }));

    // highlights with basename trailing slashes
    try testing.expectEqualSlices(usize, &.{0}, highlightNeedle("s/", "s", &matches_buf, .{ .filename = "s" }));
    try testing.expectEqualSlices(usize, &.{ 20, 21, 22, 23 }, highlightNeedle("/this/is/path/not/a/file/", "file", &matches_buf, .{ .filename = "file" }));

    // disconnected highlights
    try testing.expectEqualSlices(usize, &.{ 0, 2, 3 }, highlight("ababab", &.{"aab"}, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 6, 8, 9 }, highlight("abbbbbabab", &.{"aab"}, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 0, 2, 6 }, highlight("abcdefg", &.{"acg"}, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5, 9, 10 }, highlight("__init__.py", &.{"initpy"}, &matches_buf, .{}));

    // small buffer to ensure highlighting doesn't go out of range when the needles overflow
    var small_buf: [4]usize = undefined;
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, highlight("abcd", &.{ "ab", "cd", "abcd" }, &small_buf, .{}));
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, highlight("wxyz", &.{ "wxy", "xyz" }, &small_buf, .{}));

    // zero length haystacks and needles
    try testing.expectEqualSlices(usize, &.{}, highlight("", &.{"a"}, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{}, highlightNeedle("", "a", &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{}, highlight("a", &.{""}, &matches_buf, .{}));
    try testing.expectEqualSlices(usize, &.{}, highlightNeedle("a", "", &matches_buf, .{}));
}
