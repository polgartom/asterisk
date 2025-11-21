insert_text_at :: (editor: *Editor, buffer: *Buffer, at: s64, text: string, $history := true) {

    #if history {
        add_history(editor, buffer, .INSERT, text, Range.{at, at + text.count});
    }

    {
        maybe_grow(buffer, text.count);

        insert_at      := buffer.data  + at;
        new_right      := insert_at    + text.count;
        right_rem_size := buffer.count - (insert_at - buffer.data);
        right_rem_size  = max(0, right_rem_size);

        if right_rem_size then c_memmove(new_right, insert_at, cast(u64)right_rem_size);
        memmove(insert_at, text.data, text.count);

        buffer.count += text.count;
    }

    buffer.dirty = true;
    buffer.unsaved = true;
    buffer.modtime = ms_since_init();

    // @Temporary
    // We must rescan the lines right after text insertion because the byte_pos_to_row_col_index() works on the buffer's "row_table" that is dirty at that point so
    // if we append some text to the current line after the last character the byte_pos_to_row_col_index() will think that we on the next row.
    // This commit buffer procedure will no cause any overhead by calling it multiple times because we rescan the lines only if it's dirty.
    commit_buffer_changes(buffer);

    for *c: buffer.cursor_backup {
        steps := text.count;
        
        if c.pos > 0 && c.pos >= at {
            c.pos += steps;
        }
        if c.sel > 0 && c.sel >= at {
            c.sel += steps;
        }
        clamp_cursor(c, buffer.count);
    }

    for *e : editors {
        if e == editor continue;
        
        if e.active_buffer == buffer {
            steps := text.count;
            c := *e.cursor;
            if c.pos > 0 && c.pos >= at {
                c.pos += steps;
            }
            if c.sel > 0 && c.sel >= at {
                c.sel += steps;
            }
            clamp_cursor(c, buffer.count);
        }
    }
}

// Shift the entire *used* buffer memory to the left, typically for "deleting" characters from the right
shift_left :: (editor: *Editor, using buffer: *Buffer, to: s64, from: s64) { // @Cleanup Naming?!
    if to == from return;
    assert(to < from);

    dest   := data  + to;
    source := data  + from;
    size   := count - from;

    c_memmove(dest, source, xx size);
    count -= (from - to);

    dirty = true;
    unsaved = true;
    modtime = ms_since_init();

    // @Todo: Better explanation
    // We don't need to commit the buffer changes
    // the byte_pos_to_row_col_index() will work because we apply deletion not insertion therefore that procedure won't mess up anything

    // @Incomplete: Can be better
    for *e : editors {
        if e != editor && e.active_buffer == buffer {
            c0, c1 := get_cursor_min_max_indecies_as_pointers(*e.cursor);

            steps := from - to;

            if is_overlap(.{c0.*, c1.*}, .{to, from}) {
                if c1.* <= from {
                    c1.* = to;
                } else {
                    c1.* -= steps;
                }

                if c0.* >= to {
                    c0.* = to;
                }

            } else {
                if c0.* > to {
                    c0.* -= steps;
                }
                if c1.* > from {
                    c1.* -= steps;
                }
            }

            clamp_cursor(*e.cursor, buffer.count);
        }
    }
}

insert_os_clipboard_text_at_cursor :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor) {
    t := Clipboard.os_clipboard_get_text();
    defer free(t);

    // @Speed
    normalize_line_endings(*t);
    spaces := talloc_string(tab_size);
    for spaces { spaces[it_index] = " "; } 
    text := replace(t, "\t", spaces);
    defer free(text);

    // @Todo: Validate if the input data is valid utf8!

    insert_text_at_cursor(editor, buffer, cursor, text);
}

replace_text_at :: (editor: *Editor, buffer: *Buffer, range: Range, new_text: string, $history := true) {
    #if history {
        add_history(editor, buffer, .REPLACE, new_text, range);
    }

    remove_text_from_left(editor, buffer, range.start, range.end - range.start, history=false);
    insert_text_at(editor, buffer, range.start, new_text, history=false);
}

replace_selection :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor, text: string, $history := true) {
    start, end := selected_range(cursor);
    replace_text_at(editor, buffer, Range.{start, end}, text, history);
    
    set_cursor_pos(buffer, cursor, start + text.count, horizontal=true);
}

insert_text_at_cursor :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor, text: string, $history := true) {
    if has_selection(cursor) {
        replace_selection(editor, buffer, cursor, text, history);
        return;
    }
    
    insert_text_at(editor, buffer, cursor.pos, text, history);

    set_cursor_pos(buffer, cursor, cursor.pos + text.count, horizontal=true);
}

remove_text_from_right_at_cursor :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor, bytes_to_del: s64, $history := true) {
    remove_text_from_right(editor, buffer, cursor.pos, bytes_to_del, history);
    
    set_cursor_pos(buffer, cursor, cursor.pos - bytes_to_del, horizontal=true);
}

remove_text_from_right :: (editor: *Editor, buffer: *Buffer, at: s64, bytes_to_del: s64, $history := true) {
    remove_text_from_left(editor, buffer, at - bytes_to_del, bytes_to_del, history);
}

remove_text_from_left_at_cursor :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor, bytes_to_del: s64, $history := true) {
    remove_text_from_left(editor, buffer, cursor.pos, bytes_to_del, history);
}

remove_text_from_left :: (editor: *Editor, buffer: *Buffer, at: s64, bytes_to_del: s64, $history := true) {
    pos1 := clamp(at, 0, buffer.count-1);
    pos2 := clamp(at + bytes_to_del, 0, buffer.count);
    if pos1 == pos2 return; // @Cleanup: We do the same check in the shift_left() procedure.
    
    #if history {
        deleted_text := slice(buffer, pos1, pos2 - pos1);
        add_history(editor, buffer, .DELETE, deleted_text, Range.{pos1, pos2});
    }

    shift_left(editor, buffer, pos1, pos2);
}

