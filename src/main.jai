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

    {
        format_struct := *context.print_style.default_format_struct;
        format_struct.draw_type_name = true;
        format_struct.use_newlines_if_long_form = true;
        format_struct.indentation_width = 2;
        format_int := *context.print_style.default_format_int;
        format_int.digits_per_comma = 3;
        format_int.comma_string = ",";
    }

    args_success, executable_args=, is_set, files_from_cmdline := parse_arguments(type_of(executable_args));
    if !args_success {
        log_error("Invalid args given!\n");
        exit(1); // @Todo
    }

    if executable_args.workdir && !set_workdir(executable_args.workdir) {
        log_error("Failed to set the '%' as working directory!\n", executable_args.workdir);
    }

    {
        dir := path_strip_filename(get_path_of_running_executable());
        path_unify_sepa(dir);
        dir = trim_right(dir, "/");
        assert(dir.count > 0);
        executable_dir = copy_string(dir);
        config_dir = copy_string(dir);
        set_workdir(get_workdir());
    }

    // Assign colors made during compile-time
    for DEFAULT_COLOR_MAP { COLOR_MAP[it_index] = it; }

    window = create_window(window_name=WINDOW_NAME, width=window_width, height=window_height);
    msaa := Simp.prepare_window(window, wanted_msaa = 8);
    Simp.set_render_target(window);
    window_width, window_height = Simp.get_render_dimensions(window);

    dpi_scale = get_dpi_scale(window);

    register_keymap_procedures();
    load_global_config();
    load_project_config();
    init_editor_buffers(files_from_cmdline);
    init_fonts();
    footer_height = r_font_sm.character_height*1.5; // @Temporary

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;

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
                    dpi_scale = get_dpi_scale(window);
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
        
        mouse_scrolled_on_frame = .none;
        mouse_was_down = mouse_down;
        mouse_clicked = false;
        mouse_dbl_clicked_on_frame = false;

        for event : events_this_frame {
            //ll("%\n", event);
            register_widget_event(event);

            if event.type == .QUIT {
                // Show the save or discard file message!
                Quit();
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
            
            if event.key_code == .SHIFT {
                vk_shift_down = cast(bool, event.key_pressed);
            }

            if event.type == .MOUSE_WHEEL {
                mouse_scrolled_on_frame = ifx event.wheel_delta < 0 then .down else .up;
            }
            
            if event.key_code == .MOUSE_BUTTON_LEFT {
                // @Cleanup
                mouse_down = cast(bool, event.key_pressed);
                if mouse_down {
                    mouse_down_last_time_ms = ms_since_init();
                } else {
                    // Maybe it's double click if we clicked on the previous frame and the interval between clicks was less than 250.0ms. 
                    if !mouse_dbl_clicked && (ms_since_init() - mouse_clicked_last_time_ms) <= 300.0 { // Windows default is 500 ms, many games use 250–350 ms.
                        mouse_dbl_clicked = true;
                        mouse_dbl_clicked_on_frame = true;
                        mouse_dbl_clicked_last_time_ms = ms_since_init();
                    } else {
                        mouse_dbl_clicked = false;
                    }
                
                    if (ms_since_init() - mouse_down_last_time_ms) <= 200.0 { // Max allowed delay between press and release → 150–250 ms (Most systems use around 200 ms.)
                        mouse_clicked = true;
                        mouse_clicked_last_time_ms = ms_since_init();
                    }
                }                
            }

            if mode == .EDITOR {
                if event.type == .TEXT_INPUT && !event.ctrl_pressed {
                    editor, buffer := get_active_editor_and_buffer(); // @Temporary
                    if buffer.readonly continue;
                    if event.utf32 == 0x7F continue; // @Hacky Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace
                    
                    c := character_utf32_to_utf8(event.utf32,, allocator=temporary_allocator);
                    insert_text_at_cursor(editor, buffer, *editor.cursor, c);
                }
            }
        }
        
        /*
        if mouse_dbl_clicked && (ms_since_init() - mouse_clicked_last_time_ms) > 300.0 {
            mouse_dbl_clicked = false;
        }
        */
        
        if click_action_cooldown_active && (ms_since_init() - click_action_cooldown_start_time_ms) > 200.0 {
            click_action_cooldown_active = false;
        }

        // log("clicked: % ; dbl_clicked: % ; down: % ; was_down: %\n", mouse_clicked, mouse_dbl_clicked, mouse_down, mouse_was_down);

        if mode == .WIDGET {
            os_set_cursor(.CUR_ARROW);
        }

        if mode == .EDITOR {
            if mouse_scrolled_on_frame != .none {
                mx, my, ok := get_mouse_pointer_position_right_handed();
                if ok for *e: editors {
                    if !e.visible continue;
                    // @Improve @Todo The rect_for_draw already contains the paddings so it won't if the mouse cursor on the paddings' area.
                    // Also the rect_for_draw include the editor footer rect.
                    if is_point_in_rect(e.rect_for_draw, Vector2.{xx mx, xx my}) {
                        if      mouse_scrolled_on_frame == .up   then scroll_up(e);
                        else if mouse_scrolled_on_frame == .down then scroll_down(e);
                        break;
                    }
                }
            }
            
            // @Cleanup It's confusing that we have to check whether the mouse pointer is inside the rect using right-handed coordinates,
            // but later, when determining the desired row index, we need to perform a similar check using left-handed coordinates.
            mx, my, ok := get_mouse_pointer_position(right_handed=true);
            if ok for *e: editors {
                if !e.visible continue;
                if is_point_in_rect(e.rect_for_draw, Vector2.{xx mx, xx my}) {
                    os_set_cursor(.CUR_BEAM);
                    
                    if !click_action_cooldown_active {
                        if mouse_dbl_clicked_on_frame {
                            SelectSimilarCharacters();
                            click_action_cooldown_active = true;
                            click_action_cooldown_start_time_ms = ms_since_init();
                        } else if mouse_down {
                            active_editor = e;
                            mx, my, ok := get_mouse_pointer_position(right_handed=false);
                            pos := byte_pos_from_mouse_xy(e, e.active_buffer, mx, my);
                            if pos != -1 {
                                set_cursor_pos(e.active_buffer, *e.cursor, pos, horizontal=true, with_selection=!vk_shift_down);
                            }
                            //click_action_cooldown_active = true;
                            //click_action_cooldown_start_time_ms = ms_since_init();
                        }
                    }                    
                }
            }
        }

        // @Cleanup
        if ctrl_released {
            if word_complete.active {
                word_complete_end();
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

        // if 1 {
        //     c := map_color_to_vec4(.BACKGROUND);
        //     Simp.clear_render_target(c.x, c.y, c.z, c.w);
        //     draw_global_debug_info(make_rect(0,0,window_width, window_height));
        // }
        // swap_buffers();
        
        array_reset(*debug_infos);
        reset_temporary_storage();
        // sleep_milliseconds(6); // @Temporary
    }
} @NoProfile

get_dpi_scale :: (window: Window_Type) -> float {
    // Copied from Focus editor
    #if OS == .WINDOWS {
        dpi := cast(float) GetDpiForWindow(window);
        return dpi / 96.0;
        // #if WINDOWS7 {
        //     return 1.0;  // poor Windows 7 users
        // } else {
        //     dpi := cast(float) GetDpiForWindow(window);
        //     return dpi / 96.0;
        // }
    }
    #if OS == .LINUX {
        /*
        * `Linux_Display` is empty on platforms other than Linux, so importing it should be basically
        * free on Windows/MacOS.
        */
        LD :: #import "Linux_Display"()(VALIDATE_USAGE = DEBUG);
        return LD.get_dpi_scaling_factor(window);
    }
}

