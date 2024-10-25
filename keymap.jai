register_keymap_procedures :: () {

    // Editor keymaps   
    k := *default_keymap;

    add_proc(k, "ToggleDevInfo", ToggleDevInfo);
    add_proc(k, "DrawSpecialChars", DrawSpecialChars);

    add_proc(k, "Quit", Quit);

    add_proc(k, "MoveUp", MoveUp);
    add_proc(k, "MoveDown", MoveDown);
    add_proc(k, "MoveLeft", MoveLeft);
    add_proc(k, "MoveRight", MoveRight);
    
    add_proc(k, "MoveLeftWord", MoveLeftWord);
    add_proc(k, "MoveLeftSubword", MoveLeftSubword);
    add_proc(k, "MoveRightWord", MoveRightWord);
    add_proc(k, "MoveRightSubword", MoveRightSubword);

    add_proc(k, "ScrollViewPortUp", ScrollViewPortUp);
    add_proc(k, "ScrollViewPortDown", ScrollViewPortDown);

    add_proc(k, "DeleteCharFromRight", DeleteCharFromRight);
    add_proc(k, "DeleteCharFromLeft", DeleteCharFromLeft);
    
    add_proc(k, "DeleteTheWholeLine", DeleteTheWholeLine);
    add_proc(k, "DeleteEverythingFromLeft", DeleteEverythingFromLeft);
    add_proc(k, "DeleteWordFromRight", DeleteWordFromRight);
    add_proc(k, "DeleteSubwordFromRight", DeleteSubwordFromRight);

    add_proc(k, "InsertTab", InsertTab);
    add_proc(k, "InsertLine", InsertLine);
    add_proc(k, "InsertLineBelow", InsertLineBelow);

    add_proc(k, "GotoFirstCharOFCurrentRow", GotoFirstCharOFCurrentRow);
    add_proc(k, "GotoLastCharOfCurrentRow", GotoLastCharOfCurrentRow);

    // add_proc(k, "OpenWidget", OpenWidget);
}

init_keymaps :: () {
    register_keymap_procedures();
    reload_keymap(*default_keymap, "default", "default.keymap", false);
}

default_keymap: Keymap;

///////////////////////////////
// EDITOR

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

MoveUp :: () {
    buffer := editor.active_buffer;
    using buffer;
    text := to_string(buffer);

    for row_table {
        if editor.cursor_pos <= it.pos {
            if it_index == 0 break; // no more row above
            prev_row := row_table[it_index-1];

            prev_row_cols := cols_in_the_row(text, prev_row);
            steps := min(prev_row_cols, editor.last_cursor_col_for_up_down_movement);
            pos := first_byte_pos(prev_row);
            while steps {
                byte := text[pos];
                bytes := 1 + trailingBytesForUTF8[byte];
                pos += bytes;
                steps -= 1;
            }

            set_cursor_pos(*editor, pos);
            break;
        }
    }
}

MoveDown :: () {
    buffer := editor.active_buffer;
    using buffer;
    text := to_string(buffer);

    for row_table {
        if editor.cursor_pos <= it.pos {
            if it_index == row_table.count-1 break; // no more row below
            next_row := row_table[it_index+1];

            next_row_cols := cols_in_the_row(text, next_row);
            steps := min(next_row_cols, editor.last_cursor_col_for_up_down_movement);
            pos := first_byte_pos(next_row);
            while steps {
                byte := text[pos];
                bytes := 1 + trailingBytesForUTF8[byte];
                pos += bytes;
                steps -= 1;
            }

            set_cursor_pos(*editor, pos);
            break;
        }
    }
}

MoveLeft :: () {
    using editor;

    if cursor_pos == 0 return;

    buffer := active_buffer;
    i := prev_char_byte_index(active_buffer, editor.cursor_pos);
    set_cursor_pos(*editor, i);

    // @Temporary @Cleanup keep the cursor on the same col when we move up or down (just like in vscode)
    // also we should update this value every time except when we move up or down
    last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
}

MoveRight :: () {
    buffer := editor.active_buffer;
    using buffer;
    text := to_string(buffer);

    if !(editor.cursor_pos < text.count) return;

    byte := text[editor.cursor_pos];
    steps := 1 + trailingBytesForUTF8[byte];
    set_cursor_pos(*editor, editor.cursor_pos + steps);

    editor.last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
}

