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

    buffer.history_enabled       = false;
    defer buffer.history_enabled = true;

    at := cursor.pos;

    insert_text_at_cursor(buffer, cursor, text);
    push_history(buffer, text, at);
}

insert_text_at_cursor :: (buffer: *Buffer, cursor: *Cursor, text: string) {
    MaybeDeleteSelectedText(buffer, cursor);

    maybe_grow(buffer, text.count);

    at             := cursor.pos;
    insert_at      := buffer.data  + at;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    SlowMemcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;

    set_cursor_pos(buffer, cursor, at + text.count, horizontal=true);

    if buffer.history_enabled {
        if text == "\n" || text == " " {
            push_history_from_input_buffer(buffer);
            push_history(buffer, text, at);
        } else {
            t := *buffer.history_temp_text;

            if !t || t.data == null {
                t.data = insert_at;
                t.count = 0;
            }
            
            t.count += text.count;
        }
    }
}

insert_text_at :: (buffer: *Buffer, at: s64, text: string) {
    assert(at > -1);

    maybe_grow(buffer, text.count);

    insert_at      := buffer.data  + at;
    new_right      := insert_at    + text.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    SlowMemcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
    buffer.dirty = true;

    if buffer.history_enabled {
        if text == "\n" || text == " " {
            push_history_from_input_buffer(buffer);
            push_history(buffer, text, at);
        } else {
            t := *buffer.history_temp_text;

            if !t || t.data == null {
                t.data = insert_at;
                t.count = 0;
            }
            
            t.count += text.count;
        }
    }
}

MaybeDeleteSelectedText :: inline (buffer: *Buffer, cursor: *Cursor) -> (text_deleted: bool) {
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
    for * editor.buffers {
        if it.initialized == initialized then count += 1;
    }

    return count;
}

find_buffer_index :: (using editor: *Editor, buffer: *Buffer) -> (found: bool, index: s64)
{
    for * editor.buffers {
        if it == buffer return true, it_index;
    }

    return false, -1;
}

find_initialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64)
{
    for * editor.buffers {
        if it.initialized return true, it_index;
    }

    return false, -1;
}

find_uninitialized_buffer_index :: (using editor: *Editor) -> (found: bool, index: s64)
{
    for * editor.buffers {
        if !it.initialized return true, it_index;
    }

    return false, -1;
}

create_or_find_empty_buffer :: (editor: *Editor) -> *Buffer {
    buffer: *Buffer;
    
    found, index := find_uninitialized_buffer_index(editor);
    if found {
        assert(index > -1);
        buffer = *editor.buffers[index];
    } else {
        buffer = array_add(*editor.buffers);
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
        ZeroMemory(new_data, new_size);

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
    if data != null then c_free(data);
    if filepath     then free(filepath);
    
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

push_history :: (b: *Buffer, text: string, at: s64) {
    assert(at > -1); // Unnecessary @Cleanup
    assert(!!text); // how can be?

    if !text {
        log_error("push_history() -> skipped, empty string given (buffer: [%] ; at: %)!", b, at);
        return;
    }

    // defer print("push_history() -> text: |%| (%) at: %\n", text, text.count, at);

    reset_history_temp_text(b);

    if b.history_index != -1 && b.history_index < b.history.count-1 {
        trim_history_right(b, b.history_index);
    }

    array_add(*b.history, Buffer_History.{
        text = copy_string(text),
        at   = at,
        type = Buffer_History.Type.INSERT_STRING
    });

    b.history_index = b.history.count - 1;
}

// @Cleanup: Naming!!!!!
push_history_from_input_buffer :: (using buffer: *Buffer) {
    if !history_temp_text {
        reset_history_temp_text(buffer);
        return;
    }

    text := history_temp_text;
    at   := text.data - buffer.data;

    push_history(buffer, text, at);
}

// @Todo: Simplify
undo_history :: (using buffer: *Buffer) {
    if !history.count || history_index == -1 return;

    push_history_from_input_buffer(buffer); // @Todo: Explain it!

    history_enabled = false;

    h := history[history_index];
    if h.type == {
        case .UNDEFINED;
        case .INSERT_STRING; {
            assert(!!h.text);
            
            to := h.at;
            from := h.at + h.text.count;
            if from > buffer.count {
                diff := from - buffer.count;
                from -= diff;
                to   -= diff;
            }
            to = max(to, 0);
            
            assert(from <= buffer.count, "%; %\n", from, buffer.count); // @Debug

            shift_left(buffer, to, from);
            set_cursor_pos(buffer, *_cursor, to, horizontal=true);
        }
        case .DELETE_STRING; {
            assert(false, "TODO: .DELETE_STRING history type\n");
        }
    }

    history_enabled = true;
    history_index   -= 1;
}

// @Todo: Simplify
redo_history :: (using buffer: *Buffer) {
    if !history.count || history_index + 1 >= history.count return;

    reset_history_temp_text(buffer);

    history_enabled = false;

    h := history[history_index+1];
    if h.type == {
        case .UNDEFINED;
        case .INSERT_STRING; {
            assert(!!h.text);
            insert_text_at(buffer, h.at, h.text);
            assert(h.at + h.text.count <= buffer.count);
            
            set_cursor_pos(buffer, *_cursor, h.at + h.text.count, horizontal=true);
        }
        case .DELETE_STRING; {
            assert(false, "TODO: .DELETE_STRING history type\n");
        }
    }

    history_enabled = true;
    history_index   += 1;
}

reset_history_item :: (using history_item: *Buffer_History) {
    if type == .INSERT_STRING {
        if text free(text);
    }

    ZeroMemory(history_item, size_of(Buffer_History));
}

// Reset the buffer history items from the right until the specified index (inclusive).
trim_history_right :: (b: *Buffer, index: s64) {
    before_count := b.history.count;
    before_index := b.history_index;
    // print("trim_history_right(): count: % -> % ; i: % -> %\n", before_count, b.history.count, before_index, b.history_index);

    assert(index > -1 && index < b.history.count, "Invalid index! max: % ; given: %\n", b.history.count-1, index);

    items := inline array_view(b.history, index);
    for * items inline reset_history_item(it);

    b.history.count = index+1; // not index+1, because the index is inclusive
}

// @Todo: Explain it!
reset_history_temp_text :: (using buffer: *Buffer) {
    history_temp_text.data  = null;
    history_temp_text.count = 0;
}

BUFFER_PAGE_SIZE :: 4096;

Buffer :: struct {
    data:      *u8;
    count:     s64;
    allocated: s64;

    history_enabled := true;
    history: [..] Buffer_History;
    history_index: s64 = -1;
    history_temp_text: string; // @Todo: Explain it!

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
    text:  string;
    count: s64;     // to determine how many characters we should delete from RIGHT!!
    at:    s64;     // byte position
    type: Buffer_History.Type = .UNDEFINED;

    Type :: enum u8 {
        UNDEFINED :: 0;
        INSERT_STRING;
        DELETE_STRING;
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