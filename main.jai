// window_width := 1280;
// window_height := 720;

window_width := 1200;
window_height := 1200;

should_quit := false;

// background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

last_time : float64;

font_width: s64;

bg_color :: Vector4.{5.0/255.0, 36.0/255.0, 33.0/255.0, 1.0};
text_color :: Vector4.{189.0/255.0, 179.0/255.0, 149.0/255.0, 1.0};
CURSOR_COLOR :: Vector4.{.9, .0, .0, 1.0}; // RED

// @Todo: Blend with the text color
// CURSOR_COLOR :: Vector4.{134.0/255, 224.0/255, 143.0/255, 3.0};

line_height :: 0.0;
font_size :: 15;

TAB_SIZE_IN_SPACES :: 4;
TAB_SPACE_CHARS :: #run -> string {
    builder: String_Builder;
    builder.allocator = __temporary_allocator;
    for 0..TAB_SIZE_IN_SPACES-1 {
        append(*builder, " ");
    }
    return builder_to_string(*builder,, allocator = __temporary_allocator);
}

draw_special_chars := false;

top_offset := 0.0;
left_offset := 0.0;

x_cursor_scroll_treshold := 30;
y_cursor_scroll_treshold := 30;

show_debug_info := true;
debug_infos: [..] string;

fps: float64;
frametime: float64;

editor_in_focus := true;

// GETRECT - START
current_theme: s32 = xx Default_Themes.Default;
my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
// GETRECT - END

my_window: Window_Type;

footer_height: float;

event_find_next_occurence := false; // @Temporary

main :: () {
    print("\n--------------\n\n");

    base_path := path_strip_filename(get_path_of_running_executable());
    my_window = create_window(window_name="Asterisk", width=window_width, height=window_height);
    Simp.set_render_target(my_window);

    my_init_fonts();
    init_keymaps();
    ui_init(); // GetRect

    {
        f := <<my_font;
        print("em_width: % ; character_height: %\n", f.em_width, f.character_height);
    }

    footer_height = my_font.character_height*1.5;

    // @Todo: We should create an initial empty buffer
    {
        // open_file(*editor, "main.jai");
        // print("buffer: %\n", editor.buffers[0]);

        // @Todo: It's just for debug but we shoudl create an initial (starting) buffer for every new Editor instance
        t := "birka\ncica";
        buffer := array_add(*editor.buffers);
        editor.active_buffer = buffer;
        maybe_grow(buffer, t.count);
        memcpy(buffer.data, t.data, t.count);
        buffer.count = t.count;

        buffer.rebuild_row_table = true;
    }
        
    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;
    second_elapsed := false;

    string_for_utf32_to_utf8 := alloc_string(4); // @HEAP

    while !should_quit {
        #if OS == .WINDOWS {
            // WaitMessage();
        }

        last_time = seconds_since_init();

        second_elapsed = false;
        if last_time - last_second_time > 1.0 {
            last_second_time = last_time;
            second_elapsed = true;
        }

        update_window_events();

        for get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit {
                    my_init_fonts();
                }
            }
        }

        c := bg_color;
        Simp.clear_render_target(c.x, c.y, c.z, c.w);

        for event : events_this_frame {
            if event.type == .QUIT {
                // print("quit!\n");
                should_quit = true;
                break;
            }

            // @Debug
            if event.key_code == .ESCAPE {
                if event.key_pressed should_quit = true;
            }

            getrect_handle_event(event);

            if editor_in_focus {
                handled := keymap_handle_event(default_keymap, event);
                if handled continue;

                if event.type == .TEXT_INPUT {
                    if event.utf32 == 0x7F /* 127 */ continue;  // Prevent insertion of the "Delete character" @Hacky @Todo Ctrl-Backspace
                    memset(string_for_utf32_to_utf8.data, 0, 4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);
                    
                    insert_text(editor.active_buffer, editor.cursor_pos, string_for_utf32_to_utf8);
                    advance_cursor_pos(*editor, string_for_utf32_to_utf8.count);
                }
            } else {
                if event.key_code == .ESCAPE {
                    editor_in_focus = true;
                }
            }

        }

        text := to_string(editor.active_buffer);
        if editor.active_buffer.rebuild_row_table {
            rebuild_row_table(editor.active_buffer);
        }

        handle_editor_events();

        if draw_special_chars {
            // Tabs
            spaces := 0;
            for 0..text.count-1 {
                ch := text.data[it];
                if ch == #char " " {
                    spaces += 1;
                    if spaces == TAB_SIZE_IN_SPACES {
                        tab := slice(text, it-spaces+1, it);
                        for j: it-spaces+1..it {
                            text.data[j] = #char "~";
                        }
                        spaces = 0;
                    }
                } else {
                    spaces = 0;
                }
            }
        }

        // simtime := (seconds_since_init()-last_time)*1000;

        if show_debug_info {
            using editor;

            PrintDev("F1 toggle dev | F2 hidden chars\n");
            PrintDev("----------------------------\n");
            PrintDev("w: % ; h: % ; t: % ; l: %\n", window_width, window_height, top_offset, left_offset);

            row := get_cursor_row(*editor);
            col := get_cursor_col(*editor);
            cx  := get_cursor_x(*editor);
            cy  := get_cursor_y(*editor);
            PrintDev("p: % r: % col: % cx: % cy: %\n", cursor_pos, row-1, col, cx, cy);
            PrintDev("rows: % ; gentime: %ms\n", active_buffer.row_table.count, formatFloat(active_buffer.row_table_recalc_time, trailing_width=2));

            PrintDev("--------------rendering--------------\n");
        }

        // drawtime := seconds_since_init();

        draw_frame(text, second_elapsed, last_time);
        Simp.swap_buffers(my_window);

        // drawtime = (seconds_since_init()-drawtime)*1000;
        // PrintDev("simulate: %ms ; rendertime: %ms\n", formatFloat(simtime, trailing_width=2), formatFloat(drawtime, trailing_width=2));

        // sleep_milliseconds(20); // @Temporary
        reset_temporary_storage();
    }

}

