// [Core]

Quit :: () {
    should_quit = true;
}

// [Widget]

CloseCurrentWidget :: () {
    close_current_widget();
}

// [Editor]

SwitchOrSplitEditorPanel :: () {
    c := active_editor;

    if !editors[1].visible {
        editors[1].visible = true;
        active_editor = *editors[1];
        return;
    }

    if      *editors[0] == active_editor then active_editor = *editors[1];
    else if *editors[1] == active_editor then active_editor = *editors[0];
}

HideSecondEditorPanel :: () {
    active_editor = *editors[0];
    
    editors[1].visible = false;
}

CreateBuffer :: () {
    editor, _ := get_active_editor_and_buffer();
    editor.active_buffer = create_or_find_empty_buffer(editor);
}

CloseCurrentBuffer :: () {
    _, buffer := get_active_editor_and_buffer();
    assert(buffer != null);

    close_buffer(buffer);
}

PrevBuffer :: () {
    editor, buffer := get_active_editor_and_buffer();
    using editor;

    count := count_buffers(editor, initialized=true);
    if count < 2 return;

    found, index := find_buffer_index(buffer);
    assert(found, "-> %\n", buffer.*);

    prev_buffer: *Buffer;
    for < * buffers {
        if it_index < index && it.initialized {
            prev_buffer = it;
            break;
        }
    }

    if !prev_buffer {
        for < * buffers {
            if it.initialized {
                prev_buffer = it;
                break;
            }
        }
    }

    assert(prev_buffer != null);
    change_active_buffer(editor, prev_buffer);
}

NextBuffer :: () {
    editor, buffer := get_active_editor_and_buffer();
    using editor;

    count := count_buffers(editor, initialized=true);
    if count < 2 return;

    found, index := find_buffer_index(buffer);
    assert(found, "-> %\n", buffer.*);

    next_buffer: *Buffer;
    for * buffers {
        if it_index > index && it.initialized {
            next_buffer = it;
            break;
        }
    }

    if !next_buffer {
        for * buffers {
            if it.initialized {
                next_buffer = it;
                break;
            }
        }
    }

    assert(next_buffer != null);
    change_active_buffer(editor, next_buffer);
}

Save :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if filepath {
        s := to_string(buffer);
        File.write_entire_file(filepath, s);
        dirty = false;
    } else {
        log_error("[TODO]: File save modal is not implemented yet!\n");
    }
}

ToggleDevInfo :: () {
    show_debug_info = !show_debug_info;
}

move_up_by_one_row :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    c := *editor.cursor;

    ri := find_row_index(buffer, c.pos);
    if ri-1 < 0 return;

    prev_row := row_table[ri-1];
    col := 0;
    pos := prev_row.start;
    while pos < prev_row.end {
        if col == c.col break;
        col += 1;
        pos += 1 + trailingBytesForUTF8[buffer.data[pos]];
    }

    set_cursor_pos(buffer, c, pos, with_selection=with_selection);
}

MoveUp :: () {
    move_up_by_one_row();
}

move_down_by_one_row :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    c := *editor.cursor;

    ri := find_row_index(buffer, c.pos);
    if ri+1 == row_table.count return;

    next_row := row_table[ri+1];
    col := 0;
    pos := next_row.start;
    while pos < next_row.end {
        if col == c.col break;
        col += 1;
        pos += 1 + trailingBytesForUTF8[buffer.data[pos]];
    }

    set_cursor_pos(buffer, c, pos, with_selection=with_selection);
}

MoveDown :: () {
    move_down_by_one_row();
}

move_left_by_one_character :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    
    if editor.cursor.pos == 0 return;

    offset := prev_char_byte_offset(buffer, editor.cursor.pos);
    
    set_cursor_pos(buffer, *editor.cursor, offset, horizontal=true, with_selection=with_selection);
}

MoveLeft :: () {
    move_left_by_one_character();
}

