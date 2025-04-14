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

insert_os_clipboard_text_at_cursor :: (editor: *Editor, buffer: *Buffer, cursor: *Cursor) {
    // @Incomplete: Validate if the input data is valid utf8!
    text := Clipboard.os_clipboard_get_text();
    defer free(text);

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

insert_text_at :: (editor: *Editor, buffer: *Buffer, at: s64, text: string, $history := true) {
    maybe_grow(buffer, text.count);

    insert_at      := buffer.data  + at;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);
    right_rem_size  = max(0, right_rem_size);

    if right_rem_size then c_memmove(new_right, insert_at, cast(u64)right_rem_size);
    memmove(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.dirty = true;
    buffer.unsaved = true;

    #if history {
        add_history(editor, buffer, .INSERT, text, Range.{at, at + text.count});
    }

    // @Temporary? 
    // We must rescan the lines right after text insertion because the byte_pos_to_row_col_index() works on the buffer's "row_table" that is dirty at that point so
    // if we append some text to the current line after the last character the byte_pos_to_row_col_index() will think that we on the next row.
    // This commit buffer procedure will no cause any overhead by calling it multiple times because we rescan the lines only if it's dirty.
    commit_buffer_changes(buffer);
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

    shift_left(buffer, pos1, pos2);
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

next_character_pos :: (buffer: *Buffer, at: s64) -> s64 {
    assert(at > -1 || at <= buffer.count);

    if at == buffer.count return at;

    byte := buffer.data[at];
    return at + 1 + trailingBytesForUTF8[byte];
}

count_buffers :: (using editor: *Editor, initialized: bool) -> (count: s64) {
    count := 0;
    for * buffers {
        if it.initialized == initialized then count += 1;
    }

    return count;
}

// @Cleanup Use -1 if failed
find_buffer_index :: (buffer: *Buffer) -> (found: bool, index: s64) {
    for * buffers {
        if it == buffer return true, it_index;
    }

    return false, -1;
}

find_buffer_index_by_filepath :: (filepath: string) -> s64 {
    for * buffers {
        if it.filepath == filepath return it_index;
    }

    return -1;
}

// @Cleanup Use -1 if failed
find_initialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64) {
    for * buffers {
        if it.initialized return true, it_index;
    }

    return false, -1;
}

// @Cleanup Use -1 if failed
find_uninitialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64) {
    for * buffers {
        if !it.initialized return true, it_index;
    }

    return false, -1;
}

create_or_find_empty_buffer :: (editor: *Editor) -> *Buffer {
    buffer: *Buffer;

    found, index := find_uninitialized_buffer_index(editor);
    if found {
        assert(index > -1);
        buffer = *buffers[index];
    } else {
        buffer = create_buffer();
    }

    maybe_grow(buffer, BUFFER_PAGE_SIZE);

    buffer.initialized = true;

    commit_buffer_changes(buffer, true);

    return buffer;
}

commit_buffer_changes :: (buffer: *Buffer, $force := false) {
    #if !force {
        if !buffer.dirty return;
    }

    buffer.dirty = false;

    rescan_line_ends(buffer);
    tokenize(buffer, language = .C_STYLE); // @Todo: Multiple language support

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

    dirty = true;
    unsaved = true;
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

    new_buffer: Buffer;
    buffer.* = new_buffer;
}