PrintDev :: (fmt: string, args: .. Any) #expand {
    s := sprint(fmt, ..args); // Switch to tprint @Todo
    array_add(*debug_infos, s);  // can we use temporary allocator for dynamic arrays?
} @PrintLike

get_char_at_string_index :: (t: string, index: s64) -> string {
    assert(index < t.count);
    c := advance(t, index);
    c.count = 1;
    return c;
}

first_byte_pos :: inline (row: Row_Info) -> s64 {
    return row.pos - row.cols;
}

last_byte_pos :: inline (row: Row_Info) -> s64 {
    return row.pos;
}

find_row_index :: (using buffer: *Buffer, pos: s64) -> s64 {
    if pos == 0 return 0;

    assert(row_table.count != 0);
    for row_table {
        if pos <= it.pos {
            return it_index;
        }
    }

    return row_table.count;
}

get_cursor_row :: (using editor: *Editor) -> s64 {
    if cursor_pos == 0 return 1; // @Ambiguity: use start at 0 just like we do in get_cursor_col()

    buffer := editor.active_buffer;
    using buffer;

    assert(row_table.count != 0);
    for row_table {
        if cursor_pos <= it.pos {
            return it_index+1;
        }
    }

    return row_table.count;
}

// We should define the cursor_pos in the buffer not in the editor
get_cursor_col :: (using editor: *Editor) -> s64 {
    buffer := editor.active_buffer;
    using buffer;
    
    text := to_string(buffer);

    for row_table {
        if cursor_pos <= it.pos {
            row := it;
            i := first_byte_pos(it);
            cols := 0;
            while i < cursor_pos {
                byte := text[i];
                i += 1 + trailingBytesForUTF8[byte];
                cols += 1;
            }
            return cols;
        }
    }

    return 0;
}

next_char_byte_index :: inline (s: string, start: s64) -> s64 {
    assert(start < s.count);
    byte := s[start];
    return start + 1 + trailingBytesForUTF8[byte];
}