move_left_word :: ($subword_mode: bool) {
    using editor;
    
    if cursor_pos == 0 return;

    text := to_string(active_buffer);

    if cursor_pos == active_buffer.count {
        i := prev_char_byte_index(active_buffer, cursor_pos);
        set_cursor_pos(*editor, i);
    }

    row_index := find_row_index(active_buffer, cursor_pos);
    row := active_buffer.row_table[row_index];

    offset := first_byte_pos(row);
    if offset == cursor_pos {
        if row_index == 0 return; // no more row above

        row = active_buffer.row_table[row_index-1];
        offset = first_byte_pos(row);
    }

    start := offset; // we use this as initial value, because offset-1 is a line break if row.count > 1
    end := prev_char_byte_index(active_buffer, cursor_pos);
    assert(end > -1);
    assert(end < text.count);

    // @Cleanup
    whitespace := is_whitespace(text[cursor_pos]) && is_whitespace(text[end]);
    if whitespace {
        last_non_whitespace_offset := cursor_pos;
        for start..end {
            if !is_whitespace(text[it]) {
                last_non_whitespace_offset = it;
            }
        }
        set_cursor_pos(*editor, last_non_whitespace_offset+1);
        last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
        return;
    }

    // @Cleanup
    if !is_separator_char(text[end], subword_mode) && !is_separator_char(text[cursor_pos], subword_mode) {
        for start..end {
            separator := is_separator_char(text[it], subword_mode);
            if separator {
                offset = it;
            }
        }
    } else {
        not_combined := is_separator_char(text[cursor_pos], subword_mode) && !is_separator_char(text[end], subword_mode);
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
        offset = next_char_byte_index(text, offset);
    }

    set_cursor_pos(*editor, offset);
    last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
}

move_right_word :: ($subword_mode: bool) {
    using editor;

    if cursor_pos == active_buffer.count return;

    text := to_string(active_buffer);
    start := next_char_byte_index(text, cursor_pos);

    // It's a better solution than the current IDE's behavior
    whitespace := is_whitespace(text[cursor_pos]);
    if whitespace {
        last_whitespace_offset := cursor_pos;
        for start..text.count-1 {
            last_whitespace_offset = it;
            if !is_whitespace(text[it]) break;
        }
        set_cursor_pos(*editor, last_whitespace_offset);
        last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
        return;
    }

    combined := is_separator_char(text[cursor_pos]);
    for start..text.count-1 {
        separator := is_separator_char(text[it], subword_mode);
        if combined {
            if !separator {
                set_cursor_pos(*editor, it);
                last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
                return;
            }
        } else {
            if separator {
                set_cursor_pos(*editor, it);
                last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
                return;
            }
        }
    }

    set_cursor_pos(*editor, text.count); // no more word so we should jump to the last byte of the row
    last_cursor_col_for_up_down_movement = get_cursor_col(*editor);
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
    buffer := editor.active_buffer;
    using buffer;

    text := to_string(buffer);

    start := first_visible_row_index(*editor, buffer);
    end := last_visible_row_index(buffer);
    max_row := clamp(end-start, 0, row_table.count-1);
    current_row := find_row_index(buffer, editor.cursor_pos);
    dest_row_index := clamp(current_row - max_row, 0, row_table.count-1);
    dest_row := row_table[dest_row_index];
    pos := first_byte_pos(dest_row);
    set_cursor_pos(*editor, pos);
}

ScrollViewPortDown :: () {
    buffer := editor.active_buffer;
    using buffer;

    start := first_visible_row_index(*editor, buffer);
    end := last_visible_row_index(buffer);
    max_row := clamp(end-start, 0, row_table.count-1);
    current_row := find_row_index(buffer, editor.cursor_pos);
    dest_row_index := clamp(current_row + max_row, 0, row_table.count-1);
    dest_row := row_table[dest_row_index];
    pos := first_byte_pos(dest_row);
    set_cursor_pos(*editor, pos);
}

DeleteTheWholeLine :: () {
    buffer := editor.active_buffer;

    row_index := find_row_index(buffer, editor.cursor_pos);
    row       := buffer.row_table[row_index];
    start     := first_byte_pos(row);
    end       := row.pos;
    
    set_cursor_pos(*editor, start); // jump to first col in the row

    if row_index+1 < buffer.row_table.count {
        next_row := buffer.row_table[row_index+1];
        end = first_byte_pos(next_row);
    }

    shift_left(buffer, start, end);

    assert(editor.cursor_pos <= buffer.count, "cursor: % ; buffer.count: %", editor.cursor_pos, buffer.count);
    if editor.cursor_pos > 0 && editor.cursor_pos == buffer.count then editor.cursor_pos -= 1;
}

DeleteEverythingFromLeft :: () {
    buffer := editor.active_buffer;

    row_index := find_row_index(buffer, editor.cursor_pos);
    row       := buffer.row_table[row_index];
    start     := editor.cursor_pos;
    end       := row.pos;

    shift_left(buffer, start, end);
}

