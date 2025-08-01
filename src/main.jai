// #run {
//     #if OS == .WINDOWS {
//         WR :: #import "Windows_Resources";
//         WR.disable_runtime_console();
//     }
// }

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    print("\n\n");

    {
        dir := path_strip_filename(get_path_of_running_executable());
        path_unify_sepa(dir);
        dir = trim_right(dir, "/");
        assert(dir.count > 0);

        executable_dir = copy_string(dir);
        config_dir = copy_string(dir);
        // working_dir = copy_string(get_workdir());
        set_workdir(get_workdir());
    }

    {
        format := *context.print_style.default_format_struct;
        format.draw_type_name = true;
        format.use_newlines_if_long_form = true;
        format.indentation_width = 2;
    }

    {
        format := *context.print_style.default_format_int;
        format.digits_per_comma = 3;
        format.comma_string = ",";
    }

    args_success, executable_args=, is_set, files_from_cmdline := parse_arguments(type_of(executable_args));
    if !args_success {
        exit(1); // @Todo
    }

    window = create_window(window_name=WINDOW_NAME, width=window_width, height=window_height);
    msaa := Simp.prepare_window(window, wanted_msaa = 8);
    Simp.set_render_target(window);
    window_width, window_height = Simp.get_render_dimensions(window);

    register_keymap_procedures();

    if executable_args.workdir && !set_workdir(executable_args.workdir) {
        log_error("Failed to set the '%' as working directory!", executable_args.workdir);
    }

    load_global_config();
    load_project_config();

    init_workspace(*workspace);
    
    init_fonts();

    footer_height = primary_font_xs.character_height*1.5; // @Cleanup !!!

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;

    string_for_utf32_to_utf8 := alloc_string(4);

    {
        // log_buffer    = create_readonly_buffer("logs");
        // logerr_buffer = create_readonly_buffer("errors");

        active_editor = *editors[0];
        active_editor.visible = true;

        if files_from_cmdline.count == 2 {
            // @Temporary
            open_file_or_create_empty_buffer(*editors[0], files_from_cmdline[0]);
            open_file_or_create_empty_buffer(*editors[1], files_from_cmdline[1]);

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

    while !should_quit {
        if !redraw_requested {
            wait_for_event();
        }

        update_window_events();
        clear_widget_events();

        redraw_requested = false;

        frame += 1;
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

        // process_changes(workspace.watcher);

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
                    editor, buffer := get_active_editor_and_buffer(); // @Temporary
                    if buffer.readonly continue;

                    if event.utf32 == 0x7F continue; // @Hacky Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace

                    zero_memory(string_for_utf32_to_utf8.data, 0x4);
                    character_utf32_to_utf8(event.utf32, *string_for_utf32_to_utf8);

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
            if !editor.visible continue;

            assert(editor.active_buffer != null);
            assert(editor.active_buffer.initialized);

            editor.cursor.x_cache = -1; // Because the prepare text is very slow
            get_cursor_x(editor.active_buffer, *editor.cursor);     // @temporary

            b := editor.active_buffer;
            if b.should_reload_from_disk {
                if !b.unsaved {
                    buffer_reload_from_disk(editor, b);
                } else {
                    answer := dialog_confirm(
                        "This file has been modified by another program. Do you want to reload it?", 
                        b.filepath,
                        .YESNO | .ICONASTERISK
                    );

                    if answer == {
                        case .YES; buffer_reload_from_disk(editor, b);
                        case .NO;  b.should_reload_from_disk = false;
                    }
                }
            }
        }

        draw_frame();
        
        array_reset(*debug_infos);

        reset_temporary_storage();

        // sleep_milliseconds(6); // @Temporary
    }
} @NoProfile

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
    _BAKED_FONT_DATA :: #run -> [] u8 {
        #import "Compiler";
        filename := tprint("%/../data/firacode-retina/FiraCode-Retina.ttf", #filepath);
        font_binary, success := File.read_entire_file(filename);
        if !success compiler_report(tprint("Unable to load font file '%'!\n", filename));

        result := add_global_data(cast([] u8)font_binary, .READ_ONLY);
        return result;
    }

    primary_font    = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_size);
    primary_font_xs = Simp.get_font_at_size(_BAKED_FONT_DATA, ui.font_xs_size);

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

free_string :: (target: *string) {
    if target.count && target.data free(target.*);
    target.data = null;
    target.count = 0;
}

