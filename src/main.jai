window_width  := 1200;
window_height := 1200;

should_quit := false;

current_time: float64 = 0.0;
last_time: float64 = 0.0;
frame_dt: float64 = 0.0;

last_simulation_time : float64;
last_showed_sim_time : float64;
last_rendering_time  : float64;

mode := Program_Mode.EDITOR;

DEFAULT_FONT_PATH :: "firacode-retina/FiraCode-Retina.ttf";

line_height :: 0.0;

TAB_SIZE_IN_SPACES :: 4;
TAB_SPACE_CHARS :: #run -> string {
    builder: String_Builder;
    builder.allocator = __temporary_allocator;
    for 0..TAB_SIZE_IN_SPACES-1 {
        append(*builder, " ");
    }
    return builder_to_string(*builder,, allocator = __temporary_allocator);
}

fps: float64;
frametime: float64;

window: Window_Type;

footer_height: float;

frame := 0;
second_elapsed := false;

Args :: struct {
    workdir: string;
}

executable_dir: string;
config_filepath: string;

main :: () {
    print("\n\n");

    {
        path := get_path_of_running_executable();
        executable_dir = copy_string(path_strip_filename(path));
        path_unify_sepa(executable_dir);
        assert(executable_dir.count > 0);

        config_filepath = join(executable_dir, "config.cfg", separator="");
    }

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

        set_working_directory(workdir);
        print("Working directory: '%'\n", workdir);
    }

    load_global_config();
    init_keymaps();

    init_fonts();

    window = create_window(window_name=WINDOW_NAME, width=window_width, height=window_height);
    Simp.set_render_target(window);

    ui_init(); // GetRect

    footer_height = primary_font.character_height*1.5;

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;

    string_for_utf32_to_utf8 := alloc_string(4);

    active_editor = create_editor();

    if !active_editor.active_buffer {
        active_editor.active_buffer = create_or_find_empty_buffer(active_editor);
    }

    if files_from_cmdline.count == 2 {
        // @Temporary
        open_file_or_create_empty_buffer(*editors[0], files_from_cmdline[0]);
        open_file_or_create_empty_buffer(*editors[1], files_from_cmdline[1]);

    } else {
        for filepath: files_from_cmdline {
            open_file_or_create_empty_buffer(active_editor, filepath);
        }
    }

    // @Temporary
    editor2 := create_editor();
    editor2.visible = false;
    if !editor2.active_buffer {
        editor2.active_buffer = active_editor.active_buffer;
    }

    watch_working_directory();

    while !should_quit {
        if !redraw_requested {
            wait_for_event();
        }

        {
            // @Decide: Do we want to do this on the main thread?
            // File watcher
            changed, needs_wait, wait_seconds := process_changes(*watcher);
            if changed {
                file_browser.scan_requested = true;
            }
        }

        update_window_events();
        clear_widget_events();

        redraw_requested = false;

        current_time = seconds_since_init();
        frame_dt = current_time - last_time;
        last_time = seconds_since_init();

        second_elapsed = false;
        if last_time - last_second_time > 1.0 {
            last_second_time = last_time;
            second_elapsed = true;
        }

        for get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit {
                    init_fonts();
                }
            }
        }

        {
            // @Cleanup: Remove it!!
            enable(*keymap_set, editor_keymap, mode == .EDITOR);
            enable(*keymap_set, widget_keymap, mode == .WIDGET);
        }

        wait_for_this_key_to_release: *u32; // Key_Code

        ctrl_released := false;

        for event : events_this_frame {
            // ll("%\n", event);

            register_widget_event(event);

            if event.type == .QUIT {
                Quit();
                break;
            }

            // This prevents some crazy situations like those in Adobe Premiere Pro. For example,
            // when we try to paste a text, it triggers the Paste() action while also inserting a "v" character.
            if wait_for_this_key_to_release {
                key_code := wait_for_this_key_to_release.*;
                if key_code == cast,no_check(u32)event.key_code && event.key_pressed == 0 {
                    wait_for_this_key_to_release = null;
                } else {
                    continue;
                }
            }

            last_input_event = event;
            handled := handle_event(*keymap_set, event);
            if handled {
                wait_for_this_key_to_release = *cast,no_check(u32)event.key_code;
                continue;
            }

            // We use this for the word completion for now
            if event.key_code == .CTRL && !event.key_pressed {
                ctrl_released = true;
            }

            if mode == .EDITOR {
                if event.type == .TEXT_INPUT && !event.ctrl_pressed {
                    if event.utf32 == 0x7F continue; // @Hacky Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace

                    zero_memory(string_for_utf32_to_utf8.data, 0x4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);

                    editor, buffer := get_active_editor_and_buffer(); // @Temporary
                    insert_text_at_cursor(editor, buffer, *editor.cursor, string_for_utf32_to_utf8);
                }
            }
        }

        if ctrl_released {
            if word_complete.active {
                word_complete_abort();
            }
        }

        for buffers {
            commit_buffer_changes(it);
        }

        for *editor: editors {
            assert(editor.active_buffer != null);
            assert(editor.active_buffer.initialized);

            editor.cursor.x_cache = -1; // Because the prepare text is very slow
            get_cursor_x(editor.active_buffer, *editor.cursor);     // @temporary
        }

        draw_frame();

        // sleep_milliseconds(6); // @Temporary
        reset_temporary_storage();

        array_reset(*debug_infos);
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

