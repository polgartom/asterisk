Save :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    assert(!!filepath, "TODO");
    
    s := to_string(buffer);
    write_entire_file(filepath, s);

    dirty = false;
}

CloseCurrentBuffer :: () {
    editor, buffer := get_active_editor_and_buffer();
    
    assert(buffer != null);

    // @Todo: A confirm popup thing
    // if buffer.dirty {}

    close_buffer(editor, buffer);
}

PrevBuffer :: () {
    editor, buffer := get_active_editor_and_buffer();
    using editor;

    current_index := get_active_buffer_index(editor);
    prev_index    := current_index-1;
    if prev_index < 0 then prev_index = buffers.count-1;
    prev_buffer   := *buffers[prev_index];

    editor.active_buffer = prev_buffer;
}

NextBuffer :: () {
    editor, buffer := get_active_editor_and_buffer();
    using editor;

    current_index := get_active_buffer_index(editor);
    next_index    := (current_index + 1) % buffers.count;
    next_buffer   := *buffers[next_index];
    
    editor.active_buffer = next_buffer;
}

Quit :: () {
    should_quit = true;
}

OpenWidget :: () {
    editor_in_focus = false;
}

ToggleDevInfo :: () {
    show_debug_info = !show_debug_info;
}

DrawSpecialChars :: () {
    draw_special_chars = !draw_special_chars;
}

move_up_by_one_row :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    for row, row_index: row_table {
        if _cursor.pos <= row.pos {
            if row_index == 0 break; // no more row above

            prev_row      := row_table[row_index-1];
            prev_row_cols := num_of_chars_in_row(buffer, prev_row);
            steps         := min(prev_row_cols, _cursor.col);
            pos           := row_first_byte_offset(prev_row);

            while steps {
                byte := buffer.data[pos];
                bytes := 1 + trailingBytesForUTF8[byte];
                pos += bytes;
                steps -= 1;
            }

            set_cursor_pos(buffer, *_cursor, pos, with_selection=with_selection);
            break;
        }
    }
}

MoveUp :: () {
    move_up_by_one_row();
}

move_down_by_one_row :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    for row, row_index: row_table {
        if _cursor.pos <= row.pos {
            if row_index == row_table.count-1 break; // no more row below

            next_row      := row_table[row_index+1];
            next_row_cols := num_of_chars_in_row(buffer, next_row);
            steps         := min(next_row_cols, _cursor.col);
            pos           := row_first_byte_offset(next_row);

            while steps {
                byte := buffer.data[pos];
                bytes := 1 + trailingBytesForUTF8[byte];
                pos += bytes;
                steps -= 1;
            }

            set_cursor_pos(buffer, *_cursor, pos, with_selection=with_selection);
            break;
        }
    }
}

MoveDown :: () {
    move_down_by_one_row();
}

move_left_by_one_character :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    
    if buffer._cursor.pos == 0 return;

    offset := prev_char_byte_offset(buffer, buffer._cursor.pos);
    
    set_cursor_pos(buffer, *buffer._cursor, offset, horizontal=true, with_selection=with_selection);

    // @Temporary @Cleanup keep the cursor on the same col when we move up or down (just like in vscode)
    // also we should update this value every time except when we move up or down
    // buffer._cursor.col = get_cursor_col(buffer, *buffer._cursor);
}

MoveLeft :: () {
    move_left_by_one_character();
}

move_right_by_one_character :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    
    if !(buffer._cursor.pos < buffer.count) return;

    byte := buffer.data[buffer._cursor.pos];
    steps := 1 + trailingBytesForUTF8[byte];
    
    set_cursor_pos(buffer, *buffer._cursor, buffer._cursor.pos + steps, horizontal=true, with_selection=with_selection);

    // @Temporary @Cleanup keep the cursor on the same col when we move up or down (just like in vscode)
    // also we should update this value every time except when we move up or down
    // buffer._cursor.col = get_cursor_col(buffer, *buffer._cursor);
}

MoveRight :: () {
    move_right_by_one_character();
}

