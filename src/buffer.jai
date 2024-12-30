get_row_as_string :: inline (using buffer: *Buffer, index: s64) -> string {
    assert(index < row_table.count);

    s := get_row_as_string(buffer, row_table[index]);
    return s;
}

get_row_as_string :: inline (using buffer: *Buffer, row: Row_Info) -> string {
    s := slice(buffer, row.start, row.size);
    return s;
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

    insert_text_at_cursor(buffer, cursor, text);
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

insert_text_at :: (buffer: *Buffer, at: s64, text: string) {
    assert(at > -1);

    maybe_grow(buffer, text.count);

    insert_at      := buffer.data  + at;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    SlowMemcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;
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

create_buffer :: (editor: *Editor) -> *Buffer {
    buffer := array_add(*editor.buffers);
    maybe_grow(buffer, 0);
    rebuild_row_table(buffer);

    return buffer;
}

// @Speed:   We could implement something like a Quadtree. For example we might create a chunk after every 1000 rows (line ends)
// @Cleanup: Rename this procedure to something like rescan_line_ends()
rebuild_row_table :: (using buffer: *Buffer) {
    rebuild_row_table = false;

    timer :=  seconds_since_init();
    defer row_table_recalc_time = (seconds_since_init() - timer) * 1000;

    array_reset_keeping_memory(*row_table);

    s := to_string(buffer);
    pos := 0;
    while true {
        ln_index := inline find_index_from_left(s, #char "\n");
        if ln_index == -1 {
            inline array_add(*row_table, .{start=pos, end=pos+s.count, size=s.count});
            break;
        }

        size := ln_index;
        pos += size;
        inline array_add(*row_table, .{start=pos-size, end=pos, size=size});

        ln_index += 1;
        inline advance(*s, ln_index);

        pos += 1; // because of the line end
    }

}

get_character_as_string_at :: (buffer: *Buffer, at: u32) -> string {
    // @Todo VALIDATIONS!
    if at >= buffer.count return "";    
    if buffer.data[at] == #char "\n" return ""; // @Hacky

    s := slice(buffer, at, buffer.count - at);
    bytes := 1 + trailingBytesForUTF8[s[0]];
    s.count = bytes;
    return s;
}

slice :: inline (buffer: *Buffer, start: s64, count: s64) -> string {
    s := to_string(buffer);
    return slice(s, start, count);
}

to_string :: inline (buffer: *Buffer) -> string {
    s: string = ---;
    s.count = buffer.count;
    s.data = buffer.data;
    return s;
}

// Shift the entire *used* buffer memory to the left, typically for "deleting" characters from the right
shift_left :: (using buffer: *Buffer, to: s64, from: s64) { // @Cleanup Naming?!
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
    
    if size == 0 then size = BUFFER_PAGE_SIZE;
    desired_size := buffer.count + size;

    if desired_size >= buffer.allocated {
        new_size := buffer.allocated + desired_size;
        new_size  = Align(new_size, BUFFER_PAGE_SIZE);

        new_data := cast(*u8)c_malloc(xx new_size);
        assert(new_data != null);
        ZeroMemory(new_data, new_size);

        if buffer.data {
            SlowMemcpy(new_data, buffer.data, buffer.allocated);
            c_free(buffer.data);
        }

        buffer.data      = new_data;
        buffer.allocated = new_size;
    }
}

Buffer :: struct {
    data:      *u8;
    count:     s64;
    allocated: s64;

    dirty := false;

    // cursors: [..] Cursor; // @Todo: Multiple cursor support
    _cursor: Cursor; // This name temporary, because we're gonna use the cursors dynamic array

    row_table: [..] Row_Info;
    rebuild_row_table := false;
    row_table_recalc_time: float64 = 0.0;
    filepath: string;

    // @Todo: It's mainly for the system buffers like logs or console output etc..
    read_only := false;
}

BUFFER_PAGE_SIZE :: 4096;

// @Speed: Shrink the struct size because we use 3 × 8 bytes per row which is quite inefficient!
Row_Info :: struct {
    start: s64;
    end:   s64;
    size:  s64;
}