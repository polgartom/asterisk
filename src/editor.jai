open_file :: (editor: *Editor, filepath: string) {
    file_data := read_entire_file(filepath);
    defer free(file_data);

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
    {
        // @Todo: A nice alert or something instead of these asserts
        // Validate UTF-8
        s := file_data;
        while s.count {
            code, bytes, success := character_utf8_to_utf32(s.data, s.count);
            assert(success == .CONVERSION_OK, "Invalid UTF-8 file");
            s.data  += bytes;
            s.count -= bytes;
            assert(s.count >= 0, "Invalid UTF-8 file");
        } 
    }

    assert(editor.active_buffer != null);

    buffer := editor.active_buffer;
    if buffer.dirty || buffer.filepath {
        // Using the current buffer if it's empty, probably it's the initial buffer
        buffer = array_add(*editor.buffers);
    }

    buffer.filepath = filepath;
    
    maybe_grow(buffer, file_data.count);
    
    SlowMemcpy(buffer.data, file_data.data, file_data.count);
    buffer.count = file_data.count;

    rebuild_row_table(buffer);

    editor.active_buffer = buffer;
}

close_buffer :: (editor: *Editor, buffer: *Buffer) {
    // success := array_ordered_remove_by_value(editor.buffers, buffer);
    // assert(success, "Buffer doesn't found!");

    // @Cleanup: WTF??!
    tmp := editor.buffers;
    array_reset_keeping_memory(*editor.buffers);
    for * tmp {
        if it != buffer then array_add(*editor.buffers, it);
    }

    c_free(buffer.data);
    array_free(buffer.row_table);
    // free(buffer.filepath); // @Todo

    if editor.buffers.count == 0 {
        // Create a new empty (initial) buffer
        new_buffer := create_buffer(editor);
        editor.active_buffer = new_buffer;
    } else {
        last_index := editor.buffers.count-1;
        editor.active_buffer = *editor.buffers[last_index];
    }
}

get_active_buffer_index :: (using editor: *Editor) -> s64 {
    for * buffers {
        if active_buffer == it {
            return it_index;
        }
    }

    assert(false, "Buffer not in the list!");
    return -1;
}

get_active_editor_and_buffer :: () -> (editor: *Editor, buffer: *Buffer) {
    assert(editor.active_buffer != null);
    return editor, editor.active_buffer;
}

create_an_editor_instance :: () -> *Editor {
    editor := New(Editor);
    buffer := create_buffer(editor);
    editor.active_buffer = buffer;

    return editor;
}

// Active editor
editor: *Editor; // @Temporary?

Editor :: struct {
    buffers: [..] Buffer;
    active_buffer: *Buffer; // Cannot be null after initialization

    // cursor_pos: s64 = 0;
    // cursor_moved := false;
    // last_cursor_col_for_up_down_movement: s64 = 0;

    top_offset  := 0.0; // s64?
    left_offset := 0.0; // s64?
}

replace_tabs_with_spaces :: inline (s: string) -> (result: string, ocurrences: int) {
    result, ocurrences := replace(s, "\t", TAB_SPACE_CHARS);
    return result, ocurrences;
}

replace_crlf_to_lf :: inline (s: string) -> (result: string, ocurrences: int) {
    result, ocurrences := replace(s, "\r\n", "\n");
    return result, ocurrences;
}