move_right_by_one_character :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    
    if !(editor.cursor.pos < buffer.count) return;

    byte := buffer.data[editor.cursor.pos];
    steps := 1 + trailingBytesForUTF8[byte];
    
    set_cursor_pos(buffer, *editor.cursor, editor.cursor.pos + steps, horizontal=true, with_selection=with_selection);
}

MoveRight :: () {
    move_right_by_one_character();
}

move_left_word :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;
    
    if editor.cursor.pos == 0 return;

    if editor.cursor.pos == buffer.count {
        offset := prev_char_byte_offset(buffer, editor.cursor.pos);
        set_cursor_pos(buffer, *editor.cursor, offset, horizontal=true);
    }

    row_index := find_row_index(buffer, editor.cursor.pos);    
    row := row_table[row_index];

    offset := row.start;
    if offset == editor.cursor.pos {
        if row_index == 0 return; // no more row above

        row = row_table[row_index-1];
        offset = row.start;
    }

    text := to_string(buffer);

    start := offset; // we use this as initial value, because offset-1 is a line break if row.count > 1
    end := prev_char_byte_offset(buffer, editor.cursor.pos);
    assert(end > -1);
    assert(end < text.count);

    // @Cleanup
    whitespace := is_whitespace(text[editor.cursor.pos]) && is_whitespace(text[end]);
    if whitespace {
        last_non_whitespace_offset := editor.cursor.pos;
        for start..end {
            if !is_whitespace(text[it]) {
                last_non_whitespace_offset = it;
            }
        }
        new_pos := last_non_whitespace_offset+1;
        if new_pos > editor.cursor.pos new_pos = last_non_whitespace_offset;
        if new_pos == editor.cursor.pos new_pos = max(0, editor.cursor.pos-1);
        set_cursor_pos(buffer, *editor.cursor, new_pos, horizontal=true);
        return;
    }

    // @Cleanup
    if !is_separator(text[end], subword_mode) && !is_separator(text[editor.cursor.pos], subword_mode) {
        for start..end {
            separator := is_separator(text[it], subword_mode);
            if separator {
                offset = it;
            }
        }
    } else {
        not_combined := is_separator(text[editor.cursor.pos], subword_mode) && !is_separator(text[end], subword_mode);
        for start..end {
            separator := is_separator(text[it], subword_mode);
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
        offset += 1 + trailingBytesForUTF8[text[offset]];
    }

    set_cursor_pos(buffer, *editor.cursor, offset, horizontal=true);
}

move_right_word :: ($subword_mode: bool) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if editor.cursor.pos == buffer.count return;

    text  := to_string(buffer);
    start := editor.cursor.pos + 1 + trailingBytesForUTF8[text[editor.cursor.pos]];

    // It's a better solution than the current IDE's behavior
    whitespace := is_whitespace(text[editor.cursor.pos]);
    if whitespace {
        last_whitespace_offset := editor.cursor.pos;
        for start..text.count-1 {
            last_whitespace_offset = it;
            if !is_whitespace(text[it]) break;
        }
        set_cursor_pos(buffer, *editor.cursor, last_whitespace_offset, horizontal=true);
        return;
    }

    combined := is_separator(text[editor.cursor.pos]);
    for start..text.count-1 {
        separator := is_separator(text[it], subword_mode);
        if combined {
            if !separator {
                set_cursor_pos(buffer, *editor.cursor, it, horizontal=true);
                return;
            }
        } else {
            if separator {
                set_cursor_pos(buffer, *editor.cursor, it, horizontal=true);
                return;
            }
        }
    }

    set_cursor_pos(buffer, *editor.cursor, text.count, horizontal=true); // no more word so we should jump to the last byte of the row
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