undo :: (editor: *Editor, using buffer: *Buffer) {
    if !history.count || history_index == -1 return;

    h := *history[history_index];
    // print("[%] t: % ; range: % ; bufmax: %\n", #procedure_name(), h.type, h.range, buffer.count);

    is_similar_undo :: (prev: *Buffer_History) -> bool #expand {
        if prev.type != `h.type return false;
        
        issepa      := is_separator(`h.text[0], include_underscore=false);
        next_issepa := is_separator(prev.text[0], include_underscore=false);
        
        return !(issepa ^ next_issepa); // return true if both true or both false
    }

    if #complete h.type == {
        case .INSERT;
            to   := h.range.start;
            from := h.range.end;
            if to >= from || to < 0 || to > buffer.count-1 || from < 0 || from > buffer.count {
                log_error("Unable to revert (undo) the % due to the invalid start and end point of the text. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            shift_left(buffer, to, from);

            editor.cursor = h.cursor;
            set_cursor_pos(buffer, *editor.cursor, to, horizontal=true); 

            history_index -= 1;

            if history_index > -1 && is_similar_undo(*history[history_index]) {
                undo(editor, buffer);
            }

        case .DELETE;
            to := h.range.start;
            if to < 0 || to > buffer.count {
                log_error("Unable to revert (undo) the % due to the invalid insertion point. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            // Use the insert_text_at_cursor()! @Cleanup

            insert_text_at(editor, buffer, to, h.text, history=false);
            
            editor.cursor = h.cursor;
            set_cursor_pos(buffer, *editor.cursor, to + h.text.count, horizontal=true);

            history_index -= 1;

            if history_index > -1 && is_similar_undo(*history[history_index]) {
                undo(editor, buffer);
            }

        case .REPLACE;
            start := h.range.start;
            end   := h.range.start + h.text.count;
            if start >= end || start < 0 || start > buffer.count-1 || end < 0 || end > buffer.count-1 {
                log_error("Unable to revert (undo) the % due to the invalid range given for the replacement. %", h.type, h.*);
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
            assert(false);
    }
}

redo :: (editor: *Editor, using buffer: *Buffer) {
    if !history.count || history_index == history.count-1 return;

    h := *history[history_index+1];

    is_similar_redo :: (next: *Buffer_History) -> bool #expand {
        if next.type != `h.type return false;
        
        issepa      := is_separator(`h.text[0], include_underscore=false);
        next_issepa := is_separator(next.text[0], include_underscore=false);
        
        return !(issepa ^ next_issepa); // return true if both true or both false
    }

    if h.type == {
        case .INSERT;
            to := h.range.start;
            if to < 0 || to > buffer.count {
                log_error("Unable to revert (redo) the % due to the invalid insertion point. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            // Use the insert_text_at_cursor()! @Cleanup

            insert_text_at(editor, buffer, to, h.text, history=false);

            editor.cursor = h.cursor;
            set_cursor_pos(buffer, *editor.cursor, to + h.text.count, horizontal=true);
            Clamp(*editor.cursor.pos, 0, buffer.count);

            history_index += 1;

            if history_index < history.count && is_similar_redo(*history[history_index]) {
                redo(editor, buffer);
            }

        case .DELETE;
            to   := h.range.start;
            from := h.range.end;
            if to >= from || to < 0 || to > buffer.count-1 || from < 0 || from > buffer.count {
                log_error("Unable to revert (redo) the % due to the invalid start and end point of the text. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            shift_left(buffer, to, from);

            editor.cursor = h.cursor;
            set_cursor_pos(buffer, *editor.cursor, to, horizontal=true); 
            Clamp(*editor.cursor.pos, 0, buffer.count);

            history_index += 1;

            if history_index < history.count && is_similar_redo(*history[history_index]) {
                redo(editor, buffer);
            }

        case .REPLACE;
            // @INCOMPLETE @XXX
            start := h.range.start;
            end   := h.range.start + h.old_text.count;
            if start >= end || start < 0 || start > buffer.count-1 || end < 0 || end > buffer.count-1 {
                log_error("Unable to revert (undo) the % due to the invalid range given for the replacement. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            replace_text_at(editor, buffer, Range.{start, end}, h.text, history=false);
            
            editor.cursor = h.cursor;
            clamp_cursor(*editor.cursor, buffer.count);
            editor.cursor.col = byte_pos_to_row_col_index(buffer, editor.cursor.pos);

            history_index += 1;

            // We don't want to change these type of redos

        case .UNDEFINED;
            assert(false);
    }
}

add_history :: (editor: *Editor, using buffer: *Buffer, $type: Buffer_History.Type, text: string, range: Range) {
    if history.count && history_index != history.count-1 {
        // We should truncate the history because... @Todo: Explain it 
        new_size := buffer.history_index+1;
        history.count = new_size;
        Clamp(*history_index, -1, history.count-1);
    }

    h := array_add(*history);
    h.type   = type;
    h.range  = range;
    h.cursor = editor.cursor;

    modify_string(*h.text, text);

    #if type == .REPLACE {
        old_text := slice(buffer, range.start, range.end - range.start);
        modify_string(*h.old_text, old_text);
    }

    history_index += 1;
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

    for * buffers {
        if it.filepath == filepath return it;
    }

    buffer: *Buffer;
    for * buffers {
        if it.initialized && !it.exists_on_disk && !it.dirty && !it.count {
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
            input = sanitize_and_free_input_data(input);
            if input.count {
                maybe_grow(buffer, input.count);
                memmove(buffer.data, input.data, input.count);
                buffer.count = input.count;
            }
        }

        commit_buffer_changes(buffer, force=true);
    }

    return buffer;
}

sanitize_and_free_input_data :: (data: string) -> string {
    assert(data.count > 0);
    
    s := data;
    s = replace_crlf_to_lf(s, autofree=true);
    s = replace_tabs_with_spaces(s, autofree=true);

    return s;
}

close_buffer :: (buffer: *Buffer) {
    found, index := find_buffer_index(buffer);
    assert(found && index != -1);

    buffer_reset_keeping_memory(buffer);

    FindNewBuffer :: (e: *Editor) -> *Buffer {
        for *b: buffers {
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

}

get_buffer_index :: (buffer: *Buffer) -> s64 {
    for * buffers {
        if buffer == it {
            return it_index;
        }
    }

    assert(false); // @Temporary
    return -1;
}

buffer_end :: inline (buffer: *Buffer) -> *u8 {
    return buffer.data + buffer.count;
}

get_active_editor_and_buffer :: () -> (editor: *Editor, buffer: *Buffer) {
    assert(active_editor != null && active_editor.active_buffer != null);
    
    return active_editor, active_editor.active_buffer;
}

create_editor :: () -> *Editor {
    editor := array_add(*editors);

    return editor;
}

create_buffer :: () -> *Buffer {
    buffer := array_add(*buffers);
    buffer.id = random_get();

    return buffer;
}

change_active_buffer :: (editor: *Editor, buffer: *Buffer) {
    editor.active_buffer = buffer;
    
    clamp_cursor(*editor.cursor, buffer.count);

    // @Todo: Restore the viewport and the cursors
    editor.left_offset = 0.0;
    editor.top_offset  = 0.0;
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

active_editor: *Editor = null;
editors: [..] Editor;
buffers: [..] Buffer;

BUFFER_PAGE_SIZE :: 4096;

Editor :: struct {
    active_buffer: *Buffer;

    top_offset  := 0.0;
    left_offset := 0.0;

    cursor: Cursor;

    rect_for_draw: Rect;
    visible := true;
}

Buffer :: struct {
    id: u64;

    data:      *u8;
    count:     s64;
    allocated: s64;

    history: [..] Buffer_History;
    history_index: s64 = -1;

    colors: [] Color;

    dirty := false;
    unsaved := false;

    row_table: [..] Row_Info;
    row_table_recalc_time: float64 = 0.0;

    filepath: string;
    exists_on_disk: bool;

    tokenization_time: float64 = 0.0;

    // @Todo: It's mainly for the system buffers like logs or console output etc..
    language: Language = .PLAIN_TEXT;
    read_only := false;
    initialized := false;
}

Buffer_History :: struct {
    text: string;
    old_text: string; // FOR .REPLACE!
    range: Range;
    cursor: Cursor;
    type: Buffer_History.Type = .UNDEFINED;

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