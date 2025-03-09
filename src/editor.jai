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

cut_selection_and_copy_to_os_clipboard :: (buffer: *Buffer, cursor: *Cursor) {
    if !has_selection(cursor) return;

    text := get_selection_as_string(buffer, cursor);
    Clipboard.os_clipboard_set_text(text);

    delete_selected_range(buffer, cursor);
}

insert_os_clipboard_text_at_cursor :: (buffer: *Buffer, cursor: *Cursor) {

    // @Incomplete: Validate if the input data is valid utf8!
    text := Clipboard.os_clipboard_get_text();
    defer free(text);

    insert_text_at_cursor(buffer, cursor, text);
}

replace_text_at :: (buffer: *Buffer, range: Range, new_text: string, $history := true) {
    #if history {
        using buffer;
        if history.count && history_index != history.count-1 {
            // We should truncate the history because... @Todo: Explain it 
            new_size := buffer.history_index+1;
            history.count = new_size;
            Clamp(*history_index, -1, history.count-1);
        }

        h := array_add(*buffer.history);

        old_text := slice(buffer, range.start, range.end - range.start);
        modify_string(*h.old_text, old_text);
        modify_string(*h.text, new_text);

        h.range  = range;
        h.type   = .REPLACE;
        h.cursor = buffer._cursor;

        buffer.history_index += 1;
    }

    remove_text_from_left(buffer, range.start, range.end - range.start, history=false);
    insert_text_at(buffer, range.start, new_text, history=false);
}

insert_text_at_cursor :: (buffer: *Buffer, cursor: *Cursor, text: string, $history := true) {
    insert_text_at(buffer, cursor.pos, text, history);

    set_cursor_pos(buffer, cursor, cursor.pos + text.count, horizontal=true);
}

insert_text_at :: (buffer: *Buffer, at: s64, text: string, $history := true) {
    maybe_grow(buffer, text.count);

    insert_at      := buffer.data  + at;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);
    right_rem_size  = max(0, right_rem_size);

    if right_rem_size then c_memmove(new_right, insert_at, cast(u64)right_rem_size);
    SlowMemcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;

    #if history {
        using buffer;
        if history.count && history_index != history.count-1 {
            // We should truncate the history because... @Todo: Explain it 
            new_size := buffer.history_index+1;
            history.count = new_size;
            Clamp(*history_index, -1, history.count-1);
        }

        h := array_add(*buffer.history);
        modify_string(*h.text, text);
        h.range = .{at, at + text.count};
        h.type   = .INSERT;
        h.cursor = buffer._cursor;
        buffer.history_index += 1;
    }
}

remove_text_from_right_at_cursor :: (buffer: *Buffer, cursor: *Cursor, bytes_to_del: s64, $history := true) {
    remove_text_from_right(buffer, cursor.pos, bytes_to_del, history);
    set_cursor_pos(buffer, cursor, cursor.pos - bytes_to_del, horizontal=true);
}

remove_text_from_right :: (buffer: *Buffer, at: s64, bytes_to_del: s64, $history := true) {
    remove_text_from_left(buffer, at - bytes_to_del, bytes_to_del, history);
}

remove_text_from_left_at_cursor :: (buffer: *Buffer, cursor: *Cursor, bytes_to_del: s64, $history := true) {
    remove_text_from_left(buffer, cursor.pos, bytes_to_del, history);
}

remove_text_from_left :: (buffer: *Buffer, at: s64, bytes_to_del: s64, $history := true) {
    pos1 := clamp(at, 0, buffer.count-1);
    pos2 := clamp(at + bytes_to_del, 0, buffer.count);
    if pos1 == pos2 return; // @Cleanup: We do the same check in the shift_left() procedure.
    
    #if history {
        using buffer;

        if history.count && history_index != history.count-1 {
            // We should truncate the history because... @Todo: Explain it 
            new_size := buffer.history_index+1;
            history.count = new_size;
            Clamp(*history_index, -1, history.count-1);
        }

        h := array_add(*buffer.history);
        deleted_text := slice(buffer, pos1, pos2 - pos1);
        modify_string(*h.text, deleted_text);
        h.range = .{pos1, pos2};
        h.type   = .DELETE;
        h.cursor = _cursor;
        history_index += 1;
    }

    shift_left(buffer, pos1, pos2);
}