move_left_word :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;
    
    if _cursor.pos == 0 return;

    if _cursor.pos == buffer.count {
        offset := prev_char_byte_offset(buffer, _cursor.pos);
        set_cursor_pos(buffer, *_cursor, offset, horizontal=true);
    }

    row_index := find_row_index(buffer, _cursor.pos);    
    row := row_table[row_index];

    offset := row_first_byte_offset(row);
    if offset == _cursor.pos {
        if row_index == 0 return; // no more row above

        row = row_table[row_index-1];
        offset = row_first_byte_offset(row);
    }

    text := to_string(buffer);

    start := offset; // we use this as initial value, because offset-1 is a line break if row.count > 1
    end := prev_char_byte_offset(buffer, _cursor.pos);
    assert(end > -1);
    assert(end < text.count);

    // @Cleanup
    whitespace := is_whitespace(text[_cursor.pos]) && is_whitespace(text[end]);
    if whitespace {
        last_non_whitespace_offset := _cursor.pos;
        for start..end {
            if !is_whitespace(text[it]) {
                last_non_whitespace_offset = it;
            }
        }
        new_pos := last_non_whitespace_offset+1;
        if new_pos > _cursor.pos new_pos = last_non_whitespace_offset;
        if new_pos == _cursor.pos new_pos = max(0, _cursor.pos-1);
        set_cursor_pos(buffer, *_cursor, new_pos, horizontal=true);
        return;
    }

    // @Cleanup
    if !is_separator_char(text[end], subword_mode) && !is_separator_char(text[_cursor.pos], subword_mode) {
        for start..end {
            separator := is_separator_char(text[it], subword_mode);
            if separator {
                offset = it;
            }
        }
    } else {
        not_combined := is_separator_char(text[_cursor.pos], subword_mode) && !is_separator_char(text[end], subword_mode);
        for start..end {
            separator := is_separator_char(text[it], subword_mode);
            if not_combined {
                if separator {
                    offset = it;
                }
            } else {
                if !separator {
                    offset = it;
                }
            }
        }
    }
    
    if offset != start {
        offset = next_char_byte_offset(text, offset);
    }

    set_cursor_pos(buffer, *_cursor, offset, horizontal=true);
}

move_right_word :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if _cursor.pos == buffer.count return;

    text  := to_string(buffer);
    start := next_char_byte_offset(text, _cursor.pos);

    // It's a better solution than the current IDE's behavior
    whitespace := is_whitespace(text[_cursor.pos]);
    if whitespace {
        last_whitespace_offset := _cursor.pos;
        for start..text.count-1 {
            last_whitespace_offset = it;
            if !is_whitespace(text[it]) break;
        }
        set_cursor_pos(buffer, *_cursor, last_whitespace_offset, horizontal=true);
        return;
    }

    combined := is_separator_char(text[_cursor.pos]);
    for start..text.count-1 {
        separator := is_separator_char(text[it], subword_mode);
        if combined {
            if !separator {
                set_cursor_pos(buffer, *_cursor, it, horizontal=true);
                return;
            }
        } else {
            if separator {
                set_cursor_pos(buffer, *_cursor, it, horizontal=true);
                return;
            }
        }
    }

    set_cursor_pos(buffer, *_cursor, text.count, horizontal=true); // no more word so we should jump to the last byte of the row
}

MoveLeftWord :: inline () {
    move_left_word(false);
}

MoveLeftSubword :: inline () {
    move_left_word(true);
}

MoveRightWord :: inline () {
    move_right_word(false);
}

MoveRightSubword :: inline () {
    move_right_word(true);
}

ScrollViewPortUp :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    text := to_string(buffer);

    start := first_visible_row_index(editor, buffer);
    end := last_visible_row_index(buffer);
    max_row := clamp(end-start, 0, row_table.count-1);
    current_row := find_row_index(buffer, _cursor.pos);
    dest_row_index := clamp(current_row - max_row, 0, row_table.count-1);
    dest_row := row_table[dest_row_index];
    pos := row_last_byte_offset(dest_row);
    set_cursor_pos(buffer, *_cursor, pos);
}

ScrollViewPortDown :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    start := first_visible_row_index(editor, buffer);
    end := last_visible_row_index(buffer);
    max_row := clamp(end-start, 0, row_table.count-1);
    current_row := find_row_index(buffer, _cursor.pos);
    dest_row_index := clamp(current_row + max_row, 0, row_table.count-1);
    dest_row := row_table[dest_row_index];
    pos := row_last_byte_offset(dest_row);
    set_cursor_pos(buffer, *_cursor, pos);
}

