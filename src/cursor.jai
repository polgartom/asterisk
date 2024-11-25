

set_cursor_pos :: inline (buffer: *Buffer, cursor: *Cursor, target_pos: s64, horizontal := false, $width_selection := true) {
    target_pos = max(target_pos, 0);
    target_pos = min(target_pos, buffer.count);

    #if width_selection {
        cursor.pos = target_pos;
        cursor.sel = target_pos;
    } else {
        cursor.sel = min(target_pos, cursor.sel);
        cursor.pos = max(target_pos, cursor.sel);
    }

    // Explain!
    if horizontal {
        cursor.col = get_cursor_col(buffer, cursor);
    }
}

selected_range :: inline (using c: *Cursor) -> (start: s64, end: s64) {
    return min(pos, sel), max(pos, sel);
}

count_selected_bytes :: inline (using c: *Cursor) -> s64 {
    return max(pos, sel) - min(pos, sel);
}

count_selected_chars :: inline (buffer: *Buffer, using c: *Cursor) -> s64 {
    start, end := selected_range(c);
    if end - start == 0 return 0;

    s: string = ---;
    s.data = buffer.data + start;
    s.count = end - start;

    return utf8_count_chars(s);
}

Cursor :: struct {
    pos: s64 = 0;
    sel: s64 = 0;
    col: s64 = 0; // last_cursor_col_for_up_down_movement

    x_cache: s64 = -1; // @Temporary
}