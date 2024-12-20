Align :: inline (n: $T, $$ PAGE_SIZE: s64) -> T {
    return (n + PAGE_SIZE-1) & ~(PAGE_SIZE-1);
}

SlowMemcpy :: (destination: *void, source: *void, count: s64) {
    d := cast(*u8) destination;  s := cast(*u8) source;

    overlapping := destination > source && destination < source + count;
    if !overlapping {
        for 0 .. count - 1
            d[it] = s[it];
    } else {
        for #v2 < count - 1 .. 0
            d[it] = s[it];
    }
}

shift_left :: (using buffer: *Buffer, to: s64, from: s64) {
    if to == from return;
    assert(to < from);

    dest   := data  + to;
    source := data  + from;
    size   := count - from;

    c_memmove(dest, source, xx size);
    count -= (from - to);

    rebuild_row_table = true;
    dirty = true;
}

maybe_grow :: (buffer: *Buffer, size: s64) {
    assert(size > -1);

    MAGNITUDE :: 3; // @temporary

    desired_size := buffer.count + size;
    if desired_size == 0 {
        desired_size = 1024*MAGNITUDE; // @temporary
    }

    if desired_size >= buffer.allocated {
        reserve  := buffer.allocated + (desired_size * MAGNITUDE);
        new_size := Align(reserve, 4096);

        new_data := cast(*u8)c_malloc(xx new_size);
        assert(new_data != null);
        memset(new_data, 0, xx new_size);

        if buffer.data {
            SlowMemcpy(new_data, buffer.data, buffer.allocated);
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

get_selection_as_string :: (buffer: *Buffer, cursor: *Cursor) -> string {
    start, end := selected_range(cursor);
    return slice(buffer, start, end - start);
}

copy_selection_to_os_clipboard :: (buffer: *Buffer, cursor: *Cursor) {
    text := get_selection_as_string(buffer, cursor);
    Clipboard.os_clipboard_set_text(text);
}

cut_selection_and_copy_to_os_clipboard :: (buffer: *Buffer, cursor: *Cursor) {
    if !has_selection(cursor) return;

    text := get_selection_as_string(buffer, cursor);
    Clipboard.os_clipboard_set_text(text);

    delete_selected_range(buffer, cursor);
}

insert_os_clipboard_text_at_cursor :: (buffer: *Buffer, cursor: *Cursor) {
    // @Incomplete: Validate if the input data is valid utf8!
    
    text := Clipboard.os_clipboard_get_text();
    defer free(text);

    insert_text_at_cursor(buffer, text);
}

insert_text_at_cursor :: (buffer: *Buffer, cursor: *Cursor, text: string) {
    MaybeDeleteSelectedText(buffer, cursor);

    maybe_grow(buffer, text.count);

    insert_at      := buffer.data  + cursor.pos;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    SlowMemcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;

    set_cursor_pos(buffer, cursor, cursor.pos + text.count, horizontal=true);
}

// @Todo: Remove this and use the version above!
insert_text_at_cursor :: (buffer: *Buffer, s: string) {
    MaybeDeleteSelectedText(buffer, *buffer._cursor);

    maybe_grow(buffer, s.count);

    c := *buffer._cursor;

    insert_at      := buffer.data  + c.pos;
    new_right      := insert_at    + s.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    SlowMemcpy(insert_at, s.data, s.count);

    buffer.count += s.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;

    set_cursor_pos(buffer, c, c.pos + s.count, horizontal=true);
}

MaybeDeleteSelectedText :: inline (buffer: *Buffer, cursor: *Cursor) -> (text_deleted: bool) {
    if has_selection(buffer._cursor) {
        delete_selected_range(buffer, *buffer._cursor);
        return true;
    }
    return false;
}

delete_selected_range :: (buffer: *Buffer, cursor: *Cursor) {
    if !has_selection(cursor) return;

    start, end := selected_range(cursor);
    shift_left(buffer, start, end);

    set_cursor_pos(buffer, cursor, start, horizontal=true, with_selection=true);

    assert(cursor.pos <= buffer.count, "cursor: % ; buffer.count: %", cursor.pos, buffer.count);
}

next_character_pos :: (buffer: *Buffer, at: s64) -> s64 {
    assert(at > -1 || at <= buffer.count);

    if at == buffer.count return at;

    byte := buffer.data[at];
    return at + 1 + trailingBytesForUTF8[byte];
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