Copy :: () {
    editor, buffer := get_active_editor_and_buffer();
    copy_selection_to_os_clipboard(buffer, *buffer._cursor);
}

Paste :: () {
    editor, buffer := get_active_editor_and_buffer();
    insert_os_clipboard_text_at_cursor(buffer, *buffer._cursor);
}

Cut :: () {
    editor, buffer := get_active_editor_and_buffer();
    using,except(rebuild_row_table) buffer;

    if has_selection(buffer._cursor) {
        cut_selection_and_copy_to_os_clipboard(buffer, *_cursor);
        return;
    }

    // Cut the whole line
    row_index := find_row_index(buffer, _cursor.pos);
    row       := row_table[row_index];
    start     := row.pos - row.cols;
    end       := next_character_pos(buffer, row.pos);

    _cursor.pos = start;
    _cursor.sel = end;

    cut_selection_and_copy_to_os_clipboard(buffer, *_cursor);
}

DeleteEverythingFromLeft :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if MaybeDeleteSelectedText(buffer, *buffer._cursor) return;

    row_index := find_row_index(buffer, _cursor.pos);
    row       := row_table[row_index];
    start     := _cursor.pos;
    end       := row.pos;

    shift_left(buffer, start, end);
}

DeleteFromRight :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if MaybeDeleteSelectedText(buffer, *buffer._cursor) return;

    if _cursor.pos == 0 return;

    text := to_string(buffer);

    bytes_to_del := _cursor.pos - prev_char_byte_offset(buffer, _cursor.pos);
    
    space_char := ifx draw_special_chars #char "~" else #char " ";  // @Temporary: this is a stupid fix for the special char visualization

    // Check if we should delete a "tab"
    ch := text.data[_cursor.pos-1];
    if ch == space_char {
        i := 0;
        spaces := 1;
        for #v2 < 0.._cursor.pos-1 {
            if text.data[it] == space_char {
                spaces += 1;
                if spaces == TAB_SIZE_IN_SPACES {
                    bytes_to_del = TAB_SIZE_IN_SPACES;
                    break;
                }
            } else {
                break;
            }
        }
    }

    if bytes_to_del {
        to   := _cursor.pos-bytes_to_del;
        from := _cursor.pos;
        shift_left(buffer, to, from);
        set_cursor_pos(buffer, *_cursor, to, horizontal=true);
    }
}

DeleteWordFromLeft :: inline () {
    delete_word_or_subword_from_left(subword_mode=false);
}

DeleteSubwordFromLeft :: inline () {
    delete_word_or_subword_from_left(subword_mode=true);
}

delete_word_or_subword_from_left :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    MaybeDeleteSelectedText(buffer, *buffer._cursor);

    text := to_string(buffer);
    if text.count == 0 || _cursor.pos == text.count return;

    byte := text[_cursor.pos];
    if is_whitespace(byte) {
        for _cursor.pos..text.count-1 {
            if !is_whitespace(text[it]) {
                to   := _cursor.pos;
                from := it;
                shift_left(buffer, to, from);
                return;
            }    
        }
    }

    for _cursor.pos..text.count-1 {
        if is_separator_char(text[it], subword_mode) {
            to   := _cursor.pos;
            from := it;
            if to == from from = min(from+1, text.count-1); // @Improve: Detect combined separator characters 
            shift_left(buffer, to, from); 
            return;
        }
    }

    shift_left(buffer, _cursor.pos, text.count); // We have no separator character at the end
}

DeleteFromLeft :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if MaybeDeleteSelectedText(buffer, *buffer._cursor) return;

    assert(_cursor.pos <= buffer.count);
    if _cursor.pos == buffer.count return;

    text := to_string(buffer);
    buffer.rebuild_row_table = true;

    byte := text[_cursor.pos];
    bytes_to_del := 1 + trailingBytesForUTF8[byte];
    assert(_cursor.pos + bytes_to_del <= text.count);

    to   := _cursor.pos;
    from := _cursor.pos+bytes_to_del;
    shift_left(buffer, to, from);
}

DeleteWordFromRight :: inline () {
    delete_word_or_subword_from_right(subword_mode=false);
}

DeleteSubwordFromRight :: inline () {
    delete_word_or_subword_from_right(subword_mode=true);
}

