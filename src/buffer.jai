shift_left :: (using buffer: *Buffer, to: s64, from: s64) { // another names for "to" and "from"
    if to == from return;
    assert(to < from);

    dest   := data  + to;
    source := data  + from;
    size   := count - from;

    c_memmove(dest, source, xx size);
    count -= (from - to);

    rebuild_row_table = true;

    dirty = true; // @Cleanup: Remove this from here
}

maybe_grow :: (buffer: *Buffer, size: s64) {
    assert(size > -1);

    MAGNITUDE :: 3; // @temporary
    
    desired_size := buffer.count + size;
    if desired_size == 0 {
        desired_size = 1024*MAGNITUDE; // @temporary
    }

    if desired_size >= buffer.allocated {
        new_size := buffer.allocated + (desired_size * MAGNITUDE);
        new_data := cast(*u8)c_malloc(xx new_size);
        assert(new_data != null);
        memset(new_data, 0, xx new_size);

        if buffer.data {
            copy(new_data, buffer.data, buffer.allocated);
            c_free(buffer.data);
        }

        buffer.data      = new_data;
        buffer.allocated = new_size;
    }
}

to_string :: inline (buffer: *Buffer) -> string {
    s: string = ---;
    s.count = buffer.count;
    s.data = buffer.data;
    return s;
}

slice :: inline (buffer: *Buffer, index: s64, count: s64) -> string {
    s := to_string(buffer);
    return slice(s, index, count);
}

get_row_as_string :: (using buffer: *Buffer, index: s64) -> bool, string {
    if index >= row_table.count {
        return false, "";
    }

    row := row_table[index];
    s := slice(buffer, row.pos - row.cols, row.cols);
    
    return true, s;
}

os_clipboard_copy_range :: (buffer: *Buffer, start: s64, end: s64) {
    s := slice(buffer, start, end - start);
    os_clipboard_set_text(s);
}

os_clipboard_paste_text_at_cursor :: (using buffer: *Buffer) -> bool {
    s := os_clipboard_get_text();
    if !s.count return false;

    // @Incomplete: Validate the input!
    // if !Simp.isLegalUTF8(s.data, s.count) {
    //     log_error("OS Clipboard contains invalid utf8 data!\n");
    //     return false;
    // }

    insert_text_at_cursor(buffer, s);

    return true;
}

insert_text_at_cursor :: (using buffer: *Buffer, s: string) {
    MaybeDeleteSelectedText(buffer, *buffer._cursor);

    maybe_grow(buffer, s.count);

    insert_at      := buffer.data  + _cursor.pos;
    new_right      := insert_at    + s.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size); // @Cleanup shift_right procedure
    copy(insert_at, s.data, s.count);

    buffer.count += s.count;
    buffer.rebuild_row_table = true;

    set_cursor_pos(buffer, *_cursor, _cursor.pos+s.count, horizontal=true);

    buffer.dirty = true;
}

Buffer :: struct {
    count:     s64;
    allocated: s64;
    data:      *u8;

    dirty := false;

    // cursors: [..] Cursor; // @Todo: Multiple cursor support
    _cursor: Cursor; // This name temporary, because we're gonna use the cursors dynamic array

    row_table: [..] Row_Info;
    rebuild_row_table := false;
    row_table_recalc_time: float64 = 0.0;

    filepath: string;
}