delete_selected_range_if_has_any :: inline (buffer: *Buffer, cursor: *Cursor) -> (text_deleted: bool) {
    if has_selection(buffer._cursor) {
        delete_selected_range(buffer, *buffer._cursor);
        return true;
    }
    return false;
}

delete_selected_range :: (buffer: *Buffer, cursor: *Cursor) {
    if !has_selection(cursor) return;

    start, end := selected_range(cursor);
    shift_left(buffer, start, end);

    set_cursor_pos(buffer, cursor, start, horizontal=true, with_selection=true);

    assert(cursor.pos <= buffer.count, "cursor: % ; buffer.count: %", cursor.pos, buffer.count);
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
        buffer = array_add(*buffers);
    }

    maybe_grow(buffer, BUFFER_PAGE_SIZE);
    rescan_line_ends(buffer);

    buffer.initialized = true;

    return buffer;
}

// @Speed: We could implement something like a Quadtree. For example we might create a chunk after every 1000 rows (line ends)
rescan_line_ends :: (using buffer: *Buffer) {
    rebuild_row_table = false;

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

    // create_color_regions(buffer); // @Cleanup: Remove from here

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

    rebuild_row_table = true;
    dirty = true;
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
            SlowMemcpy(new_data, buffer.data, buffer.allocated);
            c_free(buffer.data);
        }

        buffer.data      = new_data;
        buffer.allocated = new_size;
    }
}