get_row_index_from_y_px :: (y: float, y_is_relative := false) -> (row_index: s64) {
    editor, buffer := get_active_editor_and_buffer();

    if y_is_relative {
        y += editor.top_offset;
    }

    approx_index := cast(s64)floor(y / get_line_height());
    if (approx_index > buffer.row_table.count - 1) || (approx_index < 0) return -1;

    return approx_index;
}

measure_text_width :: inline (font: *Simp.Dynamic_Font, text: string) -> s64 {
    return Simp.prepare_text(font, text);
}

// @Cleanup: naming
next_char_byte_offset :: inline (s: string, start: s64) -> s64 {
    assert(start < s.count); // Do we want to assert this?
    byte := s[start];
    return start + 1 + trailingBytesForUTF8[byte];
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

    if !font then font = primary_font;
    cx = measure_text_width(font, s);

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

init_fonts :: () {
    pixel_height := ui.font_size;

    #if USE_BAKED_FONT {
        #import "Compiler";
        _BAKED_FONT_DATA :: #run -> [] u8 {
            filename := tprint("%/../data/firacode-retina/FiraCode-Retina.ttf", #filepath);
            font_binary, success := File.read_entire_file(filename);
            if !success compiler_report(tprint("Unable to load font file '%'!\n", filename));

            result := add_global_data(cast([] u8)font_binary, .READ_ONLY);
            return result;
        }

        primary_font       = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_size);
        primary_font_xs    = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_xs_size);
    } else {
        primary_font       = Simp.get_font_at_size("./../data", "firacode-retina/FiraCode-Retina.ttf", ui.font_size);
        primary_font_xs    = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_xs_size);
    }

    assert(primary_font != null && primary_font_xs != null);
}

primary_font: *Simp.Dynamic_Font;
primary_font_xs: *Simp.Dynamic_Font;

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

first_visible_row :: inline (editor: *Editor, buffer: *Buffer) -> Row_Info {
    index := first_visible_row_index(editor, buffer);;
    
    return buffer.row_table[index];
}

last_visible_row :: inline (editor: *Editor, using buffer: *Buffer) -> Row_Info {
    index := last_visible_row_index(editor, buffer);

    return buffer.row_table[index];
}

get_line_height :: inline (row: s64 = 1, font: *Simp.Dynamic_Font = null) -> float32 {
    if !font then font = primary_font;

    return row * (font.default_line_spacing + line_height);
}

count_whitespaces_from_left :: (s: string, $space_character_only := false) -> s64 {
    count := 0;
    for c: s {
        #if space_character_only {
            if c != #char " " break;
        } else {
            if !is_whitespace(c) break;
        }
        count += 1;
    }

    return count;
}

// @Cleanup: Shorter name
seek_left_one_utf8_character_byte_pos :: (s: string, _point: int) -> int {
    point := _point - 1;
    while point > 0 {
        c := s[point];
        if (192 & c) != 128  return point;
        point -= 1;
    }

    return 0;
}

// @Cleanup: Shorter name
seek_right_one_utf8_character_byte_pos :: (s: string, point: int) -> int {
    if point == s.count {
        return point;
    }
    return point + 1 + trailingBytesForUTF8[s[point]];
}

// @Cleanup: Naming
seek_left_utf8_until_alphanum :: (s: string, point: int, $include_last_non_alphanum_char := true) -> int {
    while point {
        point = seek_left_one_utf8_character_byte_pos(s, point);
        if !is_alphanum(s[point]) {
            #if !include_last_non_alphanum_char {
                point += 1;
            }
            break;
        }
    }

    return point;
}

find_index_from_left_nocase :: (s: string, substring: string, start_index := 0) -> int, found: bool {
    if s.count < substring.count  return -1, false;

    for start_index..s.count-substring.count {
        t := slice(s, it, substring.count);
        if equal_nocase(t, substring) return it, true;
    }

    return -1, false;
}

path_unify_sepa :: inline (path: string) {
    for 0..path.count-1 {
        if path[it] == #char "\\" {
            path[it] = #char "/";
        }
    }
}

modify_string :: (target: *string, new_value: string) {
    assert(target != null);
    // print("modify_string: '%' -> '%'\n", target.*, new_value);
    if target.count free(target.*);
    target.* = copy_string(new_value);
}