move_viewport_up :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    start := first_visible_row_index(editor, buffer);
    end := last_visible_row_index(editor, buffer);
    max_row := clamp(end-start, 0, row_table.count-1);
    
    current_row_index := find_row_index(buffer, editor.cursor.pos);
    if current_row_index == 0 return;

    dest_row_index := clamp(current_row_index - max_row, 0, row_table.count-1);
    dest_row    := row_table[dest_row_index];
    dest_pos    := dest_row.start;
    dest_col    := 0;
    current_col := editor.cursor.col;
    
    s := get_row_as_string(buffer, dest_row);
    while s.count {
        if dest_col == current_col break;

        bytes := 1 + trailingBytesForUTF8[s[0]];
        advance(*s, bytes);

        dest_pos += bytes;
        dest_col += 1;
    }

    set_cursor_pos(buffer, *editor.cursor, dest_pos, horizontal=false, with_selection=with_selection);
}

ScrollViewPortUp :: () {
    move_viewport_up();
}

move_viewport_down :: ($with_selection := true) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    start := first_visible_row_index(editor, buffer);
    end := last_visible_row_index(editor, buffer);
    max_row := clamp(end-start, 0, row_table.count-1);

    current_row_index := find_row_index(buffer, editor.cursor.pos);
    if current_row_index == row_table.count-1 return;

    dest_row_index := clamp(current_row_index + max_row, 0, row_table.count-1);
    dest_row    := row_table[dest_row_index];
    dest_pos    := dest_row.start;
    dest_col    := 0;
    current_col := editor.cursor.col;

    s := get_row_as_string(buffer, dest_row);
    while s.count {
        if dest_col == current_col break;

        bytes := 1 + trailingBytesForUTF8[s[0]];
        advance(*s, bytes);

        dest_pos += bytes;
        dest_col += 1;
    }

    set_cursor_pos(buffer, *editor.cursor, dest_pos, horizontal=false, with_selection=with_selection);
}

ScrollViewPortDown :: () {
    move_viewport_down();
}

Copy :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    // Should we move this whole logic into the copy_selection_to_os_clipboard() procedure?

    if has_selection(editor.cursor) {
        copy_selection_to_os_clipboard(buffer, *editor.cursor);
        return;
    }

    row := find_row(buffer, editor.cursor.pos);
    if row.size {
        s := get_row_as_string(buffer, row);
        Clipboard.os_clipboard_set_text(s);    
        return;
    }

    Clipboard.os_clipboard_set_text("\n");
}

Paste :: () {
    editor, buffer := get_active_editor_and_buffer();
    insert_os_clipboard_text_at_cursor(editor, buffer, *editor.cursor);
}

Cut :: () {
    editor, buffer := get_active_editor_and_buffer();
    using,except(rebuild_row_table) buffer;

    if has_selection(editor.cursor) {
        cut_selection_and_copy_to_os_clipboard(editor, buffer, *editor.cursor);
        return;
    }

    // Cut the whole line
    row_index := find_row_index(buffer, editor.cursor.pos);
    row       := row_table[row_index];
    
    editor.cursor.pos = row.start;
    editor.cursor.sel = next_character_pos(buffer, row.end);

    cut_selection_and_copy_to_os_clipboard(editor, buffer, *editor.cursor);
}

DeleteEverythingFromLeft :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    range_deleted := delete_selected_range_if_has_any(editor, buffer, *editor.cursor);
    if range_deleted return;

    row_index := find_row_index(buffer, editor.cursor.pos);
    row       := row_table[row_index];
    start     := editor.cursor.pos;
    end       := row.end;

    remove_text_from_left(editor, buffer, start, end - start);
}

