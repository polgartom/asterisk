switch_editor_mode :: (switch_to: Program_Mode) {
    if switch_to == {
        case .EDITOR;
            active_widget_deactivate_all();
            
            #if POWERSAVE_BUILD {
                powersaving = true;
            }
            
            mode = .EDITOR;                
        case .WIDGET;
            #if POWERSAVE_BUILD {
                powersaving = false;
            }
        
            mode = .WIDGET;
    }
}

open_file_or_create_empty_buffer :: (editor: *Editor, _filepath: string) {
    filepath := File.get_absolute_path(_filepath);
    path_overwrite_separators(filepath, #char "/");

    for editor.buffers {
        if it.filepath == filepath return;
    }

    buffer: *Buffer;
    for * editor.buffers {
        if it.initialized && !it.exists_on_disk && !it.dirty && !it.count {
            buffer = it;
            break;
        }
    }

    if !buffer {
        buffer = create_or_find_empty_buffer(editor);
    }

    buffer.filepath       = copy_string(filepath);
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

    change_active_buffer(editor, buffer);
}

sanitize_and_free_input_data :: (data: string) -> string {
    assert(data.count > 0);
    
    s := data;
    s = replace_crlf_to_lf(s, autofree=true);
    s = replace_tabs_with_spaces(s, autofree=true);

    return s;
}

close_buffer :: (using editor: *Editor, buffer: *Buffer) {
    found, index := find_buffer_index(editor, buffer);
    assert(found && index != -1);

    buffer_reset_keeping_memory(buffer);

    active_buffer = null;
    for * buffers {
        if it_index > index && it.initialized {
            active_buffer = it;
            return;
        }
    }

    if !active_buffer {
        for * buffers {
            if it.initialized {
                active_buffer = it;
                return;
            }
        }
    }

    active_buffer = create_or_find_empty_buffer(editor);
}

get_buffer_index :: (using editor: *Editor, buffer: *Buffer) -> s64 {
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
    editor.left_offset = 0.0;
    editor.top_offset  = 0.0;
}

editor: *Editor; // @Temporary

should_recalc_editor_offsets := false; // @Temporary

Editor :: struct {
    buffers: [..] Buffer;
    active_buffer: *Buffer; // Cannot be null after initialization

    // cursor_pos: s64 = 0;
    // cursor_moved := false;
    // last_cursor_col_for_up_down_movement: s64 = 0;

    top_offset  := 0.0;
    left_offset := 0.0;
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