delete_selected_range_if_has_any :: inline (editor: *Editor, buffer: *Buffer, cursor: *Cursor) -> (text_deleted: bool) {
    if has_selection(editor.cursor) {
        delete_selected_range(editor, buffer, *editor.cursor);
        return true;
    }
    return false;
}

delete_selected_range :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor, $history := true) {
    if !has_selection(cursor) return;

    start, end := selected_range(cursor);
    remove_text_from_left(editor, buffer, start, end - start, history=history);
    set_cursor_pos(buffer, cursor, start, horizontal=true, with_selection=true);
}

copy_selection_to_os_clipboard :: (buffer: *Buffer, cursor: *Cursor) {
    text := get_selection_as_string(buffer, cursor);
    Clipboard.os_clipboard_set_text(text);
}

cut_selection_and_copy_to_os_clipboard :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor) {
    if !has_selection(cursor) return;

    text := get_selection_as_string(buffer, cursor);
    Clipboard.os_clipboard_set_text(text);

    delete_selected_range(editor, buffer, cursor);
}

is_valid_line :: inline (buffer: *Buffer, line: s64) -> bool {
    if line < 0 || line - 1 >= buffer.row_table.count return false;
    return true;
}

get_current_line :: inline (using buffer: *Buffer, byte_pos: s64) -> s64 {
    return find_row_index(buffer, byte_pos) + 1;
}

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

next_character_pos :: (buffer: *Buffer, at: s64) -> (pos: s64, moved: bool) {
    assert(at > -1 || at <= buffer.count);

    if at == buffer.count return at, false;

    byte := buffer.data[at];
    pos := at + 1 + trailingBytesForUTF8[byte];
    return pos, pos != at;
}

prev_character_pos :: (buffer: *Buffer, at: s64) -> (pos: s64, moved: bool) {
    pos := prev_char_byte_offset(buffer, at);
    return pos, pos != at;
}

count_buffers :: (using editor: *Editor, initialized: bool) -> (count: s64) {
    count := 0;
    for buffers {
        if it.initialized == initialized then count += 1;
    }

    return count;
}

// @Cleanup Use -1 if failed
find_buffer_index :: (buffer: *Buffer) -> (found: bool, index: s64) {
    for buffers {
        if it == buffer return true, it_index;
    }

    return false, -1;
}

find_buffer_by_filepath :: (filepath: string, $os_native_sepa := false) -> *Buffer {
    for buffers {
        if it.exists_on_disk {
            #if os_native_sepa   if it.filepath_os_sepa == filepath return it;
            #if !os_native_sepa  if it.filepath         == filepath return it;
        }
    }

    return null;
}

// @Cleanup Use -1 if failed
find_initialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64) {
    for buffers {
        if it.initialized return true, it_index;
    }

    return false, -1;
}

// @Cleanup Use -1 if failed
find_uninitialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64) {
    for buffers {
        if !it.initialized return true, it_index;
    }

    return false, -1;
}

create_or_find_empty_buffer :: (editor: *Editor) -> *Buffer {
    buffer: *Buffer;

    found, index := find_uninitialized_buffer_index(editor);
    if found {
        assert(index > -1);
        buffer = buffers[index];
    } else {
        buffer = create_buffer();
    }

    maybe_grow(buffer, BUFFER_PAGE_SIZE);

    buffer.initialized = true;

    commit_buffer_changes(buffer, true);

    return buffer;
}

commit_buffer_changes :: (buffer: *Buffer, force := false) {
    if !force {
        if !buffer.dirty return;
    }

    buffer.dirty = false;
    buffer.tokenization_requested = true;

    rescan_line_ends(buffer);

    for *e: editors {
        if e.active_buffer == buffer {
            clamp_cursor(*e.cursor, buffer.count);
        }
    }
}

rescan_line_ends :: (using buffer: *Buffer) {
    timer := seconds_since_init();

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

    row_table_recalc_time = (seconds_since_init() - timer) * 1000;
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

slice :: inline (buffer: *Buffer, start_ptr: *u8, end_ptr: *u8) -> string {
    end := buffer.data + buffer.count - 1;
    if start_ptr >= buffer.data + buffer.count then start_ptr = end;
    if end_ptr >= buffer.data + buffer.count   then end_ptr   = end;

    s: string;
    s.data  = start_ptr;
    s.count = end_ptr - start_ptr;

    return s;
}

to_string :: inline (buffer: *Buffer) -> string {
    s: string = ---;
    s.count = buffer.count;
    s.data  = buffer.data;
    return s;
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
        zero_memory(new_data, new_size);

        if buffer.data {
            memmove(new_data, buffer.data, buffer.allocated);
            c_free(buffer.data);
        }

        buffer.data      = new_data;
        buffer.allocated = new_size;

        {
            // Allocates colors
            new_colors_data := cast(*Color)c_malloc(xx new_size);
            assert(new_colors_data != null);
            memset(new_colors_data, cast(u8)Color.TEXT_DEFAULT, buffer.allocated);

            if buffer.colors.count {
                memmove(new_colors_data, buffer.colors.data, buffer.colors.count);
                c_free(buffer.colors.data);
            }

            buffer.colors.data  = new_colors_data;
            buffer.colors.count = new_size;
        }

    }
}

buffer_reset_keeping_memory :: (using buffer: *Buffer) {
    free(row_table.data,, row_table.allocator);

    if data != null  then c_free(data);
    if filepath      then free(filepath);

    // We don't have to free these string, because we free those and replace with the
    // new values when we add a new history. @Cleanup
    for history {
        if it.text     free(it.text);
        if it.old_text free(it.old_text);
    }
    reset_history(buffer);

    for buffers {
        if it == buffer {
            remove it;
            break;
        }
    }
}