DeleteFromRight :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    range_deleted := delete_selected_range_if_has_any(editor, buffer, *editor.cursor);
    if range_deleted return;

    if editor.cursor.pos == 0 return;

    text := to_string(buffer);
    bytes_to_del := editor.cursor.pos - prev_char_byte_offset(buffer, editor.cursor.pos);

    // Check if we should delete a "tab"
    ch := text.data[editor.cursor.pos-1];
    if ch == #char " " {
        i := 0;
        spaces := 1;
        for #v2 < 0..editor.cursor.pos-1 {
            if text.data[it] == #char " " {
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
        remove_text_from_right_at_cursor(editor, buffer, *editor.cursor, bytes_to_del);
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

    delete_selected_range_if_has_any(editor, buffer, *editor.cursor);

    text := to_string(buffer);
    if text.count == 0 || editor.cursor.pos == text.count return;

    byte := text[editor.cursor.pos];
    if is_whitespace(byte) {
        for point: editor.cursor.pos..text.count-1 {
            if !is_whitespace(text[point]) {
                remove_text_from_left(editor, buffer, editor.cursor.pos, point - editor.cursor.pos);
                return;
            }    
        }
    }

    for point: editor.cursor.pos..text.count-1 {
        if is_separator(text[point], subword_mode) {
            if editor.cursor.pos == point {
                point = min(point+1, text.count-1); // @Improve: Detect combined separator characters 
            }

            remove_text_from_left(editor, buffer, editor.cursor.pos, point - editor.cursor.pos);
            return;
        }
    }

    remove_text_from_left(editor, buffer, editor.cursor.pos, text.count); // We have no separator character at the end
}

DeleteFromLeft :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    range_deleted := delete_selected_range_if_has_any(editor, buffer, *editor.cursor);
    if range_deleted return;

    assert(editor.cursor.pos <= buffer.count);
    if editor.cursor.pos == buffer.count return;

    text := to_string(buffer);

    byte := text[editor.cursor.pos];
    bytes_to_del := 1 + trailingBytesForUTF8[byte];
    assert(editor.cursor.pos + bytes_to_del <= text.count);

    remove_text_from_left(editor, buffer, editor.cursor.pos, bytes_to_del);
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

    range_deleted := delete_selected_range_if_has_any(editor, buffer, *editor.cursor);
    if range_deleted return;

    if editor.cursor.pos == 0 return;

    text := to_string(buffer);

    assert(text.count > 0); // it should never happen, 'cause we already checked the cursor poistion above
    start := editor.cursor.pos-1;

    #if !subword_mode {
        // Delete all the whitespace until we find a non-whitespace character (only if the first deletable character from right is a whitespace)
        if text[start] == #char " " {
            for #v2 < point: 0..start {
                if text[point] != #char " " {
                    point += 1;
                    remove_text_from_right_at_cursor(editor, buffer, *editor.cursor, editor.cursor.pos - point);
                    return;
                }
            }
        }
    }

    if is_separator(text[editor.cursor.pos-1], subword_mode) {
        DeleteFromRight();
        return;
    }

    for #v2 < point: 0..start {
        if is_separator(text[point], subword_mode) {
            point += 1;
            remove_text_from_right_at_cursor(editor, buffer, *editor.cursor, editor.cursor.pos - point);
            return;
        } else if point == 0 {
            remove_text_from_right_at_cursor(editor, buffer, *editor.cursor, editor.cursor.pos - point);
            return;
        }
    }

}

InsertLine :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    delete_selected_range_if_has_any(editor, buffer, *editor.cursor);

    text := to_string(buffer);

    if editor.cursor.pos == 0 {
        insert_text_at_cursor(editor, buffer, *editor.cursor, "\n");
        return;
    }

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.

    current_row_index := find_row_index(buffer, editor.cursor.pos);
    row := row_table[current_row_index];
    start := row.start;
    end := find_index_from_left_until_not(text, #char " ", start);

    if end == -1 {
        // In this case we only have one row with only whitespace characters
        insert_text_at_cursor(editor, buffer, *editor.cursor, "\n");
        return;
    }

    if editor.cursor.pos >= start && editor.cursor.pos < end {
        // We're in the range of the first n empty spaces, so we just jump to the first non-whitespace
        // occurrence to prevent the weird effect of splitting whitespace characters
        set_cursor_pos(buffer, *editor.cursor, end);
    }

    insert_text_at_cursor(editor, buffer, *editor.cursor, "\n");

    spaces := end - start;
    assert(spaces > -1);
    while spaces != 0 {
        insert_text_at_cursor(editor, buffer, *editor.cursor, " ");
        spaces -= 1;
    }
}

