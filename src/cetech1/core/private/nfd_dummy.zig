/// Open single file dialog
pub fn openFileDialog(filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8 {
    _ = default_path;
    _ = filter;
    return null;
}

/// Open save dialog
pub fn saveFileDialog(filter: ?[:0]const u8, default_path: ?[:0]const u8) anyerror!?[:0]const u8 {
    _ = default_path;
    _ = filter;
    return null;
}

/// Open folder dialog
pub fn openFolderDialog(default_path: ?[:0]const u8) anyerror!?[:0]const u8 {
    _ = default_path;
    return null;
}

pub fn freePath(path: []const u8) void {
    _ = path;
}
