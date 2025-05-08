// @Cleanup: Rename the $with_selection param because the opposite is happening right now!
set_cursor_pos :: (buffer: *Buffer, cursor: *Cursor, target_pos: s64, horizontal := false, with_selection := true) {
    cursor.moved = true;

    Clamp(*target_pos, 0, buffer.count);

    if with_selection {
        cursor.pos = target_pos;
        cursor.sel = target_pos;
    } else {
        cursor.pos = target_pos;
    }

    // Explain!
    if horizontal {
        cursor.col = byte_pos_to_row_col_index(buffer, target_pos);
    }
}

rearrange_cursor :: (buffer: *Buffer, cursor: *Cursor, steps: s64) {
    cursor.pos += steps;
    cursor.sel += steps;

    clamp_cursor(cursor, buffer.count);
}

selected_range :: inline (using c: *Cursor) -> (start: s64, end: s64) {
    return min(pos, sel), max(pos, sel);
}

has_selection :: inline (using c: Cursor) -> bool {
    return pos != sel;
}

clamp_cursor :: (c: *Cursor, max: s64) {
    Clamp(*c.pos, 0, max);
    Clamp(*c.sel, 0, max);
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

    moved := false;

    backup: Backup_Point;

    Backup_Point :: struct {
        active:  bool;
        pos_col: s64;
        sel_col: s64; 
        pos_row_index: s64;
        sel_row_index: s64;
    }

    x_cache: s64 = -1; // @Temporary
}