prev_char_byte_index :: (using buffer: *Buffer, start: s64) -> s64 {
    if start == 0 return 0;

    text := to_string(buffer);

    row_index := find_row_index(buffer, start);
    i := first_byte_pos(row_table[row_index]);
    if i == start {
        // we on the first col of the row so we should check the above row last char
        assert(row_index > 0); // sanity
        if row_index == 0 return 0;
        row_index -= 1; // step up by one row
        i = first_byte_pos(row_table[row_index]);
    }

    // count back from left to right
    last_char_in_bytes := 0;
    while i < start {
        byte := text[i];
        last_char_in_bytes = 1 + trailingBytesForUTF8[byte];
        i += last_char_in_bytes;
    }

    index := start - last_char_in_bytes;
    assert(index > -1);

    return index;
}

cols_in_the_row :: (s: string, row: Row_Info) -> s64 {
    index := first_byte_pos(row);
    end := row.pos;
    chars := 0;
    while index < end {
        byte := s[index];
        index += 1 + trailingBytesForUTF8[byte];
        chars += 1;
    }
    return chars;
}

// source: https://github.com/focus-editor/focus
safe_advance :: inline (s: *string, amount: s64 = 1) {
    // Doesn't crash if amount is incorrect for any reason
    amount = clamp(amount, 0, s.count);
    s.count -= amount;
    s.data  += amount;
}

get_cursor_rel_x :: inline (using editor: *Editor) -> s64 {
    x := get_cursor_x(editor);
    return xx (x - left_offset + my_font.em_width);
}

get_cursor_rel_y :: inline (using editor: *Editor) -> s64 {
    row := get_cursor_row(editor);
    return xx (window_height - get_line_height(row) + top_offset);
}

get_cursor_x :: inline (using editor: *Editor) -> s64 {
    if cursor_pos == 0 return 0;
    return get_cursor_col(editor) * current_font_width();
}

get_cursor_y :: (using editor: *Editor) -> s64 {
    if cursor_pos == 0 return window_height;
    row := get_cursor_row(editor);
    return window_height - xx get_line_height(row);
}

insert_text :: (buffer: *Buffer, pos: s64, text: string) {
    maybe_grow(buffer, text.count);
    
    left := buffer.data;
    insert_at := left + pos;
    new_right := insert_at + text.count;
    right_rem_size := buffer.count - (insert_at-left);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);

    memcpy(insert_at, text.data, text.count);

    buffer.count += text.count;
    buffer.rebuild_row_table = true;
}

set_cursor_pos :: inline (using editor: *Editor, index: s64) {
    // @Todo: check overflow, use clamp() proc
    if index < 0 then index = 0;
    cursor_pos = index;
    cursor_moved = true;
    // cursor_moved = true; // @Cleanup: Remove
}

advance_cursor_pos :: inline (editor: *Editor, by: s64) {
    set_cursor_pos(editor, editor.cursor_pos + by);
}

find_index_from_right_until_not :: (s: string, byte: u8, start_index: s64 = 0) -> s64  #no_abc {
    assert(start_index > -1 && start_index < s.count);

    cursor := start_index;
    while cursor >= 0 {
        if s[cursor] != byte return cursor;
        cursor -= 1;
    }

    return -1;
}

find_index_from_left_until_not :: (s: string, byte: u8, start_index: s64 = 0) -> s64  #no_abc {
    assert(start_index > -1);

    cursor := start_index;
    while cursor < s.count {
        if s[cursor] != byte return cursor;
        cursor += 1;
    }

    return -1;
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.
    path := path_strip_filename(get_path_of_running_executable());

    set_working_directory(path);
    pixel_height := font_size; // print(">>> %\n", window_height/40);

    my_font = Simp.get_font_at_size("data", "firacode-retina/FiraCode-Retina.ttf", pixel_height);
    // print("%\n\n", <<my_font);
    assert(my_font != null);
}

current_font_width :: () -> s64 {
    assert(my_font != null);
    return my_font.em_width;
}

num_of_utf8_chars :: inline (s: string) -> s64 {
    total := 0;
    while s.count {
        count := 1 + trailingBytesForUTF8[s[0]];
        advance(*s, count);
        total += count;
    }
    return total;
}

