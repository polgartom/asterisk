
window_width  := 1200;
window_height := 1200;

should_quit := false;

last_time : float64;
last_simulation_time : float64;
last_showed_sim_time : float64;
last_rendering_time  : float64;

// Blackboard theme
bg_color          :: #run RgbaToVec4(12, 16, 33);
text_color        :: #run RgbaToVec4(248, 248, 248);
CURSOR_COLOR      :: #run Hex4ToVec4Rgba(0xFBDE2Dc0);
CURSOR_COLOR_TEXT :: #run RgbaToVec4(12, 16, 33);
SELECTION_COLOR   :: #run Hex4ToVec4Rgba(0xffffff20);
HIGHLIGHT_COLOR   :: #run RgbaToVec4(115, 255, 255, .45);

CURRENT_LINE_INDICATOR_STYLE       :: Current_Line_Indicator_Style.FRAME;
CURRENT_LINE_INDICATOR_COLOR       :: #run Hex4ToVec4Rgba(0x5D2A6DC0);
CURRENT_LINE_INDICATOR_FRAME_WIDTH :: 2.0;

Current_Line_Indicator_Style :: enum u32 {
    NONE;
    FRAME;
    HIGHLIGHT;
}

DEFAULT_FONT_PATH :: "firacode-retina/FiraCode-Retina.ttf";

my_font: *Simp.Dynamic_Font;
font_width: s64;
line_height :: 0.0;
font_size   :: 15;

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
// current_theme: s32 = xx Default_Themes.Default;
current_theme: s32 = xx Default_Themes.Bentonite;
my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
// GETRECT - END

my_window: Window_Type;

footer_height: float;

frame := 0;
current_frame := 0;

Args :: struct {
    workdir: string;
}

powersaving := POWERSAVE_BUILD;

main :: () {
    print("\n\n");

    {    
        format := *context.print_style.default_format_struct;
        format.use_newlines_if_long_form = true;
        format.indentation_width = 2;
    }

    {
        format := *context.print_style.default_format_int;
        format.digits_per_comma = 3;
        format.comma_string = ",";
    }

    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    args_success, args, is_set, files_from_cmdline := parse_arguments(Args);
    if !args_success {
        exit(1);
    }

    {
        workdir := get_working_directory();
        if args.workdir {
            dir := File.get_absolute_path(args.workdir);
            if is_directory(dir) {
                workdir = dir;
            } else {
                log_error("Unable to locate the given directory's absolute location specified with the '-workdir %' argument!\n", dir);
            }   
        }

        path_overwrite_separators(workdir, #char "/");
        set_working_directory(workdir);
        
        file_browser_change_directory(workdir);

        print("Working directory: '%'\n", workdir);
    }

    init_keymaps();

    my_window = create_window(window_name=WINDOW_NAME, width=window_width, height=window_height);
    Simp.set_render_target(my_window);

    my_init_fonts();
    ui_init(); // GetRect

    footer_height = my_font.character_height*1.5;

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;
    second_elapsed := false;

    string_for_utf32_to_utf8 := alloc_string(4); // @HEAP

    editor = create_editor();
    
    for filepath: files_from_cmdline {
        open_file_or_create_empty_buffer(editor, filepath);
    }

    if !editor.active_buffer {
        editor.active_buffer = create_or_find_empty_buffer(editor);
    }

    while !should_quit {
        #if POWERSAVE_BUILD {
            if powersaving then WaitMessage();
        }

        current_frame = frame;
        defer frame += 1;

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

        {
            enable(*keymap_set, editor_keymap, mode == .EDITOR);
            enable(*keymap_set, widget_keymap, mode == .WIDGET);
        }

        for event : events_this_frame {
            if event.type == .QUIT {
                // print("quit!\n");
                should_quit = true;
                break;
            }

            getrect_handle_event(event);

            #if DEBUG {
                if mode == .EDITOR && event.key_code == .ESCAPE {
                    if event.key_pressed should_quit = true;
                }
            }

            last_input_event = event;
            handled := handle_event(*keymap_set, event);
            if handled continue;
            
            if mode == .EDITOR {
                if event.type == .TEXT_INPUT {
                    if event.utf32 == 0x7F continue; // @Hacky Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace
                    ZeroMemory(string_for_utf32_to_utf8.data, 0x4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);

                    editor, buffer := get_active_editor_and_buffer(); // @Temporary
                    insert_text_at_cursor(buffer, *buffer._cursor, string_for_utf32_to_utf8);
                }
            }
        }

        text := to_string(editor.active_buffer);
        if editor.active_buffer.rebuild_row_table {
            rescan_line_ends(editor.active_buffer);
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

        assert(editor.active_buffer != null && editor.active_buffer.initialized);

        editor.active_buffer._cursor.x_cache = -1; // Because the prepare text is very slow
        get_cursor_x(editor.active_buffer, *editor.active_buffer._cursor);     // @temporary

        if show_debug_info {
            debug_time := seconds_since_init();

            editor, buffer := get_active_editor_and_buffer();
            using editor;

            #if 1 {
                PrintDev("w: % ; h: % ; t: % ; l: %\n", window_width, window_height, top_offset, left_offset);
    
                row := find_row_index(buffer, buffer._cursor.pos);
                col := byte_pos_to_col_pos(buffer, buffer._cursor.pos);
                cx  := get_cursor_x(buffer, *buffer._cursor);
                cy  := get_cursor_y(buffer, *buffer._cursor);

                PrintDev("p: % r: % col: % cx: % cy: %\n", buffer._cursor.pos, row, col, cx, cy);
                
                PrintDev("rows: % ; gentime: %ms ; row_table size: %\n", 
                    active_buffer.row_table.count, 
                    formatFloat(active_buffer.row_table_recalc_time, trailing_width=4),
                    cast(s64)(size_of(type_of(buffer.row_table)) * buffer.row_table.count)
                );

                #if 0 {
                    // The utf8_count_chars() is very slow if we have a larger buffer
                    s := to_string(buffer);
                    PrintDev("chars: % bytes: %\n", utf8_count_chars(s), s.count);
                }
                
                mx, my, ok := get_mouse_pointer_position(right_handed=false);
                PrintDev("mouse -> x % y % | ok: %\n", mx, my, ok);

                debug_time = (seconds_since_init() - debug_time) * 1000;
                PrintDev("[DEBUG TIME] %ms\n", formatFloat(debug_time, trailing_width=4));
            }

            last_simulation_time = (seconds_since_init()-last_time)*1000;
        }

        draw_frame(text, second_elapsed, last_time);
        swap_buffers(my_window);
        
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