batch_up_undos :: (history: [] Buffer_History, history_index: s64) -> [] Buffer_History {
    assert(history_index >= 0);
    assert(history_index < history.count);

    h := history[history_index];
    batch: [] Buffer_History;
    batch.data = history.data + history_index;
    batch.count = 1;
    
    if h.type == .INSERT {
        expect_alphanum := is_alphanum(h.text[0]);
        start_index     := history_index;
        list            := array_view(history, 0, history_index);
        
        for #v2 < list {
            if it.type != h.type break;
            if expect_alphanum ^ is_alphanum(it.text[0]) break;
            start_index = it_index;
        }

        batch = array_view(history, start_index, (history_index+1) - start_index);
        
    } else if h.type == .DELETE {
        nochars := utf8_character_count(h.text);
        if nochars != 1 return batch; // Because multi-chars deletion already kinda batched up, we only interested about single character histories for now.
        
        expect_alphanum := is_alphanum(h.text[0]);
        start_index     := history_index;
        list            := array_view(history, 0, history_index);
        
        for #v2 < list {
            if it.type != h.type break;
            nochars = utf8_character_count(it.text);
            if nochars != 1 break;
            if expect_alphanum ^ is_alphanum(it.text[0]) break;
            start_index = it_index;
        }

        batch = array_view(history, start_index, (history_index+1) - start_index);
    } 

    return batch;
}

batch_up_redos :: (history: [] Buffer_History, history_index: s64) -> [] Buffer_History {
    assert(history_index >= 0);
    assert(history_index < history.count);

    h := history[history_index];
    batch: [] Buffer_History;
    batch.data = history.data + history_index;
    batch.count = 1;

    if h.type == .INSERT {
        expect_alphanum := is_alphanum(h.text[0]);
        end_index       := history_index;
        list            := advance(history, history_index);
        
        for list {
            if it.type != h.type break;
            if expect_alphanum != is_alphanum(it.text[0]) break;
            end_index += 1;
        }
        
        batch = array_view(history, history_index, end_index-history_index);
        
    } else if h.type == .DELETE {
        nochars := utf8_character_count(h.text);
        if nochars != 1 return batch; // Because multi-chars deletion already kinda batched up, we only interested about single character histories for now.
    
        expect_alphanum := is_alphanum(h.text[0]);
        end_index       := history_index;
        list            := advance(history, history_index);
        
        for list {
            if it.type != h.type break;
            nochars = utf8_character_count(it.text);
            if nochars != 1 break;
            if expect_alphanum != is_alphanum(it.text[0]) break;
            end_index += 1;
        }
        
        batch = array_view(history, history_index, end_index-history_index);
    }

    return batch;
}

undo :: (editor: *Editor, using buffer: *Buffer) {
    if !history.count || history_index == -1 return;

    undos := batch_up_undos(history, history_index);
    for #v2 < h: undos { // We perform undos so we have to go backward        
        if #complete h.type == {        
            case .INSERT;
                to   := h.range.start;
                from := h.range.end;
                if to >= from || to < 0 || to > buffer.count-1 || from < 0 || from > buffer.count {
                    log_error("Unable to revert (undo) the % due to the invalid start and end point of the text. %", h.type, h);
                    reset_history(buffer);
                    return;
                }

                shift_left(editor, buffer, to, from);
                editor.cursor = h.cursor;
                set_cursor_pos(buffer, *editor.cursor, to, horizontal=true); 
                history_index -= 1;

            case .DELETE;
                to := h.range.start;
                if to < 0 || to > buffer.count {
                    log_error("Unable to revert (undo) the % due to the invalid insertion point. %", h.type, h);
                    reset_history(buffer);
                    return;
                }
                
                insert_text_at(editor, buffer, to, h.text, history=false);
                editor.cursor = h.cursor;
                set_cursor_pos(buffer, *editor.cursor, to + h.text.count, horizontal=true);
                history_index -= 1;

            case .REPLACE;
                start := h.range.start;
                end   := h.range.start + h.text.count;
                if start >= end || start < 0 || start > buffer.count || end < 0 || end > buffer.count {
                    log_error("Unable to revert (undo) the % due to the invalid range given for the replacement. %", h.type, h);
                    reset_history(buffer);
                    return;
                }

                replace_text_at(editor, buffer, Range.{start, end}, h.old_text, history=false);
                editor.cursor = h.cursor;
                clamp_cursor(*editor.cursor, buffer.count);
                editor.cursor.col = byte_pos_to_row_col_index(buffer, editor.cursor.pos);
                history_index -= 1;

                // We don't want to change these type of undos

            case .UNDEFINED;
                assert(false, "Undefined history type: %\n", h);
        }        
    }

    #if DEBUG {
        if undos.count {
            h := undos[0];
            s := to_string(buffer);
            current_hash := crc64(s);
            if h.hash != current_hash {
                log("\n\n-----------\nInvalid hash (undo/after): %  % | %\n", h.hash, current_hash, h);
                //File.write_entire_file(tprint("./dumps/diff/%", current_hash), s);
                //File.write_entire_file(tprint("./dumps/diff/%", h.hash), h.snapshot);
            }
        }
    }
}