DeleteCharFromRight :: () {
    using editor;

    if cursor_pos == 0 return;

    buffer := active_buffer;
    text := to_string(buffer);

    bytes_to_del := cursor_pos - prev_char_byte_index(buffer, cursor_pos);
    
    space_char := ifx draw_special_chars #char "~" else #char " ";  // @Temporary: this is a stupid fix for the special char visualization

    // Check if we should delete a "tab"
    ch := text.data[cursor_pos-1];
    if ch == space_char {
        i := 0;
        spaces := 1;
        for < cursor_pos-1..0 {
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
        to   := cursor_pos-bytes_to_del;
        from := cursor_pos;
        shift_left(buffer, to, from);
        set_cursor_pos(*editor, to);
    }
}

DeleteCharFromLeft :: () {
    buffer := editor.active_buffer;

    assert(editor.cursor_pos <= buffer.count);
    if editor.cursor_pos == buffer.count return;

    text := to_string(buffer);
    buffer.rebuild_row_table = true;

    byte := text[editor.cursor_pos];
    bytes_to_del := 1 + trailingBytesForUTF8[byte];
    assert(editor.cursor_pos + bytes_to_del <= text.count);

    to   := editor.cursor_pos;
    from := editor.cursor_pos+bytes_to_del;
    shift_left(buffer, to, from);
}

DeleteWordFromRight :: inline () {
    delete_word_or_subword_from_right(subword_mode=false);
}

DeleteSubwordFromRight :: inline () {
    delete_word_or_subword_from_right(subword_mode=true);
}

delete_word_or_subword_from_right :: ($subword_mode: bool) {
    if editor.cursor_pos == 0 return;

    buffer := editor.active_buffer;
    using buffer;
    using editor;

    text := to_string(buffer);
    rebuild_row_table = true;

    assert(text.count > 0); // it should never happen, 'cause we already checked the cursor poistion above
    start := cursor_pos-1;

    #if !subword_mode {
        // Delete all the whitespace until we find a non-whitespace character (only if the first deletable character from right is a whitespace)
        if text[start] == #char " " {
            for < index: start..0 {
                if text[index] != #char " " {
                    index += 1;
                    shift_left(buffer, index, cursor_pos);
                    set_cursor_pos(*editor, index);
                    return;
                }
            }
        }
    }

    if is_separator_char(text[cursor_pos-1], subword_mode) {
        DeleteCharFromRight();
        return;
    }

    for < index: start..0 {
        if is_separator_char(text[index], subword_mode) {
            index += 1;
            shift_left(buffer, index, cursor_pos);
            set_cursor_pos(*editor, index);
            return;
        } else if index == 0 {
            shift_left(buffer, 0, cursor_pos);
            set_cursor_pos(*editor, 0); 
            return;
        }
    }

}

InsertLine :: () {
    buffer := editor.active_buffer;
    using buffer;

    text := to_string(buffer);
    rebuild_row_table = true;

    if editor.cursor_pos == 0 {
        insert_text_at_cursor(*editor, buffer, "\n");
        return;
    }

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.

    current_row_index := find_row_index(buffer, editor.cursor_pos);
    row := row_table[current_row_index];
    start := first_byte_pos(row);
    end := find_index_from_left_until_not(text, #char " ", start);

    if end == -1 {
        // In this case we only have one row with only whitespace characters
        insert_text_at_cursor(*editor, buffer, "\n");
        return;
    }

    if editor.cursor_pos >= start && editor.cursor_pos < end {
        // We're in the range of the first n empty spaces, so we just jump to the first non-whitespace
        // occurrence to prevent the weird effect of splitting whitespace characters
        set_cursor_pos(*editor, end);
    }

    insert_text_at_cursor(*editor, buffer, "\n");

    spaces := end - start;
    assert(spaces > -1);
    while spaces != 0 {
        insert_text_at_cursor(*editor, buffer, " ");
        spaces -= 1;
    }
}

InsertLineBelow :: () {
    buffer := editor.active_buffer;
    using buffer;
    
    text := to_string(buffer);
    rebuild_row_table = true;

    current_row_index := find_row_index(buffer, editor.cursor_pos);
    row := row_table[current_row_index];
    set_cursor_pos(*editor, row.pos);             // set cursor to the last character of the current row
    insert_text_at_cursor(*editor, buffer, "\n"); // also we do a character step in this procedure

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.
    row_first_byte_index := first_byte_pos(row);
    first_non_whitespace_byte_index := find_index_from_left_until_not(text, #char " ", row_first_byte_index);
    if first_non_whitespace_byte_index != -1 {
        spaces := first_non_whitespace_byte_index - row_first_byte_index;
        assert(spaces > -1);
        while spaces != 0 {
            insert_text_at_cursor(*editor, buffer, " ");
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

    insert_text_at_cursor(*editor, editor.active_buffer, TAB_SPACE_CHARS);
}

GotoFirstCharOFCurrentRow :: inline () {
    buffer := editor.active_buffer;

    index := find_row_index(buffer, editor.cursor_pos);
    row   := buffer.row_table[index];
    start := first_byte_pos(row);

    for start..row.pos {
        if buffer.data[it] != #char " " { // skip the indentation
            set_cursor_pos(*editor, it);
            break;
        }
    }
}

GotoLastCharOfCurrentRow :: inline () {
    index  := find_row_index(editor.active_buffer, editor.cursor_pos);
    row    := editor.active_buffer.row_table[index];
    offset := last_byte_pos(row);
    set_cursor_pos(*editor, offset);
}