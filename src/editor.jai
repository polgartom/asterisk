open_file_or_create_empty_buffer :: (editor: *Editor, _filepath: string) {
    filepath := File.get_absolute_path(_filepath);
    for editor.buffers {
        if it.filepath == filepath return;
    }

    buffer := create_buffer(editor);
    buffer.filepath       = filepath;
    buffer.exists_on_disk = file_exists(filepath);
    
    if buffer.exists_on_disk {
        input := File.read_entire_file(filepath);
        if input {
            input = sanitize_and_free_input_data(input);
            if input.count {
                maybe_grow(buffer, input.count);
                SlowMemcpy(buffer.data, input.data, input.count);
                buffer.count = input.count;
            }
        }
    }

    rescan_line_ends(buffer);

    editor.active_buffer = buffer;
}

sanitize_and_free_input_data :: (data: string) -> string {
    assert(data.count > 0);
    
    s := data;
    s = replace_crlf_to_lf(s, autofree=true);
    s = replace_tabs_with_spaces(s, autofree=true);

    return s;
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

get_buffer_index :: (using editor: *Editor, buffer: *Buffer) -> s64 {
    assert(editor.active_buffer != null);

    for * buffers {
        if buffer == it {
            return it_index;
        }
    }

    assert(false); // @Temporary
    return -1;
}

get_active_editor_and_buffer :: () -> (editor: *Editor, buffer: *Buffer) {
    assert(editor.active_buffer != null);
    return editor, editor.active_buffer;
}

create_editor :: () -> *Editor {
    editor := New(Editor);
    return editor;
}

change_active_buffer :: (editor: *Editor, buffer: *Buffer) {
    i := get_buffer_index(editor, buffer);
    assert(i != -1);

    editor.active_buffer = buffer;
    should_recalc_editor_offsets = true;
}

editor: *Editor; // @Temporary

should_recalc_editor_offsets := false; // @Temporary

Editor :: struct {
    buffers: [..] Buffer;
    active_buffer: *Buffer; // Cannot be null after initialization

    // cursor_pos: s64 = 0;
    // cursor_moved := false;
    // last_cursor_col_for_up_down_movement: s64 = 0;

    top_offset  := 0.0; // s64?
    left_offset := 0.0; // s64?
}

replace_tabs_with_spaces :: inline (input: string, $autofree := false) -> (result: string, ocurrences: int) {
    #if autofree {
        defer free(input);
    }
    
    result, ocurrences := replace(input, "\t", TAB_SPACE_CHARS);
    return result, ocurrences;
}

replace_crlf_to_lf :: inline (input: string, $autofree := false) -> (result: string, ocurrences: int) {
    #if autofree {
        defer free(input);
    }

    result, ocurrences := replace(input, "\r\n", "\n");
    return result, ocurrences;
}