advance :: (arr: *[] $T, steps := 1) {
    assert(arr.count - steps > -1 && steps > -1);

    arr.data  += steps;
    arr.count -= steps;
}

advance :: (arr: [] $T, steps := 1) -> [] T {
    assert(arr.count - steps > -1 && steps > -1);

    r: [] T;
    r.data  = arr.data  + steps;
    r.count = arr.count - steps;

    return r;
}


get_range_as_string :: (s: string, range: Range) -> string {
    return slice(s, range.start, range.end - range.start);
}

rgba_to_vec4 :: (r: u8, g: u8, b: u8, a: float = 1.0) -> Vector4 {
    return .{
        r / 255.0,
        g / 255.0,
        b / 255.0,
        a
    };
}

hex_to_vec4 :: (hex: u32) -> Vector4 {
    r := (hex>>24) & 0xFF;
    g := (hex>>16) & 0xFF;
    b := (hex>>8)  & 0xFF;
    a := (hex>>0)  & 0xFF;

    return .{
        r / 255.0,
        g / 255.0,
        b / 255.0,
        a / 255.0
    };
}

wait_for_event :: () {
    // @Todo: Wayland SDL
    
    #if OS == .WINDOWS {
        WaitMessage();
    }

    #if OS == .LINUX {
        X11:: #import "X11";
        xevent: X11.XEvent;
        while !X11.XPeekEvent(X11.x_global_display, *xevent) {}
    }
}

// @Cleanup
watcher: File_Watcher(void);
watch_working_directory :: () {

    VERBOSE_WATCHER :: false;//DEBUG;
    RECURSIVE_WATCH :: true;
    EVENTS_TO_WATCH :: File_Change_Event.ALL_EVENTS & (~(.MODIFIED|.ATTRIBUTES_CHANGED)); // We don't want to rescan recursively the entire working directory just because we've changed a file's content.

    file_change_callback :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
        ll("Change for path %: %", change.full_path, change.events);
    }

    if !init(
        *watcher, 
        file_change_callback, 
        null, 
        events_to_watch = EVENTS_TO_WATCH,
        merge_window_seconds = 1.0, 
        verbose = VERBOSE_WATCHER, 
        watch_recursively = RECURSIVE_WATCH
    ) {
        log_error("Could not initialize watcher");
        exit(3);
    }

    dirs_to_watch := string.[get_working_directory()];
    assert(dirs_to_watch.count > 0);

    ll("Adding folders: %", dirs_to_watch);
    if !add_directories(*watcher, ..dirs_to_watch) {
        log_error("Could not watch directories %", dirs_to_watch);
        exit(4);
    }

    ll("Starting to check % for changes in % directories.", ifx RECURSIVE_WATCH then "recursively" else "", dirs_to_watch);

    // deinit(watcher); // Those handlers are released during shutdown, right?
}

Program_Mode :: enum u8 {
    // CORE;
    EDITOR;
    WIDGET;
};

Range :: struct {
    start: s64;
    end:   s64;

#place start; 
    a: s64; b: s64;
}

is_overlap :: (r1: Range, r2: Range) -> bool {
    if r1.a > r2.b || r2.a > r1.a return false;
    return true;
}

get_overlap_range :: (r1: Range, r2: Range) -> bool, Range {
    if !is_overlap(r1, r2) return false, .{0,0};

    return true, .{max(r1.a, r2.a), min(r1.b, r2.b)};
} 

Anim :: struct {
    active: bool;
    start: float;
    target: float;
    started_at: float;
    duration: float;

    elapsed: float64;
}

Code_get_identifier_name :: (name: Code) -> string {
    #import "Compiler";

    // This is just to help with the Add macro above.

    node := compiler_get_nodes(name);
    if node.kind != .IDENT {
        compiler_report("Not an identifier.", make_location(node));
        return "";
    }

    ident := cast(*Code_Ident) node;
    return ident.name;
}

#load "ui.jai";
#load "editor.jai";
#load "editor_control.jai";
#load "cursor.jai";
#load "memory.jai";
#load "draw.jai";
#load "config.jai";
#load "color.jai";
#load "widget.jai";
#load "lang.jai";
#load "debug.jai";
#load "word_completion.jai";

#import "System";
#import "Basic";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Unicode";
#import "GetRect";
#import "Command_Line";
#import "Hash_Table";
#import "Sort";
#import "Random";
#import "Input";
#import "Keymap";
#import "File_Watcher";

File      :: #import "File";
Simp      :: #import "Simp";
Clipboard :: #import "Clipboard";
Hash      :: #import "Hash";

#if OS == .WINDOWS {
    crt :: #system_library "msvcrt";  // For malloc, free on Windows

    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;

} else #if OS == .MACOS || OS == .IOS || OS == .LINUX || OS == .ANDROID {
    crt :: #system_library "libc";
}