buffer_reset_keeping_memory :: (using buffer: *Buffer) {
    free(row_table.data,, row_table.allocator);

    if data != null  then c_free(data);

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

create_color_regions :: (using buffer: *Buffer) {
    array_reset_keeping_memory(*color_regions);

    s := to_string(buffer);
    tokens := tokenize(s, language = .C_STYLE);
    defer if tokens.count array_free(tokens);

    text_color := map_color_to_vec4(.TEXT_DEFAULT);

    at := 0;
    for tokens {
        color := get_token_type_color(it.type);
        if color != text_color {
            array_add(*color_regions, .{pos=it.byte_pos, color=color});
            array_add(*color_regions, .{pos=it.byte_pos + it.count, color=text_color});
        }
    }

    // print("[tokens]: % \n\n[regions]: %\n\n", tokens, color_regions);

    // print("color_regions: %\n", color_regions);
}

find_color_region_index :: inline (regions: [] Color_Region, pos: s64) -> (index: s64) {
    for regions {
        if pos <= it.pos {
            return it_index;
        }
    }

    return -1;
}

get_color_regions_range :: inline (regions: [] Color_Region, start_pos: s64, end_pos: s64) -> (color_regions: [] Color_Region) {
    assert(regions.count > 0);

    start_index := find_color_region_index(regions, start_pos);
    if start_index == -1 {
        start_index = 0;
    }

    end_index := find_color_region_index(regions, end_pos);
    if end_index == -1 {
        end_index = regions.count - 1;
    }

    count := end_index - start_index;
    if count == 0 then count = 1;

    return array_view(regions, start_index, count);
}

undo :: (using buffer: *Buffer) {
    if !history.count || history_index == -1 return;

    h := *history[history_index];
    print("[%] t: % ; range: % ; bufmax: %\n", #procedure_name(), h.type, h.range, buffer.count);

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

            _cursor = h.cursor;
            set_cursor_pos(buffer, *_cursor, to, horizontal=true); 

            history_index -= 1;

        case .DELETE;
            to := h.range.start;
            if to < 0 || to > buffer.count {
                log_error("Unable to revert (undo) the % due to the invalid insertion point. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            // Use the insert_text_at_cursor()! @Cleanup

            insert_text_at(buffer, to, h.text, history=false);
            
            _cursor = h.cursor;
            set_cursor_pos(buffer, *_cursor, to + h.text.count, horizontal=true);

            history_index -= 1;

        case .REPLACE;
            start := h.range.start;
            end   := h.range.start + h.text.count;
            if start >= end || start < 0 || start > buffer.count-1 || end < 0 || end > buffer.count-1 {
                log_error("Unable to revert (undo) the % due to the invalid range given for the replacement. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            replace_text_at(buffer, Range.{start, end}, h.old_text, history=false);
            
            _cursor = h.cursor;
            clamp_cursor(buffer, *_cursor);
            _cursor.col = byte_pos_to_col_pos_hacky(buffer, _cursor.pos);
            request_editor_top_left_offsets_recalc();

            history_index -= 1;

        case .UNDEFINED;
            assert(false);
    }
}

redo :: (using buffer: *Buffer) {
    if !history.count || history_index == history.count-1 return;

    h := *history[history_index+1];

    if h.type == {
        case .INSERT;
            to := h.range.start;
            if to < 0 || to > buffer.count {
                log_error("Unable to revert (redo) the % due to the invalid insertion point. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            // Use the insert_text_at_cursor()! @Cleanup

            insert_text_at(buffer, to, h.text, history=false);

            buffer._cursor = h.cursor;
            set_cursor_pos(buffer, *buffer._cursor, to + h.text.count, horizontal=true);
            Clamp(*buffer._cursor.pos, 0, buffer.count);

            history_index += 1;

        case .DELETE;
            to   := h.range.start;
            from := h.range.end;
            if to >= from || to < 0 || to > buffer.count-1 || from < 0 || from > buffer.count {
                log_error("Unable to revert (redo) the % due to the invalid start and end point of the text. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            shift_left(buffer, to, from);

            buffer._cursor = h.cursor;
            set_cursor_pos(buffer, *buffer._cursor, to, horizontal=true); 
            Clamp(*buffer._cursor.pos, 0, buffer.count);

            history_index += 1;

        case .REPLACE;
            // @INCOMPLETE @XXX
            start := h.range.start;
            end   := h.range.start + h.old_text.count;
            if start >= end || start < 0 || start > buffer.count-1 || end < 0 || end > buffer.count-1 {
                log_error("Unable to revert (undo) the % due to the invalid range given for the replacement. %", h.type, h.*);
                reset_history(buffer);
                return;
            }

            replace_text_at(buffer, Range.{start, end}, h.text, history=false);
            
            _cursor = h.cursor;
            clamp_cursor(buffer, *_cursor);
            _cursor.col = byte_pos_to_col_pos_hacky(buffer, _cursor.pos);
            request_editor_top_left_offsets_recalc();

            history_index += 1;

        case .UNDEFINED;
            assert(false);
    }
}

reset_history :: (using buffer: *Buffer) {
    history_index = -1;
    array_reset_keeping_memory(*history);
}

switch_editor_mode :: (switch_to: Program_Mode) {
    if switch_to == {
        case .EDITOR;
            active_widget_deactivate_all();
            
            mode = .EDITOR;                
        case .WIDGET;
            mode = .WIDGET;
    }
}

open_file_or_create_empty_buffer :: (editor: *Editor, _filepath: string) {
    filepath := File.get_absolute_path(_filepath);
    path_overwrite_separators(filepath, #char "/");

    for buffers {
        if it.filepath == filepath return;
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
            e.active_buffer = FindNewBuffer(e);
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

get_active_editor_and_buffer :: () -> (editor: *Editor, buffer: *Buffer) {
    assert(active_editor != null && active_editor.active_buffer != null);
    
    return active_editor, active_editor.active_buffer;
}

create_editor :: () -> *Editor {
    editor := array_add(*editors);

    return editor;
}

change_active_buffer :: (editor: *Editor, buffer: *Buffer) {
    editor.active_buffer = buffer;
    
    editor.should_recalc_editor_offsets = true;
    editor.left_offset = 0.0;
    editor.top_offset  = 0.0;
}

request_editor_top_left_offsets_recalc :: () {
    for *editor: editors {
        request_editor_top_left_offsets_recalc(editor);
    }
}

request_editor_top_left_offsets_recalc :: (editor: *Editor) {
    editor.should_recalc_editor_offsets = true;
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

    rect_for_draw: Rect;
    visible := true;
    should_recalc_editor_offsets := false; // @Todo: REMOVE IT
}

Buffer :: struct {
    data:      *u8;
    count:     s64;
    allocated: s64;

    history: [..] Buffer_History;
    history_index: s64 = -1;

    // cursors: [..] Cursor; // @Todo: Multiple cursor support
    _cursor: Cursor; // This name temporary, because we're gonna use the cursors dynamic array

    row_table: [..] Row_Info;
    rebuild_row_table := false;
    row_table_recalc_time: float64 = 0.0;

    color_regions: [..] Color_Region;
    // rebuild_color_regions := false;

    filepath: string;
    exists_on_disk: bool;

    // @Todo: It's mainly for the system buffers like logs or console output etc..
    language: Language = .PLAIN_TEXT;
    read_only := false;
    dirty := false;
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

Color_Region :: struct {
    pos: s64;
    color: Vector4;
};