redo :: (editor: *Editor, using buffer: *Buffer) {
    if !history.count || history_index == history.count-1 return;

    redos := batch_up_redos(history, history_index+1);

    for #v2 h: redos {
        if h.type == {
            case .INSERT;
                to := h.range.start;
                if to < 0 || to > buffer.count {
                    log_error("Unable to revert (redo) the % due to the invalid insertion point. %", h.type, h);
                    reset_history(buffer);
                    return;
                }

                insert_text_at(editor, buffer, to, h.text, history=false);
                editor.cursor = h.cursor;
                set_cursor_pos(buffer, *editor.cursor, to + h.text.count, horizontal=true);
                Clamp(*editor.cursor.pos, 0, buffer.count);
                history_index += 1;

            case .DELETE;
                // @BUG: We'll get invalid range!!!
                to   := h.range.start;
                from := h.range.end;
                if to >= from || to < 0 || to > buffer.count || from < 0 || from > buffer.count {
                    log_error("Unable to revert (redo) the % due to the invalid start and end point of the text. % | to: % ; from: % ; bufcount: %\n", h.type, h, to, from, buffer.count);
                    reset_history(buffer);
                    return;
                }

                shift_left(editor, buffer, to, from);
                editor.cursor = h.cursor;
                set_cursor_pos(buffer, *editor.cursor, to, horizontal=true); 
                Clamp(*editor.cursor.pos, 0, buffer.count);
                history_index += 1;

            case .REPLACE;
                // @INCOMPLETE @XXX
                start := h.range.start;
                end   := h.range.start + h.old_text.count;
                if start >= end || start < 0 || start > buffer.count || end < 0 || end > buffer.count {
                    log_error("Unable to revert (redo) the % due to the invalid range given for the replacement. %", h.type, h);
                    reset_history(buffer);
                    return;
                }

                replace_text_at(editor, buffer, Range.{start, end}, h.text, history=false);
                editor.cursor = h.cursor;
                to := end + h.text.count - (end - start);
                if to > buffer.count then to = buffer.count;
                set_cursor_pos(buffer, *editor.cursor, to, horizontal=true); 
                // clamp_cursor(*editor.cursor, buffer.count);
                // editor.cursor.col = byte_pos_to_row_col_index(buffer, editor.cursor.pos);
                history_index += 1;
                
                // We don't want to change these type of redos

            case .UNDEFINED;
                assert(false, "Undefined history type: %\n", h);
        }
    }
}

add_history :: (editor: *Editor, using buffer: *Buffer, new_history: Buffer_History) -> *Buffer_History {
    if history.count && history_index != history.count-1 {
        // We should truncate the history because...
        new_size := buffer.history_index+1;
        history.count = new_size;
        Clamp(*history_index, -1, history.count-1);
    }
    
    #if DEBUG { assert(new_history.hash != 0); }

    h := array_add(*history);
    h.type   = new_history.type;
    h.range  = new_history.range;
    h.cursor = new_history.cursor;

    #if DEBUG {
        modify_string(*h.snapshot, to_string(buffer));
        h.hash   = new_history.hash;
    }

    assert(!!new_history.text);
    modify_string(*h.text, new_history.text);
    
    if new_history.type == .REPLACE {
        assert(!!new_history.old_text);
        modify_string(*h.old_text, new_history.old_text);
    }
    
    history_index += 1; // also we jump -1 to 0 if no history exists
    
    return h;
}

add_history :: (editor: *Editor, using buffer: *Buffer, $type: Buffer_History.Type, text: string, range: Range, _old_text: string = "" /*for replace*/) -> *Buffer_History {
    if history.count && history_index != history.count-1 {
        // We should truncate the history because...
        new_size := buffer.history_index+1;
        history.count = new_size;
        Clamp(*history_index, -1, history.count-1);
    }

    h := array_add(*history);
    h.type   = type;
    h.range  = range;
    h.cursor = editor.cursor;
    
    #if DEBUG {
        modify_string(*h.snapshot, to_string(buffer));
        h.hash = crc64(h.snapshot);
    }

    modify_string(*h.text, text);

    #if type == .REPLACE {
        old_text := slice(buffer, range.start, range.end - range.start);
        modify_string(*h.old_text, old_text);
    }
    
    history_index += 1; // also we jump -1 to 0 if no history exists
    
    return h;
}

last_history :: (using buffer: *Buffer) -> *Buffer_History {
    if buffer.history_index > -1 && buffer.history_index < buffer.history.count {
        return *buffer.history[buffer.history_index];
    }

    return null;
}

reset_history :: (using buffer: *Buffer) {
    history_index = -1;
    array_reset_keeping_memory(*history);
}

switch_editor_mode :: (switch_to: Program_Mode) {
    if switch_to == {
        case .EDITOR;
            mode = .EDITOR;
        case .WIDGET;
            mode = .WIDGET;
    }
}