modify_string :: (target: *string, new_value: string) {    
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

break_by_colon :: (line: string) -> (left: string, right: string) {
    // left  := line;

    // right := eat_until_space(line);  // 'right' now has everything from the first space to the end of the line.
    // left.count -= right.count;
            
    // right = eat_spaces(right);       // Trim the spaces from 'right'.

    found, left, right := split_from_left(line, ":");
    if !found return "", "";

    return trim(left), trim(right);
}

get_parent_dir_path :: (file_path: string) -> string {
    path := path_strip_filename(file_path);
    if path.count > 1 && path[path.count-1] == #char "/" then path.count -= 1;  // don't include trailing path separator
    return path;
}

should_descend_into_dir :: (path: string) -> bool {
    path_chunks := split(path, "/",, allocator = temp);
    for config.ignore {
        if contains(it, cast(u8) #char "/") {
            if platform_path_begins_with(path, it) return false;
        } else {
            // Match partial path
            for chunk : path_chunks {
                if platform_path_equals(chunk, it) return false;
            }
        }
    }

    return true;
}

should_ignore_path :: (path: string) -> ignore: bool {
    path_chunks := split(path, "/",, allocator = temp);

    for config.ignore {
        if contains(it, cast(u8) #char "/") {
            // Match whole path
            if wildcard_match(path, it) return true;
        } else {
            // Match partial path
            for chunk : path_chunks {
                if wildcard_match(chunk, it) return true;
            }
        }
    }

    return false;
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
} @NoProfile

start_file_watcher :: (watcher: *File_Watcher(void)) {
    VERBOSE_WATCHER :: false;//DEBUG;
    RECURSIVE_WATCH :: true;
    // EVENTS_TO_WATCH :: File_Change_Event.ALL_EVENTS & (~(.MODIFIED|.ATTRIBUTES_CHANGED)); // We don't want to rescan recursively the entire working directory just because we've changed a file's content.
    EVENTS_TO_WATCH :: File_Change_Event.ALL_EVENTS & (~(.ATTRIBUTES_CHANGED)); // We don't want to rescan recursively the entire working directory just because we've changed a file's content.

    file_change_callback :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
        if should_ignore_path(change.full_path) {
            return;
        }
        
        if change.events == .MODIFIED {
            buffer := find_buffer_by_filepath(change.full_path);
            if buffer {
                writetime_from_disk := file_modtime_and_size(change.full_path);
                r := compare_apollo_times(writetime_from_disk, buffer.last_writetime);
                
                buffer.should_reload_from_disk = r != 0;
            }

            return;
        }
        
        file_browser.scan_requested = true;
    }

    if !init(
        watcher, 
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
    if !add_directories(watcher, ..dirs_to_watch) {
        log_error("Could not watch directories %", dirs_to_watch);
        exit(4);
    }

    ll("Starting to check % for changes in % directories.", ifx RECURSIVE_WATCH then "recursively" else "", dirs_to_watch);

    // deinit(watcher); // Those handlers are released during shutdown, right?
}

os_path_begins_with :: (path: string, prefix: string) -> bool {
    #if OS == .WINDOWS {
        return begins_with_nocase(path, prefix);
    } else {
        return begins_with_nocase(path, prefix);
    }
}

get_workdir :: () -> string {
    dir := get_working_directory();
    path_unify_sepa(dir);
    return dir;
}

set_workdir :: (dir_: string) -> bool {
    dir := copy_temporary_string(dir_);
    path_unify_sepa(dir);
    ok := set_working_directory(dir);
    if ok modify_string(*working_dir, dir);

    return ok;
}

move_toward :: (a: float, b: float, amount_increasing: float, amount_decreasing := -1.0) -> float {
    if a > b {
        if amount_decreasing == -1  amount_decreasing = amount_increasing;

        a -= amount_decreasing;

        if a < b  a = b;
    } else {
        a += amount_increasing;
        if a > b  a = b;
    }

    return a;
}

ms_since_init :: inline () -> float64 {
    return seconds_since_init() * 1000;
}


Program_Mode :: enum u8 {
    // CORE;
    EDITOR;
    WIDGET;
};

Anim :: struct {
    active: bool;
    start: float;
    target: float;
    started_at: float;
    duration: float;

    elapsed: float64;
}



////////////////////////////////
//~ Globals

window: Window_Type;
window_width  := 1200;
window_height := 1200;

current_time: float64 = 0.0;
last_time: float64 = 0.0;
frame_dt: float64 = 0.0;
second_elapsed := false;

redraw_requested := true; // @Todo: Use this on WINDOWS and LINUX
fps: float64;
frametime: float64;
frame := 0;

last_simulation_time : float64;
last_showed_sim_time : float64;
last_rendering_time  : float64;

footer_height: float;

line_height := 0.0;

TAB_SIZE_IN_SPACES :: 4;
TAB_SPACE_CHARS :: #run -> string {
    builder: String_Builder;
    builder.allocator = __temporary_allocator;
    for 0..TAB_SIZE_IN_SPACES-1 {
        append(*builder, " ");
    }
    return builder_to_string(*builder,, allocator = __temporary_allocator);
}

executable_args: struct {
    workdir: string;
};

executable_dir: string;
config_dir:     string;
working_dir:    string;

should_quit := false;

mode := Program_Mode.EDITOR;

keymap_cfg_section_data: string; // @Todo
keymap_set:    Keymap_Set;
core_keymap:   *Keymap;
editor_keymap: *Keymap;
widget_keymap: *Keymap;

////////////////////////////////
//~ Platform

#if OS == .WINDOWS {
    platform_path_equals :: inline (path_a: string, path_b: string) -> bool {
        return equal_nocase(path_a, path_b);
    }

    platform_path_begins_with :: inline (path: string, subpath: string) -> bool {
        return begins_with_nocase(path, subpath);
    }

    platform_path_contains :: inline (path: string, subpath: string) -> bool {
        return contains_nocase(path, subpath);
    }

} else #if OS == .LINUX {
    platform_path_equals :: inline (path_a: string, path_b: string) -> bool {
        return path_a == path_b;
    }

    platform_path_begins_with :: inline (path: string, subpath: string) -> bool {
        return begins_with(path, subpath);
    }

    platform_path_contains :: inline (path: string, subpath: string) -> bool {
        return contains(path, subpath);
    }

} else {
    #assert false, "Unsupported OS";
}


////////////////////////////////
//~ Imports

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
#load "workspace.jai";
#load "project.jai";
#load "utils.jai";
#load "view.jai";
#load "font.jai";

#import "System";
#import "Basic";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Unicode";
#import "Command_Line";
#import "Sort";
#import "Random";
#import "Input";
#import "Keymap";
#import "File_Watcher";
#import "Hash_Table";
#import "Process";

Thread    :: #import "Thread";
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