InsertLineBelow :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;
    
    text := to_string(buffer);

    current_row_index := find_row_index(buffer, editor.cursor.pos);
    row := row_table[current_row_index];
    set_cursor_pos(buffer, *editor.cursor, row.end);    // set cursor to the last character of the current row
    insert_text_at_cursor(editor, buffer, *editor.cursor, "\n");          // also increment the cursor by a character in this procedure

    // :SmartIndentFeature @Cleanup
    // A basic smart indent count characters in the current row until the first non-space character.
    row_first_byte_index := row.start;
    first_non_whitespace_byte_index := find_index_from_left_until_not(text, #char " ", row_first_byte_index);
    if first_non_whitespace_byte_index != -1 {
        spaces := first_non_whitespace_byte_index - row_first_byte_index;
        assert(spaces > -1);
        while spaces != 0 {
            insert_text_at_cursor(editor, buffer, *editor.cursor, " ");
            spaces -= 1;
        }
    }
}

JoinLine :: () {
    editor, buffer := get_active_editor_and_buffer();

    if has_selection(editor.cursor) {
        // @Todo: Handle selection, join rows within the selected range

    } else {
        row := find_row(buffer, editor.cursor.pos);
        if row.end + 1 < buffer.count {
            s := to_string(buffer);
            assert(s[row.end] == #char "\n");

            trimmed_whitespaces := 0;
            next_row := find_row(buffer, row.end + 1);
            t1 := slice(buffer, next_row.start, next_row.size);
            if t1 {
                t2 := trim_left(t1, " ");
                if t2 then trimmed_whitespaces = t2.data - t1.data;
            }

            line := get_row_as_string(buffer, row);
            line = trim_right(line, " ");
            trimmed_from_right := (buffer.data + row.end) - (line.data + line.count);
            new_row_end := row.end - trimmed_from_right;

            set_cursor_pos(buffer, *editor.cursor, new_row_end, horizontal=true);
            
            bytes_to_del := (next_row.start + trimmed_whitespaces) - new_row_end;
            remove_text_from_left_at_cursor(editor, buffer, *editor.cursor, bytes_to_del);

            if buffer.data[new_row_end] != #char " " {
                // We don't want to step to the space character which separates the two joined lines.
                insert_text_at(editor, buffer, editor.cursor.pos, " ");
            }
        }
    }

}

InsertTab :: () {
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

    insert_text_at_cursor(editor, buffer, *editor.cursor, TAB_SPACE_CHARS);
}

GotoFirstCharOfCurrentRow :: inline () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    row := find_row(buffer, editor.cursor.pos);
    for at: row.start..row.end {
        if buffer.data[at] != #char " " { // skip the indentation
            if at == editor.cursor.pos then at = row.start;
            set_cursor_pos(buffer, *editor.cursor, at, horizontal=true, with_selection=!ShiftHeld());
            return;
        }
    }
}

GotoLastCharOfCurrentRow :: inline () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    row := find_row(buffer, editor.cursor.pos);

    // @Cleanup Confusing the with_selection thing, 'cause it means that we also move the selection cursor with the primary cursor!!
    set_cursor_pos(buffer, *editor.cursor, row.end, horizontal=true, with_selection=!ShiftHeld());
}

ExpandSelectionByLine :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if has_selection(editor.cursor) {
        row_index := find_row_index(buffer, editor.cursor.pos);
        dest_cursor_pos := row_table[row_index].end;
        if row_index + 1 < row_table.count {
            dest_cursor_pos = row_table[row_index + 1].start;
        }

        set_cursor_pos(buffer, *editor.cursor, dest_cursor_pos, horizontal=true, with_selection=false);

        row_index   = find_row_index(buffer, editor.cursor.sel);
        editor.cursor.sel = row_table[row_index].start;

    } else {
        row_index := find_row_index(buffer, editor.cursor.pos);

        dest_cursor_sel := row_table[row_index].start;
        dest_cursor_pos := row_table[row_index].end;
        
        if row_index + 1 < row_table.count {
            dest_cursor_pos = row_table[row_index + 1].start;
        }

        set_cursor_pos(buffer, *editor.cursor, dest_cursor_pos, horizontal=true, with_selection=false);
        editor.cursor.sel = dest_cursor_sel;
    }

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

