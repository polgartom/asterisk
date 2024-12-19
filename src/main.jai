// window_width := 1280;
// window_height := 720;

window_width := 1200;
window_height := 1200;

should_quit := false;

// background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

last_time : float64;
last_simulation_time : float64;
last_showed_sim_time : float64;
last_rendering_time  : float64;

font_width: s64;

RgbToVec4 :: (r: u8, g: u8, b: u8, alpha: float = 1.0) -> Vector4 {
    return Vector4.{
        r/255.0, 
        g/255.0, 
        b/255.0, 
        alpha
    };
}

bg_color :: Vector4.{5.0/255.0, 36.0/255.0, 33.0/255.0, 1.0};
text_color :: Vector4.{189.0/255.0, 179.0/255.0, 149.0/255.0, 1.0};

// CURSOR_COLOR :: Vector4.{.9, .0, .0, 1.0};
// CURSOR_COLOR :: Vector4.{.8, .1, .1, 1.0};
CURSOR_COLOR :: #run RgbToVec4(134, 224, 143);
SELECTION_COLOR :: Vector4.{.3, .5, .6, .5};

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

x_cursor_scroll_treshold := 30;
y_cursor_scroll_treshold := 30;

show_debug_info := DEBUG;
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
        f := my_font.*;
        print("em_width: % ; character_height: %\n", f.em_width, f.character_height);
    }

    footer_height = my_font.character_height*1.5;

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;
    second_elapsed := false;

    string_for_utf32_to_utf8 := alloc_string(4); // @HEAP

    editor = create_an_editor_instance();
    load_file_from_command_line(editor); // @Temporary

    while !should_quit {
        #if !DEBUG {
            #if OS == .WINDOWS {
                WaitMessage();
            }
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

            #if DEBUG {
                if event.key_code == .ESCAPE {
                    if event.key_pressed should_quit = true;
                }
            }

            getrect_handle_event(event);

            if editor_in_focus {
                handled := Keymap.keymap_handle_event(default_keymap, event);
                if handled continue;

                if event.type == .TEXT_INPUT {
                    if event.utf32 == 0x7F /* 127 */ continue;  // Prevent insertion of the "Delete character" @Hacky @Todo Ctrl-Backspace
                    memset(string_for_utf32_to_utf8.data, 0, 4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);

                    editor, buffer := get_active_editor_and_buffer(); // @Temporary
                    insert_text_at_cursor(buffer, string_for_utf32_to_utf8);
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

        editor.active_buffer._cursor.x_cache = -1; // Because the prepare text is very slow
        get_cursor_x(editor.active_buffer, *editor.active_buffer._cursor);     // @temporary

        if show_debug_info {
            last_simulation_time = (seconds_since_init()-last_time)*1000;

            editor, buffer := get_active_editor_and_buffer();
            using editor;

            // PrintDev("F1 toggle dev | F2 hidden chars\n");
            // PrintDev("----------------------------\n");
            PrintDev("w: % ; h: % ; t: % ; l: %\n", window_width, window_height, top_offset, left_offset);
 
            row := find_row_index(buffer, buffer._cursor.pos);
            col := get_cursor_col(buffer, *buffer._cursor);
            cx  := get_cursor_x(buffer, *buffer._cursor);
            cy  := get_cursor_y(buffer, *buffer._cursor);

            PrintDev("p: % r: % col: % cx: % cy: %\n", buffer._cursor.pos, row, col, cx, cy);
            PrintDev("rows: % ; gentime: %ms\n", active_buffer.row_table.count, formatFloat(active_buffer.row_table_recalc_time, trailing_width=2));
            s := to_string(buffer);
            PrintDev("chars: % bytes: %\n", utf8_count_chars(s), s.count);
            
            t := "";
            c := utf8_count_chars(t);
            PrintDev("chars: %\n", c);
        }


        draw_frame(text, second_elapsed, last_time);
        Simp.swap_buffers(my_window, vsync=false);

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

row_first_byte_offset :: inline (row: Row_Info) -> s64 {
    return row.end_byte_offset - row.bytes;
}

row_last_byte_offset :: inline (row: Row_Info) -> s64 {
    return row.end_byte_offset;
}

find_row_index :: (using buffer: *Buffer, offset: s64) -> s64 {
    if offset == 0 return 0;

    assert(row_table.count != 0);
    for row, row_index: row_table {
        if offset <= row.pos {
            return row_index;
        }
    }

    return row_table.count-1;
}

find_next_row_index :: (using buffer: *Buffer, offset: s64) -> (success: bool, index: s64) {
    index := find_row_index(buffer, offset);
    if !(index+1 < row_table.count) return false, -1;
    return true, index+1;
}

// get_cursor_row :: (using editor: *Editor) -> s64 {
//     if cursor_pos == 0 return 1; // @Ambiguity: use start at 0 just like we do in get_cursor_col()

//     buffer := editor.active_buffer;
//     using buffer;

//     assert(row_table.count != 0);
//     for row_table {
//         if cursor_pos <= it.pos {
//             return it_index+1;
//         }
//     }

//     return row_table.count;
// }

get_cursor_row :: (using buffer: *Buffer, cursor: *Cursor) -> s64 {
    if cursor.pos == 0 return 1;
    assert(row_table.count != 0);
    
    for row, row_index: row_table {
        if cursor.pos <= row.pos {
            return row_index + 1;
        }
    }

    return row_table.count;
}

get_cursor_col :: (using buffer: *Buffer, cursor: *Cursor) -> s64 {
    return get_col_index(buffer, cursor.pos);
}

get_col_index :: (using buffer: *Buffer, cursor: *Cursor) -> s64 {
    return get_col_index(buffer, cursor.pos);
}

get_col_index :: (using buffer: *Buffer, pos: s64) -> s64 {
    for row, row_index: row_table {
        if pos <= row.pos {
            cols   := 0;
            offset := row_first_byte_offset(row);
            while offset < pos {
                byte := data[offset];
                offset += 1 + trailingBytesForUTF8[byte];
                cols += 1;
            }

            return cols;
        }
    }

    return 0;
}

char_byte_offset :: inline (s: string, start: s64) -> s64 {
    assert(start < s.count); // Do we want to assert this?
    byte := s[start];
    return start + 1 + trailingBytesForUTF8[byte];
}

// @Cleanup: naming
next_char_byte_offset :: inline (s: string, start: s64) -> s64 {
    assert(start < s.count); // Do we want to assert this?
    byte := s[start];
    return start + 1 + trailingBytesForUTF8[byte];
}

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

num_of_chars_in_row :: (buffer: *Buffer, row: Row_Info) -> s64 {
    pos   := row_first_byte_offset(row);
    end   := row.pos;
    assert(row.pos <= buffer.count, "% %", row.pos, buffer.count);

    chars := 0;
    while pos < end {
        byte := buffer.data[pos];
        pos  += 1 + trailingBytesForUTF8[byte];
        chars += 1;
    } 

    return chars;
}

byte_offset_to_col_index :: (buffer: *Buffer, offset: s64) -> s64 {
    index := find_row_index(buffer, offset);
    row := buffer.row_table[index];
    start := row_first_byte_offset(row);
    
    t := slice(buffer, start, offset-start);
    return utf8_count_chars(t);
}

get_cursor_rel_x :: inline (editor: *Editor, buffer: *Buffer, cursor: *Cursor) -> s64 {
    x := get_cursor_x(buffer, cursor);
    return xx (x - editor.left_offset + my_font.em_width);
}

get_cursor_rel_y :: inline (editor: *Editor, buffer: *Buffer, cursor: *Cursor) -> s64 {
    row_index   := find_row_index(buffer, cursor.pos);
    line_height := get_line_height(row_index + 1);
    return xx (window_height - line_height + editor.top_offset);
}

get_cursor_y :: inline (buffer: *Buffer, cursor: *Cursor) -> s64 {
    if cursor.pos == 0 return window_height;
    row_index := find_row_index(buffer, cursor.pos);
    return window_height - xx get_line_height(row_index + 1);
}

get_cursor_x :: inline (buffer: *Buffer, cursor: *Cursor) -> s64 {
    if cursor.pos == 0 return 0;
    if cursor.x_cache != -1 return cursor.x_cache;

    // @Speed !!!!!! the prepare_text is so slooow!

    row_index := find_row_index(buffer, cursor.pos);
    row := buffer.row_table[row_index];
    first_byte := row.pos-row.cols;
    text := to_string(buffer);
    text = slice(text, first_byte, cursor.pos-first_byte);
    cx := Simp.prepare_text(my_font, text);

    cursor.x_cache = cx; // @Temporary

    return cx;
}

// insert_text :: (buffer: *Buffer, pos: s64, text: string) {
//     maybe_grow(buffer, text.count);

//     left := buffer.data;
//     insert_at := left + pos;
//     new_right := insert_at + text.count;
//     right_rem_size := buffer.count - (insert_at-left);

//     if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);

//     memcpy(insert_at, text.data, text.count);

//     buffer.count += text.count;
//     buffer.rebuild_row_table = true;
// }

insert_text_at_cursor :: inline (using buffer: *Buffer, s: string) {
    maybe_grow(buffer, s.count);

    insert_at      := buffer.data  + _cursor.pos;
    new_right      := insert_at    + s.count;
    right_rem_size := buffer.count - (insert_at - buffer.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size); // @Cleanup shift_right procedure
    copy(insert_at, s.data, s.count);

    buffer.count += s.count;
    buffer.rebuild_row_table = true;

    set_cursor_pos(buffer, *_cursor, _cursor.pos+s.count, horizontal=true);

    buffer.dirty = true;
}

//  @Cleanup: Naming
find_index_from_right_until_not :: (s: string, byte: u8, start_index: s64 = 0) -> s64  #no_abc {
    assert(start_index > -1 && start_index < s.count);

    cursor := start_index;
    while cursor >= 0 {
        if s[cursor] != byte return cursor;
        cursor -= 1;
    }

    return -1;
}

//  @Cleanup: Naming
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
    // pixel_height := font_size; // print(">>> %\n", window_height/40);
    pixel_height := 15;

    my_font = Simp.get_font_at_size("data", "firacode-retina/FiraCode-Retina.ttf", pixel_height);
    // my_font = Simp.get_font_at_size("data", "local/CascadiaCode.ttf", pixel_height);
    print("font: %\n", my_font.*);
    // print("%\n\n", my_font.*);
    assert(my_font != null);
}

