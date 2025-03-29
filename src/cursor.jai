// @Cleanup: Rename the $with_selection param because the opposite is happening right now!
set_cursor_pos :: (buffer: *Buffer, cursor: *Cursor, target_pos: s64, horizontal := false, with_selection := true) {

    Clamp(*target_pos, 0, buffer.count);

    if with_selection {
        cursor.pos = target_pos;
        cursor.sel = target_pos;
    } else {
        cursor.pos = target_pos;
    }

    // Explain!
    if horizontal {
        cursor.col = byte_pos_to_col_pos_hacky(buffer, target_pos);
    }
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

set_selection_unsafe :: inline (c: *Cursor, range: Range) {
    a, b := get_cursor_min_max_indecies_as_pointers(c);
    a.* = range.start;
    b.* = range.end;
}

clamp_cursor :: (c: *Cursor, max: s64) {
    Clamp(*c.pos, 0, max);
    Clamp(*c.sel, 0, max);
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

save_cursor_col :: (b: *Buffer, c: *Cursor) {
    backup := *c.backup;
    using backup;

    active = true;
    
    pos_col = byte_pos_to_col_pos(b, c.pos);
    sel_col = byte_pos_to_col_pos(b, c.sel);
    
    pos_row_index = find_row_index(b, c.pos);
    sel_row_index = find_row_index(b, c.sel);

    // print("save_cursor_col() -> pos: % % ; sel: % %\n", pos_col, pos_row_index, sel_col, sel_row_index);
}

try_restore_cursor_col :: (b: *Buffer, c: *Cursor) {
    backup := *c.backup;
    using backup;

    if !active return;
    active = false;

    GetBytePos :: (row_index: s64, col: s64) -> s64 #expand {
        if row_index >= `b.row_table.count {
            log_error("GetBytePos() desired row index doesn't exists anymore, so we're gonna use the last one! Desired: % ; last: %\n", row_index, `b.row_table.count-1);
            row_index = `b.row_table.count-1;
        }

        row := `b.row_table[row_index];
        if col == 0 then return row.start;

        _col := 0;
        s := get_row_as_string(`b, row);
        while s {
            if _col == col break;
            
            utf8_advance_one_character(*s);
            
            _col += 1;
        }

        return s.data - `b.data;
    }

    restored_c_pos := GetBytePos(pos_row_index, pos_col);
    restored_c_sel := GetBytePos(sel_row_index, sel_col);

    // print("try_restore_cursor_col() -> pos: % -> % ; sel: % -> %\n", c.pos, restored_c_pos, c.sel, restored_c_sel);

    c.pos = restored_c_pos;
    c.sel = restored_c_sel;
}

Cursor :: struct {
    pos: s64 = 0;
    sel: s64 = 0;
    col: s64 = 0; // last_cursor_col_for_up_down_movement

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