// HACKY!
ExpandSelectionLeftByWord :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    tmp := editor.cursor.sel;
    defer editor.cursor.sel = tmp;

    move_left_word(subword_mode=false);
}

// HACKY!
ExpandSelectionRightbyWord :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    tmp := editor.cursor.sel;
    defer editor.cursor.sel = tmp;

    move_right_word(subword_mode=false);
}

ExpandSelectionViewPortUp :: () {
    move_viewport_up(with_selection=false);
}

ExpandSelectionViewPortDown :: () {
    move_viewport_down(with_selection=false);
}

// @Cleanup: Gosh...
IndentLeft :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    c := *editor.cursor;

    cpos_after := c.pos;
    cpos_row_index := find_row_index(buffer, c.pos);
    csel_after := c.sel;
    csel_row_index := find_row_index(buffer, c.sel);

    block_lines: [..] string;
    block_lines.allocator = temp;

    rows: [..] Row_Info;
    rows.allocator = temp;

    start, end := selected_range(c);
    at := start;
    while at <= end {
        row_index := find_row_index(buffer, at);
        row       := row_table[row_index];
        array_add(*rows, row);

        s := get_row_as_string(buffer, row);
        spaces := count_whitespaces_from_left(s, space_character_only=true);
        del := TAB_SIZE_IN_SPACES;
        if spaces < TAB_SIZE_IN_SPACES then del = spaces;
        new_s := advance(s, del);
        array_add(*block_lines, new_s);

        if row_index <= cpos_row_index {
            cpos_after -= del;
        }

        if row_index <= csel_row_index {
            csel_after -= del;
        }

        at = row.end + 1;
    }

    new_block: string;
    for s: block_lines {
        new_block = tprint("%1%2", new_block, s);
        if it_index != block_lines.count-1 {
            new_block = tprint("%1\n", new_block);
        }
    }

    start = rows[0].start;
    end   = rows[rows.count-1].end;
    replace_text_at(editor, buffer, Range.{start, end}, new_block);

    commit_buffer_changes(buffer);

    // STUPID CORRECTION!
    if find_row_index(buffer, cpos_after) != cpos_row_index {
        cpos_after = row_table[cpos_row_index].start;
    }
    if find_row_index(buffer, csel_after) != csel_row_index {
        csel_after = row_table[csel_row_index].start;
    }

    c.pos = cpos_after;
    c.sel = csel_after;
    clamp_cursor(c, buffer.count);

    c.col = byte_pos_to_row_col_index(buffer, c.pos);

    // set_cursor_pos(buffer, c, cpos_after, horizontal=true, with_selection=!has_selection(c));
}

// @Incomplete: It has some bugs!
IndentRight :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    c := *editor.cursor;
    ca, cb := get_cursor_min_max_indecies_as_pointers(c);
    ca_row_index := find_row_index(buffer, ca.*);
    cb_row_index := find_row_index(buffer, cb.*);

    block_lines: [..] string;
    block_lines.allocator = temp;

    rows: [..] Row_Info;
    rows.allocator = temp;

    start, end := selected_range(c);
    at := start;
    while at <= end {
        row_index := find_row_index(buffer, at);
        row       := row_table[row_index];
        array_add(*rows, row);

        s := get_row_as_string(buffer, row);
        spaces := count_whitespaces_from_left(s, space_character_only=true);
        rem := spaces % TAB_SIZE_IN_SPACES;
        add := TAB_SIZE_IN_SPACES - rem;

        new_s := alloc_string(s.count + add,, temp);
        new_s.count = s.count + add;
        memset(new_s.data, #char " ", spaces + add);
        memcpy(new_s.data + spaces + add, s.data+spaces, s.count-spaces);
        array_add(*block_lines, new_s);

        if row_index <= ca_row_index {
            ca.* += add;
        }
        if row_index <= cb_row_index {
            cb.* += add;
        }

        at = row.end + 1;
    }

    new_block: string;
    for s: block_lines {
        new_block = tprint("%1%2", new_block, s);
        if it_index != block_lines.count-1 {
            new_block = tprint("%1\n", new_block);
        }
    }

    start = rows[0].start;
    end   = rows[rows.count-1].end;
    replace_text_at(editor, buffer, Range.{start, end}, new_block);

    commit_buffer_changes(buffer);

    clamp_cursor(c, buffer.count);
    c.col = byte_pos_to_row_col_index(buffer, c.pos);
}

