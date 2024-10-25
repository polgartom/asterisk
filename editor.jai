Editor :: struct {
    buffers: [..] Buffer;
    active_buffer: *Buffer;
    cursor_pos: s64 = 0;
    cursor_moved := false;
    last_cursor_col_for_up_down_movement: s64 = 0;
}

editor: Editor; // @Temporary

to_string :: inline (buffer: *Buffer) -> string {
    s: string = ---;
    s.count = buffer.count;
    s.data = buffer.data;
    return s;
}

maybe_grow :: (buffer: *Buffer, size: s64) {
	assert(size > -1);

    desired_size := buffer.count + size;
    if desired_size == 0 desired_size = 4096; // @temporary
    if desired_size >= buffer.allocated {
        SCALAR :: 2;
        new_size := buffer.allocated + (desired_size * SCALAR);
        new_data := cast(*u8)c_malloc(xx new_size);
        assert(new_data != null);
        memset(new_data, 0, xx new_size);

        if buffer.data {
            memcpy(new_data, buffer.data, buffer.allocated);
            c_free(buffer.data);
        }

        buffer.data      = new_data;
        buffer.allocated = new_size;
    }
}

Buffer :: struct {
    count: s64;
    allocated: s64;
    data: *u8;

    rebuild_row_table := false;
    row_table: [..] Row_Info;
    row_table_recalc_time: float64 = 0.0;

    filepath: string;
}

// @Ambiguity
Row_Info :: struct {
    pos: s64;  // end byte index of the row
    cols: s64; // bytes in the row
}

rebuild_row_table :: (using buffer: *Buffer) {
    rebuild_row_table = false;

    row_table_recalc_time = seconds_since_init();

    // array_reset(*row_table); // @speed can reuse the same memory
    array_reset_keeping_memory(*row_table);

    s := to_string(buffer);
    pos := 0;
    while true {
        ln_index := find_index_from_left(s, #char "\n");
        if ln_index == -1 {
            chars := s.count;
            array_add(*row_table, .{pos=pos+chars, cols=chars});
            break;
        }

        chars := ln_index;
        pos += chars;
        array_add(*row_table, .{pos=pos, cols=chars});

        ln_index += 1;
        advance(*s, ln_index);

        pos += 1; // because of the line end
    }

    row_table_recalc_time = (seconds_since_init()-row_table_recalc_time)*1000;
}

open_file :: (editor: *Editor, filepath: string) {
    file_data := read_entire_file(filepath);
    {
        tmp := replace_crlf_to_lf(file_data);
        free(file_data);
        file_data = tmp;
    }
    {
        tmp := replace_tabs_with_spaces(file_data);
        free(file_data);
        file_data = tmp;
    }

    buffer := array_add(*editor.buffers);
    buffer.filepath = filepath;
    
    maybe_grow(buffer, file_data.count);
    
    copy(buffer.data, file_data.data, file_data.count);
    buffer.count = file_data.count;

    buffer.rebuild_row_table = true;

    editor.active_buffer = buffer;
}

replace_tabs_with_spaces :: inline (s: string) -> (result: string, ocurrences: int) {
    result, ocurrences := replace(s, "\t", TAB_SPACE_CHARS);
    return result, ocurrences;
}

replace_crlf_to_lf :: inline (s: string) -> (result: string, ocurrences: int) {
    result, ocurrences := replace(s, "\r\n", "\n");
    return result, ocurrences;
}