delete_word_or_subword_from_right :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using editor;
    using buffer;

    if MaybeDeleteSelectedText(buffer, *buffer._cursor) return;

    if _cursor.pos == 0 return;

    text := to_string(buffer);
    rebuild_row_table = true;

    assert(text.count > 0); // it should never happen, 'cause we already checked the cursor poistion above
    start := _cursor.pos-1;

    #if !subword_mode {
        // Delete all the whitespace until we find a non-whitespace character (only if the first deletable character from right is a whitespace)
        if text[start] == #char " " {
            for #v2 < index: 0..start {
                if text[index] != #char " " {
                    index += 1;
                    shift_left(buffer, index, _cursor.pos);
                    set_cursor_pos(buffer, *_cursor, index, horizontal=true);
                    return;
                }
            }
        }
    }

    if is_separator_char(text[_cursor.pos-1], subword_mode) {
        DeleteFromRight();
        return;
    }

    for #v2 < index: 0..start {
        if is_separator_char(text[index], subword_mode) {
            index += 1;
            shift_left(buffer, index, _cursor.pos);
            set_cursor_pos(buffer, *_cursor, index, horizontal=true);
            return;
        } else if index == 0 {
            shift_left(buffer, 0, _cursor.pos);
            set_cursor_pos(buffer, *_cursor, 0, horizontal=true);
            return;
        }
    }

}

InsertLine :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    MaybeDeleteSelectedText(buffer, *buffer._cursor);

    text := to_string(buffer);
    rebuild_row_table = true;

    if _cursor.pos == 0 {
        insert_text_at_cursor(buffer, "\n");
        return;
    }

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.

    current_row_index := find_row_index(buffer, _cursor.pos);
    row := row_table[current_row_index];
    start := row_first_byte_offset(row);
    end := find_index_from_left_until_not(text, #char " ", start);

    if end == -1 {
        // In this case we only have one row with only whitespace characters
        insert_text_at_cursor(buffer, "\n");
        return;
    }

    if _cursor.pos >= start && _cursor.pos < end {
        // We're in the range of the first n empty spaces, so we just jump to the first non-whitespace
        // occurrence to prevent the weird effect of splitting whitespace characters
        set_cursor_pos(buffer, *_cursor, end);
    }

    insert_text_at_cursor(buffer, "\n");

    spaces := end - start;
    assert(spaces > -1);
    while spaces != 0 {
        insert_text_at_cursor(buffer, " ");
        spaces -= 1;
    }
}

InsertLineBelow :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;
    
    text := to_string(buffer);
    rebuild_row_table = true;

    current_row_index := find_row_index(buffer, _cursor.pos);
    row := row_table[current_row_index];
    set_cursor_pos(buffer, *_cursor, row.pos);    // set cursor to the last character of the current row
    insert_text_at_cursor(buffer, "\n");          // also increment the cursor by a character in this procedure

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.
    row_first_byte_index := row_first_byte_offset(row);
    first_non_whitespace_byte_index := find_index_from_left_until_not(text, #char " ", row_first_byte_index);
    if first_non_whitespace_byte_index != -1 {
        spaces := first_non_whitespace_byte_index - row_first_byte_index;
        assert(spaces > -1);
        while spaces != 0 {
            insert_text_at_cursor(buffer, " ");
            spaces -= 1;
        }
    }

}

InsertTab :: inline () {
    // @Todo: convert < TAB_SIZE_IN_SPACES spaces to tab
    // text := builder_to_string(*builder, do_reset = false);
    // defer free(text);

    // if cursor_pos != text.count {
    //     ch := text.data[cursor_pos];
    //     // ok, sc := surround_chars(text, cursor_pos);
    //     // if ok print("surround_chars: |%|\n", sc);
    //     // else print("failed to get the surround_chars!\n");
    // }

    editor, buffer := get_active_editor_and_buffer();

    insert_text_at_cursor(buffer, TAB_SPACE_CHARS);
    buffer._cursor.col = get_cursor_col(buffer, *buffer._cursor);
}

GotoFirstCharOFCurrentRow :: inline () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    index := find_row_index(buffer, _cursor.pos);
    row   := row_table[index];
    start := row_first_byte_offset(row);

    for start..row.pos {
        if buffer.data[it] != #char " " { // skip the indentation
            new_pos := it;
            if it == _cursor.pos new_pos = start;
            set_cursor_pos(buffer, *_cursor, new_pos, horizontal=true);
            return;
        }
    }
}