// @Incomplete !!!
ExtendSelectionByToken :: () {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    s := to_string(buffer);
    advance(*s, editor.cursor.pos);

    if !s return;
    if !is_alphanum(s[0]) return;

    t := s;
    while t {
        if is_separator(t[0], include_underscore=false) {
            ident := slice(buffer, editor.cursor.pos, t.data - s.data);
            set_cursor_pos(buffer, *editor.cursor, editor.cursor.pos + ident.count, horizontal=true, with_selection=false);
            break;
        }

        advance(*t, 1 + trailingBytesForUTF8[t[0]]);
    }

    // @Incomplete: Currently, we are working with one cursor instance per buffer
}

Undo :: () {
    editor, buffer := get_active_editor_and_buffer();
    undo(editor, buffer);
}

Redo :: () {
    editor, buffer := get_active_editor_and_buffer();
    redo(editor, buffer);
}

////////////////////////////////////
//

register_keymap_procedures :: () {

    core_keymap   = add_keymap(*keymap_set, "Core");
    widget_keymap = add_keymap(*keymap_set, "Widget");
    editor_keymap = add_keymap(*keymap_set, "Editor");

    Add :: (k: *Keymap, ident: Code) #expand {
        add_proc(k, #run CodeInspect.get_identifier_name(ident), #insert ident);
    }

    // Core
    
    Add(core_keymap, Quit);

    // Widget

    Add(widget_keymap, CloseCurrentWidget);
    
    Add(editor_keymap, open_find_text_dialog);
    Add(editor_keymap, open_file_browser);
    Add(editor_keymap, open_buffer_browser);

    // Editor

    Add(editor_keymap, SwitchOrSplitEditorPanel);
    Add(editor_keymap, HideSecondEditorPanel);

    Add(editor_keymap, ToggleDevInfo);

    Add(editor_keymap, CreateBuffer);
    Add(editor_keymap, CloseCurrentBuffer);
    Add(editor_keymap, PrevBuffer);
    Add(editor_keymap, NextBuffer);

    Add(editor_keymap, Save);

    Add(editor_keymap, InsertTab);
    Add(editor_keymap, InsertLine);
    Add(editor_keymap, InsertLineBelow);
    Add(editor_keymap, JoinLine);

    Add(editor_keymap, Copy);
    Add(editor_keymap, Paste);
    Add(editor_keymap, Cut);

    Add(editor_keymap, MoveUp);
    Add(editor_keymap, MoveDown);
    Add(editor_keymap, MoveLeft);
    Add(editor_keymap, MoveRight);
    Add(editor_keymap, MoveLeftWord);
    Add(editor_keymap, MoveLeftSubword);
    Add(editor_keymap, MoveRightWord);
    Add(editor_keymap, MoveRightSubword);
    Add(editor_keymap, ScrollViewPortUp);
    Add(editor_keymap, ScrollViewPortDown);
    Add(editor_keymap, GotoFirstCharOfCurrentRow);
    Add(editor_keymap, GotoLastCharOfCurrentRow);

    Add(editor_keymap, DeleteFromRight);
    Add(editor_keymap, DeleteFromLeft);
    Add(editor_keymap, DeleteEverythingFromLeft);
    Add(editor_keymap, DeleteWordFromRight);
    Add(editor_keymap, DeleteSubwordFromRight);    
    Add(editor_keymap, DeleteWordFromLeft);
    Add(editor_keymap, DeleteSubwordFromLeft);

    Add(editor_keymap, ExpandSelectionByLine);
    Add(editor_keymap, ExpandSelectionUp);
    Add(editor_keymap, ExpandSelectionLeft);
    Add(editor_keymap, ExpandSelectionDown);
    Add(editor_keymap, ExpandSelectionRight);
    Add(editor_keymap, ExpandSelectionLeftByWord);
    Add(editor_keymap, ExpandSelectionRightbyWord);
    Add(editor_keymap, ExpandSelectionViewPortUp);
    Add(editor_keymap, ExpandSelectionViewPortDown);

    Add(editor_keymap, ExtendSelectionByToken);

    Add(editor_keymap, IndentLeft);
    Add(editor_keymap, IndentRight);

    Add(editor_keymap, Undo);
    Add(editor_keymap, Redo);
}