get_mouse_pointer_position_right_handed :: inline () -> s64, s64, bool {
    mx, my, ok := get_mouse_pointer_position(right_handed=true);
    return mx, my, ok;
}

measure_text_width :: inline (font: *Simp.Dynamic_Font, text: string) -> s64 {
    return Simp.prepare_text(font, text);
}

should_descend_into_dir :: (path: string) -> bool {
    auto_release_temp();

    path_chunks := split(path, "/",, allocator=temp);
    workdir_chunks := split(get_workdir(), "/",, allocator=temp);
    path_chunks = platform_skip_matching_path_chunks(path_chunks, workdir_chunks);
    if !path_chunks return false;

    for ignore: config.ignore {
        if contains(ignore, cast(u8) #char "/") {
            if platform_path_begins_with(path, ignore) return false;
        } else {
            // Match partial path
            for chunk : path_chunks {
                if platform_path_equals(chunk, ignore) return false;
            }
        }
    }

    return true;
}

should_ignore_path :: (path: string) -> ignore: bool {
    auto_release_temp();
    
    path_chunks := split(path, "/",, allocator=temp);
    workdir_chunks := split(get_workdir(), "/",, allocator=temp);
    path_chunks = platform_skip_matching_path_chunks(path_chunks, workdir_chunks);
    if !path_chunks return false;

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

ms_since_init :: inline () -> float64 {
    return seconds_since_init() * 1000;
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

memmove :: inline (destination: *void, source: *void, count: s64) {
    c_memmove(destination, source, xx count);
}

zero_memory :: inline (ptr: *void, size: s64) {
    memset(ptr, 0, size);
}

Align :: inline (n: $T, $$ PAGE_SIZE: s64) -> T {
    return (n + PAGE_SIZE-1) & ~(PAGE_SIZE-1);
}

c_malloc  :: (size: u64) -> *void                               #foreign crt "malloc";
c_free    :: (memory: *void)                                    #foreign crt "free";
c_realloc :: (memory: *void, size: u64) -> *void                #foreign crt "realloc";
c_memmove :: (dest: *void, src: *void, count: u64) -> *void     #foreign crt "memmove";

//////////////////////////////
// Globals

executable_args: struct { workdir: string; };

window: Window_Type;
window_width  := 1200;
window_height := 1200;
dpi_scale := 1.0;
should_quit := false;
redraw_requested := true; // @Todo: Use this on WINDOWS and LINUX
frame := 0;
fps: float64;

current_time: float64 = 0.0;
last_time: float64 = 0.0;
frame_dt: float64 = 0.0;
second_elapsed := false;
frametime: float64;
last_simulation_time : float64;
last_showed_sim_time : float64;
last_rendering_time  : float64;

executable_dir: string;
config_dir:     string;
working_dir:    string;

footer_height: float;
line_height := 0.0;    // @Todo
letter_spacing := 0.0; // @Todo
tab_size := 4;
r_rect_radius := 8.0;

mode := Program_Mode.EDITOR;
Program_Mode :: enum u8 { EDITOR; WIDGET; };

keymap_cfg_section_data: string; // @Todo
keymap_set:    Keymap_Set;
core_keymap:   *Keymap;
editor_keymap: *Keymap;
widget_keymap: *Keymap;

vk_shift_down := false;

mouse_scrolled_on_frame: enum u8 {none; up; down;};
mouse_down := false; // @Temporary
mouse_was_down := false;
mouse_down_last_time_ms: float64;
mouse_clicked := false;
mouse_clicked_last_time_ms: float64;
mouse_dbl_clicked := false;
mouse_dbl_clicked_last_time_ms: float64;
mouse_dbl_clicked_on_frame := false;

click_action_cooldown_active := false;
click_action_cooldown_start_time_ms: float64;

cursor_shape := Cursor_Shape.BLOCK;
cursor_line_indicator := Cursor_Line_Indicator.FILLED;

Cursor_Shape :: enum u8 {BLOCK; LINE; UNDERSCORE;};
Cursor_Line_Indicator :: enum u8 {NONE; FILLED; BORDERED;};

os_current_cursor_kind := OS_Cursor_Kind.CUR_ARROW;

OS_Cursor_Kind :: enum u8 {
    CUR_NONE  :: 0;
    CUR_ARROW :: 1;
    CUR_BEAM  :: 2;
    CUR_WAIT  :: 3;
}

#if OS == .WINDOWS {
    os_set_cursor :: (kind: OS_Cursor_Kind) -> bool {
        // set_custom_cursor_handling(true);

        cur_rsrc_name := win32_cursor_resource_name_from_kind(kind); 
        handle := LoadCursorA(null /* HINSTANCE */, cur_rsrc_name); // Loads the cursor resource if not already loaded; otherwise returns its handle.
        if handle == null {
            error_code := GetLastError();
            log_error("Failed to load the cursor! error code: '%'\n", error_code);
            return false;
        }
            
        SetCursor(handle);
        os_current_cursor_kind = kind;
        
        return true;
    }

    win32_cursor_resource_name_from_kind :: (kind: OS_Cursor_Kind) -> LPCSTR {
        if kind == {
            case .CUR_ARROW; return IDC_ARROW;
            case .CUR_BEAM;  return IDC_IBEAM;
            case .CUR_WAIT;  return IDC_WAIT;
        };
        return null;
    }
}

////////////////////////////////
// Debug

show_debug_info := DEBUG;
debug_infos: [..] string;

PrintDev :: (fmt: string, args: .. Any) #expand {
    s := tprint(fmt, ..args);
    array_add(*debug_infos, s); // can we use temporary allocator for dynamic arrays?
} @PrintLike

ll :: (fmt: string, args: .. Any) #expand {
    s := tprint(fmt, ..args);
    log("[%] %", #procedure_name(), s);
} @PrintLike

MeasureProc :: () #expand {
    time := seconds_since_init();
    `defer {
        print("[%/time] %ms\n", #procedure_name(), (seconds_since_init() - time) * 1000);
    };
}

////////////////////////////////
// Imports

#load "common.jai";
#load "unicode.jai";
#load "editor.jai";
#load "control.jai";
#load "cursor.jai";
#load "draw.jai";
#load "config.jai";
#load "color.jai";
#load "widget.jai";
#load "lang.jai";
#load "word_completion.jai";
#load "view.jai";
#load "font.jai";

#import "System";
#import "Basic";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Window_Creation";
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
    #import "Windows";
    #import "Windows_Utf8";
    #import "Windows_Registry";

    crt :: #system_library "msvcrt";  // For malloc, free on Windows
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
    GetDpiForWindow :: (hWnd: HWND) -> u32 #foreign user32;
    SetCursorPos :: (x: s32, y: s32) -> s32 #foreign user32;
}

#if OS == .MACOS || OS == .IOS || OS == .LINUX || OS == .ANDROID {
    crt :: #system_library "libc";
}