find_next_row_index :: (using buffer: *Buffer, offset: s64) -> (success: bool, index: s64) {
    index := find_row_index(buffer, offset);
    if !(index+1 < row_table.count) return false, -1;
    return true, index+1;
}

get_cursor_row :: (using buffer: *Buffer, cursor: *Cursor) -> s64 {
    if cursor.pos == 0 return 1;
    assert(row_table.count != 0);
    
    for row, row_index: row_table {
        if cursor.pos <= row.end {
            return row_index + 1;
        }
    }

    return row_table.count;
}

// Return the relative column index
byte_pos_to_col_pos :: (buffer: *Buffer, byte_pos: s64) -> s64 {
    assert(byte_pos <= buffer.count, "byte_pos: % ; buffer.count: %\n", byte_pos, buffer.count);

    col := 0;
    
    row := find_row(buffer, byte_pos);
    at  := row.start;
    while at < byte_pos {
        byte := buffer.data[at];
        at += 1 + trailingBytesForUTF8[byte];
        col += 1;
    }
    assert(at == byte_pos);

    return col;
}

get_row_index_from_y_px :: (y: float, y_is_relative := false) -> (row_index: s64) {
    editor, buffer := get_active_editor_and_buffer();

    if y_is_relative {
        y += editor.top_offset;
    }

    approx_index := cast(s64)floor(y / get_line_height());
    if (approx_index > buffer.row_table.count - 1) || (approx_index < 0) return -1;

    return approx_index;
}

get_row_col_from_x_px :: (row_index: s64, x: float, x_is_relative := false) -> (col: s64, bytes_from_left: s64) {
    editor, buffer := get_active_editor_and_buffer();
    
    if x_is_relative {
        x += editor.left_offset;
    }

    s := get_row_as_string(buffer, row_index);

    bytes_from_left := 0;
    col             := 0;
    left            := 0.0;
    while s.count {
        cw := Simp.get_character_width_in_pixels(my_font, s.data, .LEFT_JUSTIFIED);
        if cast(float)x <= left break;
                
        byte_step := 1 + trailingBytesForUTF8[s[0]];
        s = advance(s, byte_step);
        
        left += cw;
        col += 1;
        bytes_from_left += byte_step;
    }

    return col, bytes_from_left;
}

get_selected_rows :: (buffer: *Buffer, cursor: *Cursor) -> [..] Row_Info {
    rows: [..] Row_Info;
    
    if !has_selection(cursor) return rows;

    start, end := selected_range(cursor);
    at := start;
    while at <= end {
        row := find_row(buffer, at);
        array_add(*rows, row);
        at = row.end + 1;
    }

    return rows;
} 

measure_text_width :: inline (text: string) -> s64 {
    return Simp.prepare_text(my_font, text);
}

measure_text_width :: inline (font: *Simp.Dynamic_Font, text: string) -> s64 {
    return Simp.prepare_text(font, text);
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
    assert(row.end <= buffer.count, "% %", row.end, buffer.count);

    chars := 0;

    at := row.start;
    while at < row.end {
        byte  := buffer.data[at];
        at    += 1 + trailingBytesForUTF8[byte];
        chars += 1;
    } 

    assert(at == row.end);

    return chars;
}

// byte_offset_to_col_index :: (buffer: *Buffer, offset: s64) -> s64 {
//     index := find_row_index(buffer, offset);
//     row := buffer.row_table[index];
//     start := row.start;
    
