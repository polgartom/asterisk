window_width := 850;
window_height := 600;

should_quit := false;

background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

cursor_pos := 0;

last_time : float64;

key_left: u32;
key_right: u32;
key_down: u32;
key_up: u32;
key_backspace: u32;
key_shift: u32;


d :: print;

main :: () {
    print("\n--------------\n\n");

    base_path := path_strip_filename(get_path_of_running_executable());
    window := create_window(window_name="Asterisk", width=window_width, height=window_height);
    Simp.set_render_target(window);

    my_init_fonts();

    builder: String_Builder;
    init_string_builder(*builder);
    append(*builder, "|main :: () {|\n\n\n|} |");

    last_pressed_key : Key_Code = .UNKNOWN;
    last_pressed_key_time : float64;

    last_time = seconds_since_init();
    // d("> %\n", last_time);

    while !should_quit {
        // d("new frame\n");
        last_time = seconds_since_init();
        // d("> %\n", last_time);

        update_window_events();

        for get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit {
                    my_init_fonts();
                }
            }
        }

        c := background_color;
        Simp.clear_render_target(c.x, c.y, c.z, c.w);

        // if events_this_frame.count d(">> %\n", events_this_frame.count);

        key_left = 0;
        key_right = 0;
        key_down = 0;
        key_up = 0;
        key_backspace = 0;
        key_shift = 0;

        // print("%\n", events_this_frame);

        for event : events_this_frame { 
            if event.type == .QUIT {
                // print("quit!\n");
                should_quit = true;
                break;
            }

            if event.key_code == .ESCAPE {
                if event.key_pressed should_quit = true;
            }

            if event.type == .KEYBOARD {
                key := event.key_code;

                if event.key_pressed {
                    if 1 || last_pressed_key != key {
                        last_pressed_key = key;

                        if key == .ARROW_LEFT   key_left  = event.key_pressed;
                        if key == .ARROW_RIGHT  key_right = event.key_pressed;
                        if key == .ARROW_DOWN   key_down  = event.key_pressed;
                        if key == .ARROW_UP     key_up    = event.key_pressed;
                        
                        if key == .BACKSPACE {
                            key_backspace = event.key_pressed;

                            if cursor_pos != 0 {
                                text := builder_to_string(*builder, do_reset = true);
                                defer free(text);
                                for 0..text.count-1 {
                                    if it != cursor_pos-1 {
                                        append(*builder, text[it]);
                                    }
                                }
                                cursor_pos -= 1;
                            }
                        }

                        if key > 32 && key < 127 {
                            if !key_shift key += 32; // to lowercase, not be confused, it is reversed
                            append_char(*builder, key);
                        } else if key == .SPACEBAR || key == .ENTER {
                            append_char(*builder, key);
                        }
                    }

                    last_pressed_key_time = last_time - last_pressed_key_time;
                }

            }
        }

        text := builder_to_string(*builder, do_reset = false);
        defer free(text);

        if key_left && cursor_pos != 0 {
            cursor_pos -= 1;
        }

        if key_right && cursor_pos < text.count {
            cursor_pos += 1;
        }

        ml :: 5.0;

        // Draw text
        if text.count {
            t := text;
            i: s64 = 0;
            row := 1;
            while i != -1 {
                i = find_index_from_left(t, #char "\n");

                temp := t;
                if i != -1 temp.count = i;
                text_w := Simp.prepare_text(my_font, temp);
                bottom := xx window_height-(20.0*row);
                Simp.draw_prepared_text(my_font, xx ml, xx bottom, .{.8, .8, .8, 1});

                if i != -1 row += 1; advance(*t, i+1);
            }
        }

        // Draw caret
        {
            row := get_cursor_row(text);
            col := get_cursor_col(text);
            cx  := get_cursor_x(text);
            // print("cursor: r: % ; c: % ; x: %\n", row, col, cx);

            Simp.set_shader_for_color();

            top := 24.0 * row;
            left_pos := ml;
            last_char_width := 9;

            Simp.immediate_quad(cx+ml, window_height - top - 3, cx+ml+last_char_width, window_height - top, .{.9, .2, .3, 1.0});
        }

        Simp.swap_buffers(window);

        sleep_milliseconds(20);
        reset_temporary_storage();
    }
    
}

get_cursor_row :: (text: string) -> s64 {
    row := 1;
    for 0..text.count-1 {
        c := text.data[it];
        if c == #char "\n" then row += 1;
        if it == cursor_pos return row;
    }

    // assert(false);
    return row;
}

get_cursor_col :: (text: string) -> s64 {
    col := 0;
    for 0..text.count-1 {
        c := text.data[it];
        if c == #char "\n" then col = 0;
        if it == cursor_pos return col;
        col += 1;
    }

    // assert(false);
    return col;
}

get_cursor_x :: (text: string) -> s64 {
    
    cursor_row := get_cursor_row(text);
    cursor_col := get_cursor_col(text);

    row := 1;
    col := 0;

    while text.count {
        c := text.data[col];
        if !c break;

        if c == #char "\n" {
            if !(col+1 >= text.count) advance(*text, col+1);
            else if text.count advance(*text, 1);
            row += 1;
            col = 0;
        }

        // print("> % % ; % % ; [%]\n", cursor_row, cursor_col, row, col, c);
        if cursor_row == row && cursor_col == col {
            break;
        }

        if c != #char "\n" {
            col += 1;
        }
    }

    if col == 0 return 0;

    t := text;
    t.count = col;
    x := Simp.prepare_text(my_font, t);

    return x;
}

append_char :: (b: *String_Builder, key: Key_Code) {
    buf := get_current_buffer(b);

    text := builder_to_string(b, do_reset = true);
    defer free(text);

    should_free := false;

    if cursor_pos {
        a := text;
        a.count = cursor_pos;
        append(b, a);
    }

    if key == .SPACEBAR {
        append(b, #char " ");
    } else if key == .ENTER {
        append(b, #char "\n");
    } else if (key > 32 && key < 127) {
        c := map_key_to_string(key);
        defer free(c);
        append(b, c);
    }
    
    a := advance(text, cursor_pos);
    append(b, a);

    cursor_pos += 1;
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.
    path := path_strip_filename(get_path_of_running_executable());

    set_working_directory(path);
    pixel_height := window_height / 40;

    my_font = Simp.get_font_at_size("data", "FiraCode-Retina.ttf", pixel_height);
    assert(my_font != null);
}

#import "System";
#import "Basic";
#import "String";
// #import "String_Builder";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Keymap";
// #import "GetRect";
Simp    :: #import "Simp";