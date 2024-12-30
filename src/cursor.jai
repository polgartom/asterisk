// @Cleanup: Rename the $with_selection param because the opposite is happening right now!
set_cursor_pos :: inline (buffer: *Buffer, cursor: *Cursor, target_pos: s64, horizontal := false, with_selection := true) {
    target_pos = max(target_pos, 0);
    target_pos = min(target_pos, buffer.count);

    if with_selection {
        cursor.pos = target_pos;
        cursor.sel = target_pos;
    } else {
        cursor.pos = target_pos;
    }

    // Explain!
    if horizontal {
        cursor.col = byte_pos_to_col_pos(buffer, cursor.pos);
    }

    should_recalc_editor_offsets = true;
}

selected_range :: inline (using c: *Cursor) -> (start: s64, end: s64) {
    return min(pos, sel), max(pos, sel);
}

count_selected_bytes :: inline (using c: *Cursor) -> s64 {
    return max(pos, sel) - min(pos, sel);
}

has_selection :: inline (using c: Cursor) -> bool {
    return pos != sel;
}

count_selected_chars :: inline (buffer: *Buffer, using c: *Cursor) -> s64 {
    start, end := selected_range(c);
    if end - start == 0 return 0;

    s: string = ---;
    s.data = buffer.data + cast(s64)start;
    s.count = end - start;

    return utf8_count_chars(s);
}

get_cursor_min_max_indecies_as_pointers :: (cursor: *Cursor) -> (cursor_min_position: *s64, cursor_max_position: *s64) {
    c1 := *cursor.pos;
    c2 := *cursor.sel;
    if c2.* < c1.* {
        tmp := c1;
        c1 = c2;
        c2 = tmp;
    }

    return c1, c2;
}

Cursor :: struct {
    pos: s64 = 0;
    sel: s64 = 0;
    col: s64 = 0; // last_cursor_col_for_up_down_movement

    x_cache: s64 = -1; // @Temporary
}