//     t := slice(buffer, start, offset-start);
//     return utf8_count_chars(t);
// }

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

    cx := 0;
    defer cursor.x_cache = cx; // @Temporary

    row := find_row(buffer, cursor.pos);
    if row.start == cursor.pos return 0;

    s := get_row_as_string(buffer, row);
    s = slice(s, 0, cursor.pos - row.start);
    cx = measure_text_width(my_font, s);

    return cx;
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
    pixel_height := font_size;

    #if USE_BAKED_FONT {
        #import "Compiler";
        _BAKED_FONT_DATA :: #run -> [] u8 {
            filename := tprint("%/../data/firacode-retina/FiraCode-Retina.ttf", #filepath);
            font_binary, success := File.read_entire_file(filename);
            if !success compiler_report(tprint("Unable to load font file '%'!\n", filename));

            result := add_global_data(cast([] u8)font_binary, .READ_ONLY);
            return result;
        }

        my_font = Simp.get_font_at_size(_BAKED_FONT_DATA, pixel_height);
    } else {
        my_font = Simp.get_font_at_size("./../data", "firacode-retina/FiraCode-Retina.ttf", pixel_height);
        // my_font = Simp.get_font_at_size("./../data", "local/font.ttf", pixel_height+2);
    }

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

last_visible_row_index :: inline (editor: *Editor, using buffer: *Buffer) -> s64 {
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

count_whitespaces_from_left :: (s: string) -> s64 {
    count := 0;
    for c: s {
        if !is_whitespace(c) break;
        count += 1;
    }

    return count;
}

#if OS == .WINDOWS {
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
}

// @Temporary
load_file_from_command_line :: (editor: *Editor) {
    return;
    // Args :: struct {
    //     file: string;
    // };

    // args_success, args, is_set, free_args := parse_arguments(Args);
    // // print("% % % %\n", args_success, args, is_set, free_args);
    // if !args_success {
    //     exit(1);
    // }

    // for free_args {
    //     open_file(editor, it);
    // }

    // if is_set.file {
    //     open_file(editor, args.file);
    // }

    // assert(free_args.count > 1);
}

utf8_count_chars :: inline (s: string) -> s64 {
    count := 0;
    while s {
        advance(*s, 1 + trailingBytesForUTF8[s[0]]);
        count += 1;
    }

    return count;
}

utf8_advance_one_character :: (s: string) -> string {
    assert(s.count > 0);
    
    size := 1 + trailingBytesForUTF8[s[0]];
    t := advance(s, size);

    return t;
}

utf8_advance_one_character :: (s: *string) {
    assert(s.count > 0);
    
    size := 1 + trailingBytesForUTF8[s.data[0]];
    advance(s, size);
}

find_index_from_left_nocase :: (s: string, substring: string, start_index := 0) -> int, found: bool {
    if s.count < substring.count  return -1, false;

    for start_index..s.count-substring.count {
        t := slice(s, it, substring.count);
        if equal_nocase(t, substring) return it, true;
    }

    return -1, false;
}

scan_dir :: (_path: string, recursive := false, follow_directory_symlinks := true, $files_only := true) -> [] string #must {
    path := _path;

    if path.count > 1 && ends_with(path, "/") then path.count -= 1;

    assert(is_directory(path)); // Error hint for the user @Todo
    
    items : [..] string; // IS IT USING THE TEMP ALLOCATOR???

    visitor :: (info: *File_Visit_Info, user_data: *[..] string) {
        #if files_only {
            if !info.is_directory && !info.is_symlink {
                array_add(user_data, copy_string(info.full_name));
            }
        } else {
            array_add(user_data, copy_string(info.full_name));
        }
    }

    visit_files(path, recursive, *items, visitor, visit_directories=true, follow_directory_symlinks=follow_directory_symlinks);

    return items;
}

RgbaToVec4 :: (r: u8, g: u8, b: u8, alpha: float = 1.0) -> Vector4 #expand {
    return Vector4.{
        r/255.0, 
        g/255.0, 
        b/255.0, 
        alpha
    };
}

Hex4ToVec4Rgba :: (hex: u32) -> Vector4 #expand {
    r := (hex>>24) & 0xFF;
    g := (hex>>16) & 0xFF;
    b := (hex>>8)  & 0xFF;
    a := (hex>>0)  & 0xFF;

    return Vector4.{
        r/255.0, 
        g/255.0, 
        b/255.0, 
        a/255.0
    };
}

Program_Mode :: enum u8 {
    // CORE;
    EDITOR;
    WIDGET;
};

mode := Program_Mode.EDITOR;


#load "workspace.jai";
#load "editor.jai";
#load "keymap.jai";
#load "cursor.jai";
#load "buffer.jai";
#load "memory.jai";
#load "render.jai";
#load "draw.jai";
#load "event.jai";
#load "widget.jai";
#load "language_support.jai";

CodeInspect :: #import,file "code_inspect.jai";

#import "System";
#import "Basic";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Unicode";
#import "GetRect";
#import "Command_Line";

File      :: #import "File";
Simp      :: #import "Simp";
Clipboard :: #import "Clipboard";

#if OS == .WINDOWS {
    crt :: #system_library "msvcrt";  // For malloc, free on Windows
} else #if OS == .MACOS || OS == .IOS || OS == .LINUX || OS == .ANDROID {
    crt :: #system_library "libc";
}