current_font_width :: () -> s64 {
    assert(my_font != null);
    return my_font.em_width;
}

first_visible_row_index :: inline (editor: *Editor, using buffer: *Buffer) -> s64 {
    line_height := get_line_height();
    start_row: s64 = xx (editor.top_offset / line_height);
    start_row = clamp(start_row - 1, 0, row_table.count-1);

    return start_row;
}

last_visible_row_index :: inline (using buffer: *Buffer) -> s64 {
    viewport_h := window_height-footer_height*2; // @Hacky

    line_height := get_line_height();
    end_row: s64 = xx ((editor.top_offset + viewport_h) / line_height);
    end_row = clamp(end_row+1, 0, row_table.count-1);

    return end_row;
}

get_line_height :: inline (row: s64 = 1) -> float32 {
    return row * (my_font.default_line_spacing + line_height);
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

#if OS == .WINDOWS {
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
}

// @Temporary
load_file_from_command_line :: (editor: *Editor) {
    Args :: struct {
        file: string;
    };

    args_success, args, is_set, free_args := parse_arguments(Args);
    // print("% % % %\n", args_success, args, is_set, free_args);
    if !args_success {
        exit(1);
    }

    for free_args {
        open_file(editor, it);
    }

    // if is_set.file {
    //     open_file(editor, args.file);
    // }

    // assert(free_args.count > 1);
}

#load "unicode.jai";
#load "editor.jai";
#load "keymap.jai";
#load "draw.jai";
#load "buffer.jai";
#load "cursor.jai";

#import "System";
#import "Basic";
#import "File";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Input";
Keymap :: #import "Keymap";
#import "Unicode";
Simp :: #import "Simp";
#import "GetRect";
#import "Memory";
#import "Command_Line";

c_malloc  :: (size: u64) -> *void                #foreign crt "malloc";
c_free    :: (memory: *void)                     #foreign crt "free";
c_realloc :: (memory: *void, size: u64) -> *void #foreign crt "realloc";
c_memmove :: (dest: *void, src: *void, count: u64) -> *void #foreign crt "memmove";

#if OS == .WINDOWS {
    crt :: #system_library "msvcrt";  // For malloc, free on Windows
} else #if OS == .MACOS || OS == .IOS || OS == .LINUX || OS == .ANDROID {
    crt :: #system_library "libc";
}