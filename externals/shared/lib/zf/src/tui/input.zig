const std = @import("std");
const testing = std.testing;
const zf = @import("zf");

const ArrayList = std.ArrayList;

/// Haycstacks are the strings read from stdin
pub const Haystack = struct {
    str: []const u8,
    rank: f64 = 0,
};

/// read the haystacks from the buffer
pub fn collectHaystacks(allocator: std.mem.Allocator, buf: []const u8, delimiter: u8) ![][]const u8 {
    var haystacks: ArrayList([]const u8) = .empty;

    // find delimiters
    var start: usize = 0;
    for (buf, 0..) |char, index| {
        if (char == delimiter) {
            // add to arraylist only if slice is not all delimiters
            if (index - start != 0) {
                try haystacks.append(allocator, buf[start..index]);
            }
            start = index + 1;
        }
    }

    // catch the end if stdio didn't end in a delimiter
    if (start < buf.len and buf[start] != delimiter) {
        try haystacks.append(allocator, buf[start..]);
    }

    return try haystacks.toOwnedSlice(allocator);
}

test "collect whitespace" {
    const haystacks = try collectHaystacks(testing.allocator, "first second third fourth", ' ');
    defer testing.allocator.free(haystacks);

    try testing.expectEqual(4, haystacks.len);
    try testing.expectEqualStrings("first", haystacks[0]);
    try testing.expectEqualStrings("second", haystacks[1]);
    try testing.expectEqualStrings("third", haystacks[2]);
    try testing.expectEqualStrings("fourth", haystacks[3]);
}

test "collect newline" {
    const haystacks = try collectHaystacks(testing.allocator, "first\nsecond\nthird\nfourth", '\n');
    defer testing.allocator.free(haystacks);

    try testing.expectEqual(4, haystacks.len);
    try testing.expectEqualStrings("first", haystacks[0]);
    try testing.expectEqualStrings("second", haystacks[1]);
    try testing.expectEqualStrings("third", haystacks[2]);
    try testing.expectEqualStrings("fourth", haystacks[3]);
}

test "collect excess whitespace" {
    const haystacks = try collectHaystacks(testing.allocator, "   first second   third fourth   ", ' ');
    defer testing.allocator.free(haystacks);

    try testing.expectEqual(4, haystacks.len);
    try testing.expectEqualStrings("first", haystacks[0]);
    try testing.expectEqualStrings("second", haystacks[1]);
    try testing.expectEqualStrings("third", haystacks[2]);
    try testing.expectEqualStrings("fourth", haystacks[3]);
}

/// rank each haystack against the query
///
/// returns a sorted slice of Haystacks that match the query ready for display
/// in a tui or output to stdout
pub fn rankAndSort(
    ranked: []Haystack,
    haystacks: []const []const u8,
    needles: []const []const u8,
    keep_order: bool,
    plain: bool,
    case_sensitive: bool,
) []Haystack {
    if (needles.len == 0) {
        for (haystacks, 0..) |haystack, index| {
            ranked[index] = .{ .str = haystack };
        }
        return ranked;
    }

    var index: usize = 0;
    for (haystacks) |haystack| {
        if (zf.rank(haystack, needles, .{ .case_sensitive = case_sensitive, .plain = plain })) |r| {
            ranked[index] = .{ .str = haystack, .rank = r };
            index += 1;
        }
    }

    if (!keep_order) {
        std.sort.block(Haystack, ranked[0..index], {}, sort);
    }

    return ranked[0..index];
}

fn sort(_: void, a: Haystack, b: Haystack) bool {
    // first by rank
    if (a.rank < b.rank) return true;
    if (a.rank > b.rank) return false;

    // then by length
    if (a.str.len < b.str.len) return true;
    if (a.str.len > b.str.len) return false;

    // then alphabetically
    for (a.str, 0..) |c, i| {
        if (c < b.str[i]) return true;
        if (c > b.str[i]) return false;
    }
    return false;
}