init_keymaps :: () {
    register_keymap_procedures();

    // @Incomplete
    // if !file_exists("default.keymap") {
    //     write_entire_file("default.keymap", DEFAULT_KEYMAP_CONFIG);
    // }
    // success := load_from_file(*keymap_set, "default", "default.keymap", false);

    success := load_from_memory(*keymap_set, DEFAULT_KEYMAP_CONFIG, "default");
    
    assert(success, "Failed to load the 'default.keymap'");
}

// handle_keymaps_event :: (event: Event) -> (handled: bool) {
//     current_keymap_event = *event;
//     return keymap_handle_event(default_keymap, event);
// }

keymap_set: Keymap_Set;

core_keymap:   *Keymap;
editor_keymap: *Keymap;
widget_keymap: *Keymap;

last_input_event: Event = ---;

// @Cleanup
ShiftHeld :: () -> bool #expand {
    return last_input_event.shift_pressed;
}

DEFAULT_KEYMAP_CONFIG :: #string DONE 
[1]

[Core]

A-F4 Quit

[Widget]

ESC CloseCurrentWidget

[Editor]

C-, SwitchOrSplitEditorPanel
A-w HideSecondEditorPanel

C-f open_find_text_dialog
C-o open_file_browser
A-x open_buffer_browser

F1 ToggleDevInfo

C-n CreateBuffer
C-w CloseCurrentBuffer
C-PageUp NextBuffer
C-PageDown PrevBuffer
C-s Save

ArrowLeft MoveLeft
ArrowUp MoveUp
ArrowDown MoveDown
ArrowRight MoveRight

C-ArrowLeft MoveLeftWord
A-ArrowLeft MoveLeftSubword
C-ArrowRight MoveRightWord
A-ArrowRight MoveRightSubword

PageUp ScrollViewPortUp
PageDown ScrollViewPortDown

Home GotoFirstCharOfCurrentRow
A-Home GotoLastCharOfCurrentRow
S-Home GotoFirstCharOfCurrentRow
A-S-Home GotoLastCharOfCurrentRow

TAB InsertTab
ENTER InsertLine
C-ENTER InsertLineBelow
C-j JoinLine

C-c Copy
C-v Paste
C-x Cut

C-k DeleteEverythingFromLeft

Delete DeleteFromLeft
C-Delete DeleteWordFromLeft
A-Delete DeleteSubwordFromLeft

Backspace DeleteFromRight
C-Backspace DeleteWordFromRight
A-Backspace DeleteSubwordFromRight

C-l ExpandSelectionByLine
S-ArrowUp ExpandSelectionUp
S-ArrowLeft ExpandSelectionLeft
S-ArrowDown ExpandSelectionDown
S-ArrowRight ExpandSelectionRight
C-S-ArrowLeft ExpandSelectionLeftByWord
C-S-ArrowRight ExpandSelectionRightbyWord
C-S-PageUp ExpandSelectionViewPortUp
C-S-PageDown ExpandSelectionViewPortDown

C-d ExtendSelectionByToken

C-] IndentRight
C-[ IndentLeft

C-z Undo
C-y Redo

DONE;

#import "Keymap";