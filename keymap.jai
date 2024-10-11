register_keymap_procedures :: () {
    k := *default_keymap;

    // Editor keymaps   
    add_proc(k, "DeleteCharFromRight", DeleteCharFromRight);
    add_proc(k, "DeleteCharFromLeft", DeleteCharFromLeft);
    
    add_proc(k, "DeleteTheWholeLine", DeleteTheWholeLine);
    add_proc(k, "DeleteEverythingFromLeft", DeleteEverythingFromLeft);
    add_proc(k, "DeleteWordFromRight", DeleteWordFromRight);
    add_proc(k, "DeleteSubwordFromRight", DeleteSubwordFromRight);

    add_proc(k, "InsertTab", InsertTab);
}

///////////////////////////////
// EDITOR

DeleteTheWholeLine :: () {
    // @Speed !!!!
    text := builder_to_string(*builder, do_reset = true);
    defer free(text);

    row_index := get_cursor_row(text) - 1;
    row := row_table[row_index];
    start := first_row_col(row);
    end := row.pos;
    
    set_cursor_pos(start);

    if row_index+1 < row_table.count {
        next_row := row_table[row_index+1];
        end = first_row_col(next_row);
    }

    before := slice(text, 0, start);
    after := slice(text, end, text.count);

    append(*builder, before);
    append(*builder, after);

    len := builder_string_length(*builder);
    if cursor_pos > len set_cursor_pos(len);

    should_rebuild_row_table = true;
}

DeleteEverythingFromLeft :: () {
    // @Speed !!!!
    text := builder_to_string(*builder, do_reset = true);
    defer free(text);

    row_index := get_cursor_row(text) - 1;
    row := row_table[row_index];
    start := cursor_pos;
    end := row.pos;

    before := slice(text, 0, start);
    after := slice(text, end, text.count);

    append(*builder, before);
    append(*builder, after);

    should_rebuild_row_table = true;
}

DeleteCharFromRight :: () {
    if cursor_pos == 0 return;

    // @Speed !!!!
    text := builder_to_string(*builder, do_reset = true);
    defer free(text);

    bytes_to_del := cursor_pos - prev_char_byte_index(text);
    
    // Check if we should delete a "tab"
    ch := text.data[cursor_pos-1];
    if ch == #char " " {
        i := 0;
        spaces := 1;
        for < cursor_pos-1..0 {
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
        before := slice(text, 0, cursor_pos-bytes_to_del); 
        after := slice(text, cursor_pos, text.count);
        append(*builder, before);
        append(*builder, after);
        set_cursor_pos(cursor_pos-bytes_to_del);
        should_rebuild_row_table = true;
    }
}

DeleteCharFromLeft :: () {
    if !(cursor_pos < builder_string_length(*builder)) return;

    // @Speed !!!!
    text := builder_to_string(*builder, do_reset = true);
    defer free(text);
    should_rebuild_row_table = true;

    byte := text[cursor_pos];
    bytes_to_del := 1 + trailingBytesForUTF8[byte];
    assert(cursor_pos+bytes_to_del <= text.count);

    before := slice(text, 0, cursor_pos); 
    after := slice(text, cursor_pos+bytes_to_del, text.count);
    append(*builder, before);
    append(*builder, after);
}

DeleteWordFromRight :: inline () {
    _delete_word_or_subword_from_right(subword_mode=false);
}

DeleteSubwordFromRight :: inline () {
    _delete_word_or_subword_from_right(subword_mode=true);
}

_delete_word_or_subword_from_right :: ($subword_mode: bool) {
    // @Speed @Cleanup !!!!!!
    if cursor_pos == 0 return;

    text := builder_to_string(*builder, do_reset = true);
    defer free(text);
    should_rebuild_row_table = true;

    assert(text.count > 0); // it should never happen, 'cause we already checked the cursor poistion above

    start := min(cursor_pos-1, text.count-1); // pos of the next deletable char from right

    #if !subword_mode {
        // Delete all the whitespace until we find a non-whitespace character (only if the first deletable character from right is a whitespace)
        if text[start] == #char " " {
            for < index: start..0 {
                if text[index] != #char " " {
                    index += 1;
                    left := slice(text, 0, index);
                    right := slice(text, cursor_pos, text.count);
                    append(*builder, left);
                    append(*builder, right);
                    set_cursor_pos(index);
                    return;
                }
            }
        }
    }

    if is_separator_char(text[cursor_pos-1], subword_mode) {
        append(*builder, text); // @Hacky
        DeleteCharFromRight();
        return;
    }

    for < index: start..0 {
        if is_separator_char(text[index], subword_mode) {
            index += 1; // 'cause we don't want to delete the separator char. We do handle that case above
            left := slice(text, 0, index);
            right := slice(text, cursor_pos, text.count);
            append(*builder, left);
            append(*builder, right);
            set_cursor_pos(index);

            return;
        } else if index == 0 {
            right := slice(text, cursor_pos, text.count);
            
            append(*builder, right);
            set_cursor_pos(0); 
            return;
        }
    }

    append(*builder, text); // @Hacky
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

    append_text(*builder, TAB_SPACE_CHARS);
}

init_keymaps :: () {
    register_keymap_procedures();
    reload_keymap(*default_keymap, "default", "default.keymap", false);
}

default_keymap: Keymap;