// @Cleanup: use this!!
// first_visible_row_index :: inline (using buffer: *Buffer) -> s64 {
//     s := to_string(buffer);

//     line_height := get_line_height();
//     start_row: s64 = xx (top_offset / line_height);
//     start_row = clamp(start_row - 1, 0, row_table.count-1);

//     return start_row;
// }

last_visible_row_index :: inline (using buffer: *Buffer) -> s64 {
    s := to_string(buffer);

    viewport_h := window_height-footer_height*2; // @Hacky

    line_height := get_line_height();
    end_row: s64 = xx ((top_offset + viewport_h) / line_height);
    end_row = clamp(end_row+1, 0, row_table.count-1);

    return end_row;
}

get_line_height :: inline (row: s64 = 1) -> float32 {
    return row * (my_font.default_line_spacing+line_height);
}

is_separator_char :: inline (c: s64, $include_underscore := false) -> bool {
    #if include_underscore {
        if c == #char "_" return true;
    }

    return c == #char " " || c == #char "\n" ||
           c == #char "{" || c == #char "}"  ||
           c == #char "." || c == #char ";"  ||
           c == #char ">" || c == #char "<"  ||
           c == #char "=" || c == #char "!"  ||
           c == #char "[" || c == #char "]"  ||
           c == #char "(" || c == #char ")"  ||
           c == #char "#" || c == #char "?"  ||
           c == #char "/" || c == #char "*"  ||
           c == #char "-" || c == #char "+"  ||
           c == #char "&" || c == #char "@"  ||
           c == #char "$" || c == #char ","  ||
           c == #char ":" || c == #char "|"  ||
           c == #char "^" || c == #char "%"  ||
           c == #char "~" || c == #char "\\" ||
           c == #char "\"" || c == #char "'" ||
           c == #char "`"
           ;
}

is_whitespace :: inline (c: s64) -> bool {
    assert(c != #char "\t", "We should convert all of the tabs to spaces");

    return c == #char " " || c == #char "\n";
}

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}

search_text: string;

Editor_Event :: struct {
    proc: Editor_Event_Proc;
}

Editor_Event_Proc :: #type ();

editor_events: [..] Editor_Event;

add_editor_event :: (proc_: Editor_Event_Proc) {
    array_add(*editor_events, .{proc=proc_});
}

handle_editor_events :: () {
    for < editor_events.count-1..0 {
        event := editor_events[it];
        event.proc();
    }

    array_reset_keeping_memory(*editor_events);
}

// last_occurance_offset: s64 = -1;
// FindNextOccurence :: () {
//     if search_text.count == 0 return;

//     text := builder_to_string(*builder, do_reset = false);
//     defer free(text);

//     start := ifx last_occurance_offset == -1 then 0 else last_occurance_offset;
    
//     if start < text.count {
//         s := text;
//         advance(*s, start);
//         byte_offset, found := index_of_string_nocase(s, search_text);
//         if !found byte_offset = -1;
//         if byte_offset != -1 {
//             last_occurance_offset = start + byte_offset + search_text.count; // @Todo: check overflow
//             set_cursor_pos(start+byte_offset);
//         }
//     }

// }

#if OS == .WINDOWS {
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
}

#load "draw.jai";
#load "keymap.jai";
#load "editor.jai";

#import "System";
#import "Basic";
#import "File";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Keymap";
#import "Unicode";
Simp :: #import "Simp";
#import "GetRect";
#import "Memory";

c_malloc  :: (size: u64) -> *void                #foreign crt "malloc";
c_free    :: (memory: *void)                     #foreign crt "free";
c_realloc :: (memory: *void, size: u64) -> *void #foreign crt "realloc";
c_memmove :: (dest: *void, src: *void, count: u64) -> *void #foreign crt "memmove";

#if OS == .WINDOWS {
    crt :: #system_library "msvcrt";  // For malloc, free on Windows
} else #if OS == .MACOS || OS == .IOS || OS == .LINUX || OS == .ANDROID {
    crt :: #system_library "libc";
}