// These tests are arguably the most important in zf. They ensure the ordering of filtered
// items is maintained when updating the filter algorithms. The test cases are based on
// experience with other fuzzy finders that led to the creation of zf. When I find new
// ways to improve the filtering algorithm these tests should all pass, and new tests
// should be added to ensure the filtering doesn't break. The tests don't check the actual
// rank value, only the order of the first n results.

fn testRankHaystacks(
    needles: []const []const u8,
    haystacks: []const []const u8,
    expected: []const []const u8,
) !void {
    const ranked_buf = try testing.allocator.alloc(Haystack, haystacks.len);
    defer testing.allocator.free(ranked_buf);
    const ranked = rankAndSort(ranked_buf, haystacks, needles, false, false, false);

    for (expected, 0..) |expected_str, i| {
        if (!std.mem.eql(u8, expected_str, ranked[i].str)) {
            std.debug.print("\n======= order incorrect: ========\n", .{});
            for (ranked[0..@min(ranked.len, expected.len)]) |haystack| std.debug.print("{s}\n", .{haystack.str});
            std.debug.print("\n========== expected: ===========\n", .{});
            for (expected) |str| std.debug.print("{s}\n", .{str});
            std.debug.print("\n================================", .{});
            std.debug.print("\nwith query:", .{});
            for (needles) |needle| std.debug.print(" {s}", .{needle});
            std.debug.print("\n\n", .{});

            return error.TestOrderIncorrect;
        }
    }
}

test "zf ranking consistency" {
    // Filepaths from Blender. Both fzf and fzy rank DNA_genfile.h first
    try testRankHaystacks(
        &.{"make"},
        &.{
            "source/blender/makesrna/intern/rna_cachefile.c",
            "source/blender/makesdna/intern/dna_genfile.c",
            "source/blender/makesdna/DNA_curveprofile_types.h",
            "source/blender/makesdna/DNA_genfile.h",
            "GNUmakefile",
        },
        &.{"GNUmakefile"},
    );

    // From issue #3, prioritize filename coverage
    try testRankHaystacks(&.{"a"}, &.{ "/path/a.c", "abcd" }, &.{"/path/a.c"});
    try testRankHaystacks(
        &.{"app.py"},
        &.{
            "./myownmod/custom/app.py",
            "./tests/test_app.py",
        },
        &.{"./tests/test_app.py"},
    );

    // From issue #24, some really great test cases (thanks @ratfactor!)
    const haystacks = [_][]const u8{
        "oat/meal/sug/ar",
        "oat/meal/sug/ar/sugar",
        "oat/meal/sug/ar/sugar.txt",
        "oat/meal/sug/ar/sugar.js",
        "oatmeal/sugar/sugar.txt",
        "oatmeal/sugar/snakes.txt",
        "oatmeal/sugar/skeletons.txt",
        "oatmeal/brown_sugar.txt",
        "oatmeal/brown_sugar/brown.js",
        "oatmeal/brown_sugar/sugar.js",
        "oatmeal/brown_sugar/brown_sugar.js",
        "oatmeal/brown_sugar/sugar_brown.js",
        "oatmeal/granulated_sugar.txt",
        "oatmeal/raisins/sugar.js",
    };
    try testRankHaystacks(
        &.{ "oat/sugar", "sugar/sugar", "meal/sugar" },
        &haystacks,
        &.{ "oatmeal/sugar/sugar.txt", "oatmeal/brown_sugar/sugar.js", "oatmeal/brown_sugar/brown_sugar.js" },
    );
    try testRankHaystacks(&.{ "oat/sugar", "brown" }, &haystacks, &.{"oatmeal/brown_sugar/brown.js"});
    try testRankHaystacks(&.{"oat/sn"}, &haystacks, &.{"oatmeal/sugar/snakes.txt"});
    try testRankHaystacks(&.{"oat/skel"}, &haystacks, &.{"oatmeal/sugar/skeletons.txt"});

    // Strict path matching better ranking
    try testRankHaystacks(
        &.{"mod/baz.rb"},
        &.{
            "./app/models/foo-bar-baz.rb",
            "./app/models/foo/bar-baz.rb",
            "./app/models/foo/bar/baz.rb",
        },
        &.{"./app/models/foo/bar/baz.rb"},
    );
}
