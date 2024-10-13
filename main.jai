// window_width := 1280;
// window_height := 720;

window_width := 1200;
window_height := 1200;

should_quit := false;

// background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

cursor_pos   := 0;
cursor_moved := false;
last_cursor_col_for_up_down_movement := 0; // @Cleanup naming! :SetDesiredColumnAfterMove

last_time : float64;

key_left: u32;
key_right: u32;
key_down: u32;
key_up: u32;
key_backspace: u32;
key_pgup: u32;
key_pgdn: u32;

key_shift: u32;
key_ctrl: u32;

font_width: s64;

bg_color :: Vector4.{5.0/255.0, 36.0/255.0, 33.0/255.0, 1.0};
text_color :: Vector4.{189.0/255.0, 179.0/255.0, 149.0/255.0, 1.0};
cursor_color :: Vector4.{.9, .0, .0, 1.0};

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

builder: String_Builder;

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

    init_string_builder(*builder);

    sample := read_entire_file("main.jai");
    append(*builder, sample);
    should_rebuild_row_table = true;

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

        key_left = 0;
        key_right = 0;
        key_down = 0;
        key_up = 0;
        key_backspace = 0;
        key_shift = 0;
        key_pgup = 0;
        key_pgdn = 0;
        key_ctrl = 0;

        for event : events_this_frame {
            if event.type == .QUIT {
                // print("quit!\n");
                should_quit = true;
                break;
            }

            // if event.key_code == .ESCAPE {
            //     if event.key_pressed should_quit = true;
            // }

            getrect_handle_event(event);

            if editor_in_focus {
                handled := keymap_handle_event(default_keymap, event);
                if handled continue;

                if event.type == .TEXT_INPUT {
                    if event.utf32 == 0x7F /* 127 */ continue;  // Prevent insertion of the "Delete character" @Hacky @Todo Ctrl-Backspace
                    memset(string_for_utf32_to_utf8.data, 0, 4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);
                    append_text(*builder, string_for_utf32_to_utf8);
                }
            } else {
                if event.key_code == .ESCAPE {
                    editor_in_focus = true;
                }
            }

        }

        text := builder_to_string(*builder, do_reset = false);
        defer free(text);

        if should_rebuild_row_table {
            rebuild_row_table(text);
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

        if show_debug_info {
            PrintDev("F1 toggle dev | F2 hidden chars\n");
            PrintDev("----------------------------\n");
            PrintDev("w: % ; h: % ; t: % ; l: %\n", window_width, window_height, top_offset, left_offset);

            row := get_cursor_row(text);
            col := get_cursor_col(text);
            cx  := get_cursor_x(text);
            cy  := get_cursor_y(text);
            PrintDev("p: % r: % col: % cx: % cy: %\n", cursor_pos, row-1, col, cx, cy);
            PrintDev("rows: % ; gentime: %ms\n", row_table.count, formatFloat(row_table_recalc_time, trailing_width=2));
            // for row_table {
            //     PrintDev("#% | pos: % cols: %\n", it_index, it.pos, it.cols);
            // }

            PrintDev("--------------rendering--------------\n");
        }

        draw_frame(text, second_elapsed, last_time);

        Simp.swap_buffers(my_window);

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

get_cursor_row :: (text: string) -> s64 {
    if cursor_pos == 0 return 1; // @Ambiguity: use start at 0 just like we do in get_cursor_col()

    assert(row_table.count != 0);
    for row_table {
        if cursor_pos <= it.pos {
            return it_index+1;
        }
    }

    return row_table.count;
}

get_cursor_col :: (text: string) -> s64 {
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

// next_char_byte_index :: (s: string) -> s64 {

// }

prev_char_byte_index :: (text: string) -> s64 {
    if cursor_pos == 0 return 0;

    row_index := get_cursor_row(text) - 1;
    i := first_byte_pos(row_table[row_index]);
    if i == cursor_pos {
        // we on the first col of the row so we should check the above row last char
        assert(row_index > 0); // sanity
        if row_index == 0 return 0;
        // step up by one row
        row_index -= 1;
        i = first_byte_pos(row_table[row_index]);
    }

    last_char_in_bytes := 0;
    while i < cursor_pos {
        byte := text[i];
        last_char_in_bytes = 1 + trailingBytesForUTF8[byte];
        i += last_char_in_bytes;
    }

    index := cursor_pos - last_char_in_bytes;
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

get_cursor_rel_y :: inline (text: string) -> s64 {
    row := get_cursor_row(text);
    return xx (window_height - get_line_height(row) + top_offset);
}

get_cursor_rel_x :: inline (text: string) -> s64 {
    x := get_cursor_x(text);
    return xx (x - left_offset + my_font.em_width);
}

get_cursor_x :: inline (text: string) -> s64 {
    if cursor_pos == 0 return 0;
    return get_cursor_col(text) * current_font_width();
}

get_cursor_y :: (text: string) -> s64 {
    if cursor_pos == 0 return window_height;
    row := get_cursor_row(text);
    return window_height - xx get_line_height(row);
}

append_text :: (b: *String_Builder, t: string) {
    // @Speed @Cleanup

    buf := get_current_buffer(b);
    text := builder_to_string(b, do_reset = true);
    defer free(text);

    if cursor_pos {
        a := text;
        a.count = cursor_pos;
        append(b, a);
    }

    append(b, t);

    a := advance(text, cursor_pos);
    append(b, a);

    increase_cursor_pos(t.count);

    should_rebuild_row_table = true;
}

set_cursor_pos :: inline (index: s64, $update_desired_cursor_col := false) {
    // @Todo: check overflow, use clamp() proc
    if index < 0 then index = 0;
    cursor_pos = index;
    cursor_moved = true;
}

increase_cursor_pos :: inline (by: s64) {
    set_cursor_pos(cursor_pos + by);
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

surround_chars :: (s: string, index: s64) -> bool, string {
    if s.count == 0    return false, s;
    if index > s.count return false, s;

    r := s;
    if index+1 <= s.count then r.count = index+1;
    if index-1 > -1      then advance(*r, index-1);

    return true, r;
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

rebuild_row_table :: (s: string) {
    should_rebuild_row_table = false;

    row_table_recalc_time = seconds_since_init()*1000;

    // array_reset(*row_table); // @speedwe can reuse the same memory
    array_reset_keeping_memory(*row_table);

    pos  := 0;
    posc := 0;
    while true {
        ln_index := find_index_from_left(s, #char "\n");
        if ln_index == -1 {
            chars := s.count;
            array_add(*row_table, .{pos=pos+chars, cols=chars});
            break;
        }

        chars := ln_index;
        pos += chars;
        array_add(*row_table, .{pos=pos, cols=chars});

        ln_index += 1;
        advance(*s, ln_index);

        pos += 1; // because of the line end
    }

    row_table_recalc_time = seconds_since_init()*1000 - row_table_recalc_time;
}

first_visible_row_index :: inline (s: string) -> s64 {
    line_height := get_line_height();
    start_row: s64 = xx (top_offset / line_height);
    start_row = clamp(start_row - 1, 0, row_table.count-1);
    return start_row;
}

last_visible_row_index :: inline (s: string) -> s64 {
    viewport_h := window_height-footer_height*2; // @Hacky

    line_height := get_line_height();
    end_row: s64 = xx ((top_offset + viewport_h) / line_height);
    end_row = clamp(end_row+1, 0, row_table.count-1);
    return end_row;
}

print_row :: inline (s: string, row_index: s64) {
    assert(row_index > -1);

    row := row_table[row_index];
    start := row.pos-row.cols;
    end := start+row.cols;
    assert(start > -1);
    assert(end <= s.count, "end: % ; s.count: %\n", end, s.count);

    t := slice(s, start, row.cols);
    print("(%,%,%)> |%|\n", row_index, row.pos, row.cols, t);
}

get_line_height :: inline (row: s64 = 1) -> float32 {
    return (my_font.default_line_spacing+line_height)*row;
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

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}

search_text: string;

row_table_recalc_time: float64 = 0.0;
draw_row_table := false;
should_rebuild_row_table := false;
row_table: [..] Row_Info;

// @Ambiguity
Row_Info :: struct {
    pos: s64;  // end byte index of the row
    cols: s64; // bytes in the row
}

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

last_occurance_offset: s64 = -1;
FindNextOccurence :: () {
    if search_text.count == 0 return;

    text := builder_to_string(*builder, do_reset = false);
    defer free(text);

    start := ifx last_occurance_offset == -1 then 0 else last_occurance_offset;
    
    if start < text.count {
        s := text;
        advance(*s, start);
        byte_offset, found := index_of_string_nocase(s, search_text);
        if !found byte_offset = -1;
        if byte_offset != -1 {
            last_occurance_offset = start + byte_offset + search_text.count; // @Todo: check overflow
            set_cursor_pos(start+byte_offset);
        }
    }

}

#if OS == .WINDOWS {
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
}

#load "draw.jai";
#load "keymap.jai";
// #load "editor.jai";

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