GotoLastCharOfCurrentRow :: inline () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    index  := find_row_index(buffer, _cursor.pos);
    row    := row_table[index];
    offset := row_last_byte_offset(row);
    
    set_cursor_pos(buffer, *_cursor, offset, horizontal=true);
}

ExpandSelectionUp :: () {
    move_up_by_one_row(with_selection=false);
}

ExpandSelectionDown :: () {
    move_down_by_one_row(with_selection=false);
}

ExpandSelectionRight :: () {
    move_right_by_one_character(with_selection=false);
}

ExpandSelectionLeft :: () {
    move_left_by_one_character(with_selection=false);
}

////////////////////////////////////
//

register_keymap_procedures :: () {

    // Editor keymaps   
    k := *default_keymap;

    Keymap.add_proc(k, "ToggleDevInfo", ToggleDevInfo);
    Keymap.add_proc(k, "DrawSpecialChars", DrawSpecialChars);

    Keymap.add_proc(k, "Quit", Quit);
    Keymap.add_proc(k, "Save", Save);

    Keymap.add_proc(k, "CloseCurrentBuffer", CloseCurrentBuffer);
    Keymap.add_proc(k, "PrevBuffer", PrevBuffer);
    Keymap.add_proc(k, "NextBuffer", NextBuffer);

    ///////////////////////////

    Keymap.add_proc(k, "MoveUp", MoveUp);
    Keymap.add_proc(k, "MoveDown", MoveDown);
    Keymap.add_proc(k, "MoveLeft", MoveLeft);
    Keymap.add_proc(k, "MoveRight", MoveRight);

    Keymap.add_proc(k, "MoveLeftWord", MoveLeftWord);
    Keymap.add_proc(k, "MoveLeftSubword", MoveLeftSubword);
    Keymap.add_proc(k, "MoveRightWord", MoveRightWord);
    Keymap.add_proc(k, "MoveRightSubword", MoveRightSubword);

    Keymap.add_proc(k, "ScrollViewPortUp", ScrollViewPortUp);
    Keymap.add_proc(k, "ScrollViewPortDown", ScrollViewPortDown);

    Keymap.add_proc(k, "DeleteFromRight", DeleteFromRight);
    Keymap.add_proc(k, "DeleteFromLeft", DeleteFromLeft);
    
    Keymap.add_proc(k, "Copy", Copy);
    Keymap.add_proc(k, "Paste", Paste);
    Keymap.add_proc(k, "Cut", Cut);

    Keymap.add_proc(k, "DeleteEverythingFromLeft", DeleteEverythingFromLeft);
    Keymap.add_proc(k, "DeleteWordFromRight", DeleteWordFromRight);
    Keymap.add_proc(k, "DeleteSubwordFromRight", DeleteSubwordFromRight);
    
    Keymap.add_proc(k, "DeleteWordFromLeft", DeleteWordFromLeft);
    Keymap.add_proc(k, "DeleteSubwordFromLeft", DeleteSubwordFromLeft);

    Keymap.add_proc(k, "InsertTab", InsertTab);
    Keymap.add_proc(k, "InsertLine", InsertLine);
    Keymap.add_proc(k, "InsertLineBelow", InsertLineBelow);

    Keymap.add_proc(k, "GotoFirstCharOFCurrentRow", GotoFirstCharOFCurrentRow);
    Keymap.add_proc(k, "GotoLastCharOfCurrentRow", GotoLastCharOfCurrentRow);

    Keymap.add_proc(k, "ExpandSelectionUp", ExpandSelectionUp);
    Keymap.add_proc(k, "ExpandSelectionLeft", ExpandSelectionLeft);
    Keymap.add_proc(k, "ExpandSelectionDown", ExpandSelectionDown);
    Keymap.add_proc(k, "ExpandSelectionRight", ExpandSelectionRight);
}

init_keymaps :: () {
    register_keymap_procedures();
    success := Keymap.load_from_file(*default_keymap, "default", ".\\..\\default.keymap", false);
    assert(success, "Failed to load the 'default.keymap'");
}

default_keymap: Keymap.Keymap;