open_file_or_create_empty_buffer :: (editor: *Editor, _filepath: string) -> *Buffer {
    filepath := File.get_absolute_path(_filepath);
    path_overwrite_separators(filepath, #char "/");

    for buffers {
        if it.filepath == filepath return it;
    }

    buffer: *Buffer;
    for buffers {
        if it.initialized && !it.readonly && !it.exists_on_disk && !it.dirty && !it.count {
            buffer = it;
            break;
        }
    }

    if !buffer {
        buffer = create_or_find_empty_buffer(editor);
    }

    modify_string(*buffer.filepath, filepath);
    buffer.exists_on_disk = file_exists(filepath);
    
    if buffer.exists_on_disk {
        input := File.read_entire_file(filepath);
        if input {
            _input := input;
            defer free(_input);

            normalize_line_endings(*_input); // Converts any \r\n into \n, overwriting the original data.
            spaces := talloc_string(tab_size);
            for spaces { spaces[it_index] = " "; } 
            final_text := replace(_input, "\t", spaces);
            defer free(final_text);
            insert_text_at(editor, buffer, 0, final_text, history=false);
            buffer.unsaved = false;
            buffer.last_writetime = file_modtime_and_size(filepath);
        }

        commit_buffer_changes(buffer, force=true);
    }

    ext := path_extension(buffer.filepath);
    buffer.language = language_from_file_extension(ext);

    return buffer;
}

buffer_reload_from_disk :: (editor: *Editor, using buffer: *Buffer) -> bool {
    should_reload_from_disk = false;
    
    if !exists_on_disk return false;

    input, ok := File.read_entire_file(filepath);
    if !ok return false;
    defer free(input);

    if input {
        normalize_line_endings(*input); // Converts any \r\n into \n, overwriting the original data.
        replace_text_at(editor, buffer, .{start=0, end=buffer.count}, input, history=true);
        unsaved = false; // Because this is the up to date version of the buffer
        last_writetime = file_modtime_and_size(filepath);
    }
    commit_buffer_changes(buffer, force=true);
    return true;
}

buffer_write_to_disk :: (using buffer: *Buffer) -> bool {
    assert(!!filepath, "No filepath given! Buffer: %\n", buffer.*);
    
    exists := file_exists(filepath);
    if !exists {
        dir := path_strip_filename(filepath);
        assert(!!dir);
        File.make_directory_if_it_does_not_exist(dir);
    }

    ok := File.write_entire_file(filepath, to_string(buffer));
    if !ok {
        log_error("Unable to write the buffer data to '%'!\n", filepath);
        return false;
    }

    unsaved = false;
    exists_on_disk = true;
    last_writetime = file_modtime_and_size(filepath);

    return true;
}

save_buffer :: (using buffer: *Buffer) -> bool {
    if !filepath {
        path, ok := dialog_get_save_file_name();
        if !ok return false;
        modify_string(*filepath, path);
        path_unify_sepa(filepath);
        modify_string(*filepath_os_sepa, path);
        
        ext := path_extension(path);
        language = language_from_file_extension(ext);
    }

    ok := buffer_write_to_disk(buffer);
        
    {
        // @Temporary: We could flag the buffer, like .BUFFER_EDITOR_CONFIG or .BUFFER_PROJECT_CONFIG
        // Also we should put this in file watcher procedure
        config_path := get_editor_config_path();
        if file_exists(config_path) && platform_path_equals(config_path, filepath) {
            ReloadEditor();
        }
        config_path = get_project_config_path();
        if file_exists(config_path) && platform_path_equals(config_path, filepath) {
            ReloadEditor();
        }    
    }

    return ok;
}

close_buffer :: (buffer: *Buffer) {
    found, index := find_buffer_index(buffer);
    assert(found && index != -1);

    FindNewBuffer :: (e: *Editor) -> *Buffer {
        for b: buffers {
            if b == e.active_buffer continue;
            if b.initialized {
                if b.exists_on_disk {
                    return b;
                }
                editor_uses_the_buffer := false;
                for editors {
                    if it.active_buffer == b {
                        editor_uses_the_buffer = true;
                    }
                }
                if !editor_uses_the_buffer return b;
            }
        }

        return create_or_find_empty_buffer(e);
    }

    for *e: editors {
        if e.active_buffer == buffer {
            b := FindNewBuffer(e);
            commit_buffer_changes(b, force=true);
            change_active_buffer(e, b);
        }
    }

    buffer_reset_keeping_memory(buffer);
}

is_active :: inline (using e: *Editor) -> bool {
    return e == active_editor;
}

is_active :: inline (using e: *Editor, using b: *Buffer) -> bool {
    return e.active_buffer == b;
}

get_buffer_index :: (buffer: *Buffer) -> s64 {
    for buffers {
        if buffer == it {
            return it_index;
        }
    }

    assert(false);
    return -1;
}

get_editor_index :: (editor: *Editor) -> s64 {
    for * editors {
        if editor == it return it_index;
    }

    assert(false);
    return -1;
}

buffer_end :: inline (buffer: *Buffer) -> *u8 {
    return buffer.data + buffer.count;
}

get_active_editor_and_buffer :: () -> (editor: *Editor, buffer: *Buffer) {
    assert(active_editor != null && active_editor.active_buffer != null);
    return active_editor, active_editor.active_buffer;
}

create_buffer :: () -> *Buffer {
    id: u64;
    retry := true;
    while retry {
        id = random_get();
        retry = false;
        for b: buffers if b.id == id { retry = true; ll("id collision: % %\n", id, b.id); break; }
    }
    
    buffer := New(Buffer);
    buffer.id = id;
    array_add(*buffers, buffer);

    return buffer;
}

create_readonly_buffer :: (name: string) -> *Buffer {
    assert(!!name, "You should provide a name!\n");

    b := create_buffer();
    b.readonly = true;
    b.initialized = true;

    fmt_name := sprint("* % *", name);
    defer free(fmt_name);
    modify_string(*b.name, fmt_name);
    commit_buffer_changes(b, true);

    return b;
}

change_active_buffer :: (editor: *Editor, next_buffer: *Buffer) {
    current_buffer := editor.active_buffer;
    if current_buffer == next_buffer return;
    editor_index := get_editor_index(editor);
    if current_buffer {
        current_buffer.cursor_backup[editor_index] = editor.cursor; // Backing up the current cursor
    }

    editor.active_buffer = next_buffer;
    editor.cursor = next_buffer.cursor_backup[editor_index];
    clamp_cursor(*editor.cursor, next_buffer.count);

    editor.left_offset = 0.0;
    editor.top_offset  = 0.0;
    scroll_to_cursor(editor, editor.cursor, animation_duration=0.0);
}

scroll_to_cursor :: (editor: *Editor, cursor: Cursor, animation_duration: float = 0.08) {
    assert(editor.active_buffer != null);
    buffer := editor.active_buffer;
    r := editor.rect_for_draw;
    if r.w == 0 || r.h == 0 return;
    
    // Viewport (X)
    x_threshold := em(1.0, r_font) * 2;
    mx := get_cursor_x(buffer, *editor.cursor);
    mx = cast(s64)(mx - editor.left_offset - r.w);

    target := editor.left_offset;
    if mx + x_threshold > 0 {
        target += abs(mx + x_threshold);
    } else if abs(mx) > xx r.w {
        target -= abs(mx) - r.w;
        if target < 0 then target = 0;
    }

    if target != editor.left_offset {
        if animation_duration {
            anim_x: Anim;
            anim_x.active = true;
            anim_x.start  = editor.left_offset;
            anim_x.target = target;
            anim_x.duration = animation_duration;
            anim_x.started_at = frame_time64;
            editor.x_scroll_anim = anim_x;
        } else {
            editor.left_offset = target;
            editor.x_scroll_anim.active = false;
        }
    }

    // Viewport (Y)
    y_threshold := fnt_get_line_height() * 6; // @Todo :WhiteSpacesAfterLastRow
    my := fnt_get_line_height(find_row_index(buffer, editor.cursor.pos));
    my = r.h - my + editor.top_offset;

    target = editor.top_offset;
    if my - y_threshold < 0 {
        target += abs(my - y_threshold);
    } else if my + y_threshold > r.h + r.y {
        target -= (my + y_threshold) - (r.h + r.y);
        if target < 0 then target = 0;
    }

    if target != editor.top_offset {
        if animation_duration {
            anim_y: Anim;
            anim_y.active = true;
            anim_y.start  = editor.top_offset;
            anim_y.target = target;
            anim_y.duration = animation_duration;
            anim_y.started_at = frame_time64;
            editor.y_scroll_anim = anim_y;
        } else {
            editor.top_offset = target;
            editor.y_scroll_anim.active = false;
        }
    }

    redraw_requested = true;
}

scroll_up :: (editor: *Editor) {
    // @Todo: Handle the touchpad scrolling!

    assert(editor.active_buffer != null);
    buffer := editor.active_buffer;
    r := editor.rect_for_draw;
    if r.w == 0 || r.h == 0 return; // ???

    first_ri := buffer.row_table.count-1;
    first_visible_ri := first_visible_row_index(editor, buffer);
    target_ri := first_visible_row_index(editor, buffer);
    target_ri -= 3;
    if target_ri < 0 then target_ri = 0;

    // Viewport (Y)
    target := ifx target_ri == 0 then 0 else fnt_get_line_height(target_ri) + r_font.default_line_spacing;
    
    editor.top_offset = target;
    editor.y_scroll_anim.active = false;

    redraw_requested = true;
}

scroll_down :: (editor: *Editor) {
    // @Todo: Handle the touchpad scrolling! 
    assert(editor.active_buffer != null);
    buffer := editor.active_buffer;
    r := editor.rect_for_draw;
    if r.w == 0 || r.h == 0 return; // ???

    // Have to subtract the threshold because in this case we want to the top of the 6. row top not the bottom of it.
    y_threshold := fnt_get_line_height() * (6-1); // :WhiteSpacesAfterLastRow

    last_ri := buffer.row_table.count-1;
    last_visible_ri := last_visible_row_index(editor, buffer);
    if last_visible_ri == last_ri {
        if editor.top_offset + editor.rect_for_draw.h - y_threshold > fnt_get_line_height(last_ri) + r_font.default_line_spacing {
            return;
        }
    }
    
    target_ri := first_visible_row_index(editor, buffer);
    target_ri += 3;
    Clamp(*target_ri, 0, last_ri);

    // Viewport (Y)
    target := fnt_get_line_height(target_ri) + r_font.default_line_spacing; // add the line spacing so we get the bottom position of the row
    editor.top_offset = target;
    editor.y_scroll_anim.active = false;

    redraw_requested = true;
}

scroll_left :: (editor: *Editor) {
    buffer := editor.active_buffer;
    assert(editor.active_buffer != null);
    r := editor.rect_for_draw;
    if r.w == 0 || r.h == 0 return; // ???
    
    target := editor.left_offset - r_font.em_width * 6;
    if target < 0 target = 0;
    editor.left_offset = target;
    redraw_requested = true;
}

scroll_right :: (editor: *Editor) {
    buffer := editor.active_buffer;
    assert(editor.active_buffer != null);
    r := editor.rect_for_draw;
    if r.w == 0 || r.h == 0 return; // ???
    
    max_width := 0;
    si := first_visible_row_index(editor, buffer);
    ei := last_visible_row_index(editor, buffer);
    for i: si..ei {
        row := buffer.row_table[i];
        str := get_row_as_string(buffer, row);
        w := measure_text_width(r_font, str);
        if w > max_width then max_width = w;
    }
    
    target := editor.left_offset + r_font.em_width * 6;
    if cast(s64, target + r.w) < cast(s64)max_width {
        editor.left_offset = target;
        redraw_requested = true;
    } else if xx max_width > editor.left_offset + r.w {
        max_possible_x := max_width - r.w;
        editor.left_offset = max_possible_x;
    }
}

find_row :: inline (using buffer: *Buffer, byte_pos: s64) -> Row_Info {
    assert(buffer.initialized, "buffer: %\n", buffer.*);
    index := find_row_index(buffer, byte_pos);
    assert(index < row_table.count, "buffer: %\n", buffer.*);
    return row_table[index];
}

find_row_index :: (using buffer: *Buffer, byte_pos: s64) -> s64 {
    if byte_pos == 0 return 0;
    assert(row_table.count != 0);
    for row, row_index: row_table {
        if byte_pos <= row.end {
            return row_index;
        }
    }
    return row_table.count-1;
}

first_visible_row_index :: (editor: *Editor, using buffer: *Buffer) -> s64 {
    line_height := fnt_get_line_height();
    start_row: s64 = xx (editor.top_offset / line_height);
    start_row = clamp(start_row - 1, 0, row_table.count-1);
    return start_row;
}

last_visible_row_index :: (editor: *Editor, using buffer: *Buffer) -> s64 {
    viewport_h := editor.rect_for_draw.h;// window_height-footer_height*2; // @Hacky
    line_height := fnt_get_line_height();
    end_row: s64 = xx ((editor.top_offset + viewport_h) / line_height);
    end_row = clamp(end_row+1, 0, row_table.count-1);
    return end_row;
}

first_visible_row :: inline (editor: *Editor, buffer: *Buffer) -> Row_Info {
    index := first_visible_row_index(editor, buffer);;
    return buffer.row_table[index];
}

last_visible_row :: inline (editor: *Editor, using buffer: *Buffer) -> Row_Info {
    index := last_visible_row_index(editor, buffer);
    return buffer.row_table[index];
}

byte_pos_to_row_col_index :: (buffer: *Buffer, byte_pos: s64) -> s64 {
    assert(byte_pos <= buffer.count, "byte_pos: % ; buffer.count: %\n", byte_pos, buffer.count);
    row := find_row(buffer, byte_pos);
    col := 0;
    pos := row.start;
    while pos < byte_pos {
        col += 1;
        pos += 1 + trailingBytesForUTF8[buffer.data[pos]];
    }
    return col;
}

// @Cleanup: Better name!!!
byte_pos_from_mouse_xy :: (editor: *Editor, buffer: *Buffer, mx: s64, my: s64) -> s64 {
    if mx < 0 || my < 0 return -1;

    approx_row_index := cast(s64)floor((my + editor.top_offset) / fnt_get_line_height());
    if approx_row_index >= buffer.row_table.count return -1;
    
    rect := editor.rect_for_draw;
    rs := get_row_as_string(buffer, approx_row_index);
    ch := r_font.character_height;
    left := cast(float32)rect.x;
    bottom := (rect.h + rect.y) - fnt_get_line_height(approx_row_index+1) + editor.top_offset;
    
    ptr := rs.data;
    while rs.count {
        if cast(float, mx + editor.left_offset) <= left break;
        cw := Simp.get_character_width_in_pixels(r_font, rs.data, .LEFT_JUSTIFIED);
        left += cw;
        bytes := 1 + trailingBytesForUTF8[rs[0]];
        rs = advance(rs, bytes);
        ptr += bytes;
    }
    
    idx := ptr - buffer.data;
    Clamp(*idx, 0, buffer.count);
    
    return idx;
    
    /*
    if rs {
        log(">> '%'\n", string.{count=1 + trailingBytesForUTF8[rs[0]], data=rs.data});
        return true;
    } else {
        return false, -1; // @Todo
    }
    */
}

get_row_index_from_y_px :: (y: float, y_is_relative := false) -> (row_index: s64) {
    editor, buffer := get_active_editor_and_buffer();
    if y_is_relative {
        y += editor.top_offset;
    }
    approx_index := cast(s64)floor(y / fnt_get_line_height());
    if (approx_index > buffer.row_table.count - 1) || (approx_index < 0) return -1;
    return approx_index;
}

get_cursor_x :: inline (buffer: *Buffer, cursor: *Cursor, font: *Simp.Dynamic_Font = null) -> s64 {
    if cursor.pos == 0 return 0;
    if cursor.x_cache != -1 return cursor.x_cache;

    // @Speed !!!!!! the prepare_text is so slooow!

    cx := 0;
    defer cursor.x_cache = cx; // @Temporary
    row := find_row(buffer, cursor.pos);
    if row.start == cursor.pos return 0;

    s := get_row_as_string(buffer, row);
    s = slice(s, 0, cursor.pos - row.start);

    if !font then font = r_font;
    cx = measure_text_width(font, s);

    return cx;
}

// @Cleanup: Remove it, because we have the seek_previous_utf8_char or something like that.
prev_char_byte_offset :: (using buffer: *Buffer, start: s64) -> s64 {
    if start == 0 return 0;

    ptr := buffer.data + start;
    ptr -= 1;

    first_bit := ptr.* & 0x80;
    if first_bit == 0x0 return ptr - buffer.data; // 1 byte length char

    // Cursor (caret) movement is based on characters, not bytes - this issue should never occur!
    first_2bit := ptr.* & 0xc0;
    assert(first_2bit != 0xc0, "The start byte (buffer.data+start) is in the middle of a Unicode character.");
    assert(first_2bit == 0x80, "Invalid UTF-8"); // the first bit check happens above

    bytes := 1;
    while (ptr.* & 0xc0) == 0x80 && (ptr > buffer.data) {
        ptr -= 1;
        bytes += 1;
        assert(bytes <= 4, "Invalid UTF-8! We expect less than 5 bytes but we got %", bytes); // it's not totally correct
    }

    assert((ptr.* & 0xc0) == 0xc0, "No more characters are left, and we don't have the byte indicating the Unicode character's byte length.\n");

    return ptr - buffer.data;
}

// logbuf :: (text: string) {
//     using buffer := log_buffer;

//     assert(buffer && buffer.readonly);
    
//     // @Todo: Handle binary and non-printable data
//     normalize_line_endings(*text);

//     append_text_raw(buffer, text);
//     buffer.dirty = true;

// }

// logerrbuf :: (text: string) {
//     using buffer := logerr_buffer;
    
//     assert(buffer && buffer.readonly);

//     // @Todo: Handle binary and non-printable data
//     normalize_line_endings(*text);

//     append_text_raw(buffer, text);
//     buffer.dirty = true;

// }

init_editor_buffers :: (files_from_cmdline: [] string) {
    // log_buffer    = create_readonly_buffer("logs");
    // logerr_buffer = create_readonly_buffer("errors");
    active_editor = *editors[0];
    active_editor.visible = true;
    if files_from_cmdline.count == 2 {
        // @Temporary
        b := open_file_or_create_empty_buffer(*editors[0], files_from_cmdline[0]);
        change_active_buffer(*editors[0], b);
        b = open_file_or_create_empty_buffer(*editors[1], files_from_cmdline[1]);
        change_active_buffer(*editors[1], b);

        editors[0].visible = true;
        editors[1].visible = true;

    } else {
        for filepath: files_from_cmdline {
            e := *editors[it_index % editors.count];
            b := open_file_or_create_empty_buffer(e, filepath);
            change_active_buffer(e, b);
            
            e.visible = true;
        }
    }

    // @Todo: Don't draw the editor if no active buffer is assigned to
    for *e: editors {
        if !e.active_buffer {
            b := create_or_find_empty_buffer(e);
            change_active_buffer(e, b);
        }
    }
}

#if DEBUG {
    dump_buffer_histories :: (using buffer: *Buffer) {
        #if !DEBUG { return; }

        fname := path_filename(buffer.filepath);
        if !fname  {
            assert(false);
            return;
        }

        fpath := tprint("dumps/%", fname);
        File.file_delete(fpath);
        ok := File.write_entire_file(fpath, to_string(buffer));
        if !ok {
            assert(false);
            return;
        }
        
        b: String_Builder;
        init_string_builder(*b);
        
        append_by_pointer(*b, *history_index);
        append_by_pointer(*b, *history.count);
        
        for history {
            append(*b, it.text);
            append(*b, 0);
            append(*b, it.old_text);
            append(*b, 0);
            append_by_pointer(*b, *it.range);
            append_by_pointer(*b, *it.cursor);
            append_by_pointer(*b, *it.type);
            append_by_pointer(*b, *it.modtime);
            append_by_pointer(*b, *it.hash);
        }
        
        s := builder_to_string(*b);
        defer free(s);
        fpath = tprint("dumps/%-history", fname);
        File.file_delete(fpath);
        ok = File.write_entire_file(fpath, s);
        if !ok {
            assert(false);
        }
        
        dialog_confirm("Hisotry dump saved!", options=.OK|.ICONINFORMATION);
    }

    load_dump_buffer_history :: () {
        #if !DEBUG { return; }

        e, b := get_active_editor_and_buffer();
        fname := path_filename(b.filepath);
        if !fname  {
            assert(false);
            return;
        }

        for *e: editors {
            close_buffer(e.active_buffer);
        }
        
        fpath := tprint("dumps/%", fname);
        b = open_file_or_create_empty_buffer(e, fpath);
        reset_history(b);

        fpath = tprint("dumps/%-history", fname);
        data := File.read_entire_file(fpath);
        defer free_string(*data);
        
        get :: ($T: Type) -> T #expand {
            assert(`data.count >= size_of(T));
            r := cast(*T, `data.data);
            advance(*`data, size_of(T));
            return r.*;
        }
        
        get_string :: () -> string #expand {
            i := find_index_from_left(`data, 0);
            assert(i != -1, "data: %\n", `data);
            defer advance(*`data, i+1);
            r := slice(`data, 0, i);
            return r;
        }
        
        history_index := get(s64);
        expected_history_count := get(s64);
        
        while data.count {
            h: Buffer_History;
            h.text = get_string();
            h.old_text = get_string();
            h.range = get(Range);
            h.cursor = get(Cursor);
            h.type = get(Buffer_History.Type);
            h.modtime = get(float64);
            h.hash = get(u64);
            
            added_history := add_history(e, b, h);
        }
        
        b.history_index = history_index;
        
        // log("Added histories:\n%\n", b.history);
        
        assert(expected_history_count == b.history.count, "expected: % ; got: %\n", expected_history_count, b.history.count);
    }
}

active_editor: *Editor = null;
editors: [2] Editor;
buffers: [..] *Buffer;

editor_commands :: Editor_Command.[
    .{"Open Editor Config", OpenEditorConfigFile},
    .{"Open Project Config", OpenProjectConfigFile},
    .{"Reload Buffer From Disk", ReloadBufferFromDisk},
    .{"Transform Selection to Snake Case", TransformSelectionToSnakeCase},
];

// log_buffer:    *Buffer;
// logerr_buffer: *Buffer;

BUFFER_PAGE_SIZE :: 4096;

Editor :: struct {
    active_buffer: *Buffer;
    cursor: Cursor;
    
    visible := false;
        
    rect_for_draw: Rect;
    top_offset  := 0.0;
    left_offset := 0.0;
    
    width_anim:    Anim;
    y_scroll_anim: Anim;
    x_scroll_anim: Anim;
    
    scrollbar_anim: Anim; // @Todo
    scrollbar_opacity := 0.5;
    scrollbar_grabbed_y := 0.0;
}

Buffer :: struct {
    id: u64;

    data:      *u8;
    count:     s64;
    allocated: s64;

    initialized := false;
    dirty := false;
    tokenization_requested := false;
    unsaved := false;
    readonly := false;
    should_reload_from_disk := false;
    exists_on_disk := false;

    colors: [] Color;
    row_table: [..] Row_Info;
    cursor_backup: [editors.count] Cursor;
    history: [..] Buffer_History;
    history_index: s64 = -1;
    language: Language = .PLAIN_TEXT; // @Todo: It's mainly for the system buffers like logs or console output etc..
    
    name: string;
    filepath: string;
    filepath_os_sepa: string; // keep this for comparisons
    modtime: float64;
    last_writetime: Apollo_Time;

    quads_for_code_run: [..] Code_Font_Quad;

    Code_Font_Quad :: struct {
        quad: Simp.Font_Quad;
        color := Vector4.{1, 1, 1, 1.0};
    }

    // For measurements
    tokenization_time: float64 = 0.0;
    row_table_recalc_time: float64 = 0.0;
    
    //code_render_time: MultiSample_Measurement;
}

Buffer_History :: struct {
    text: string;
    old_text: string; // FOR .REPLACE!
    range: Range;
    cursor: Cursor;
    type: Buffer_History.Type = .UNDEFINED;
    modtime: float64;
    
    #if DEBUG {
        hash: u64;
        snapshot: string;
    }

    Type :: enum u8 {
        UNDEFINED :: 0;
        INSERT;
        DELETE;
        REPLACE;
    }
}

// @Speed: Shrink the struct size because we use 3 × 8 bytes per row which is quite inefficient!
Row_Info :: struct {
    start: s64;
    end:   s64;
    size:  s64;
}

Editor_Command_Proc :: #type ();
Editor_Command :: struct {
    name: string;
    proc: Editor_Command_Proc;
}