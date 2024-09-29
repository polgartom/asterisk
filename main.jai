window_width := 850;
window_height := 650;

should_quit := false;

// background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

cursor_pos := 0;

last_time : float64;

key_left: u32;
key_right: u32;
key_down: u32;
key_up: u32;
key_backspace: u32;
key_shift: u32;

font_width: s64;

d :: print;

bg_color :: Vector4.{5.0/255.0, 36.0/255.0, 33.0/255.0, 1.0};
text_color :: Vector4.{189.0/255.0, 179.0/255.0, 149.0/255.0, 1.0};
ml :: 5.0; // margin left
line_height :: 0.0;//5.0; // what is this metric, px?

main :: () {
    print("\n--------------\n\n");

    base_path := path_strip_filename(get_path_of_running_executable());
    window := create_window(window_name="Asterisk", width=window_width, height=window_height);
    Simp.set_render_target(window);

    my_init_fonts();
    
    {
        f := <<my_font;
        print("em_width: % ; character_height: %\n", f.em_width, f.character_height);
    }

    builder: String_Builder;
    init_string_builder(*builder);
    append(*builder, "main :: () {\na := 21;\nb: s32;\nkacsax\n\npolgartom\n}");

    last_pressed_key : Key_Code = .UNKNOWN;
    last_pressed_key_time : float64;

    last_time = seconds_since_init();

    while !should_quit {
        last_time = seconds_since_init();

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

        c := bg_color;
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

            if event.type == .TEXT_INPUT {
                utf8_text := character_utf32_to_utf8(event.utf32);
                defer free(utf8_text);
                append_text(*builder, utf8_text);

            } else if event.type == .KEYBOARD {
                key := event.key_code;

                if event.key_pressed {
                    if 1 || last_pressed_key != key {
                        last_pressed_key = key;

                        if key == .ARROW_LEFT   key_left  = event.key_pressed;
                        if key == .ARROW_RIGHT  key_right = event.key_pressed;
                        if key == .ARROW_DOWN   key_down  = event.key_pressed;
                        if key == .ARROW_UP     key_up    = event.key_pressed;

                        // Delete a char from right
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

                        if key == .ENTER append_text(*builder, "\n");
                        if key == .TAB   append_text(*builder, "    ");
                    }

                    last_pressed_key_time = last_time - last_pressed_key_time;
                }

            }
        }

        text := builder_to_string(*builder, do_reset = false);
        defer free(text);

        // Handle caret movement
        if key_left && cursor_pos != 0 {
            cursor_pos -= 1;
            if cursor_pos != 0 {
                ch := get_char_at_string_index(text, cursor_pos);
                // print("> ci: % ; ch: %\n", cursor_pos, ch);
            }
        }

        if key_right && cursor_pos < text.count {
            cursor_pos += 1;
            if cursor_pos < text.count {
                ch := get_char_at_string_index(text, cursor_pos);
                // print("> ci: % ; ch: %\n", cursor_pos, ch);
            }
        }

        if key_up {
            t := text;
            t.count = cursor_pos;
            index := find_index_from_right(t, #char "\n");
            if index != -1 {
                // go to above row end
                cols := t.count-index;
                t.count = index;

                cursor_pos = index;

                if !(cursor_pos > 0 && text.data[cursor_pos-1] == #char "\n") {
                    // search for the first col index in upper row
                    index = find_index_from_right(t, #char "\n");
                    if index != -1 {
                        above_row_cols := cursor_pos - index;
                        if above_row_cols < cols {
                            cursor_pos = index + above_row_cols;
                        } else {
                            cursor_pos = index + cols;
                        }

                        // it's double end line so we should jump up by one
                        // also this "ln" check should be prevent the weird double jump up if 
                        // 2 line breaks are presents together
                        ln := get_char_at_string_index(text, cursor_pos) == "\n";
                        if t.count-index == 1 && !ln {
                            cursor_pos -= 1;
                        }
                    } else {
                        // its the first row
                        cursor_pos = ifx cols-1 > -1 then cols-1 else 0;
                    }
                }


            }

        }

        if key_down {
            // Move cursor down
            cursor_col := get_cursor_col(text);
            i := find_index_from_left(text, #char "\n", start_index=cursor_pos);
            if i != -1 {
                cursor_pos = i+1;
                col := 0;
                for i+1..text.count-1 {
                    if col == cursor_col || text.data[it] == #char "\n" {
                        break;
                    }
                    col += 1;
                }
                cursor_pos += col;
            }
        }

        // Draw caret
        {
            row := get_cursor_row(text);
            // col := get_cursor_col(text);
            cx  := get_cursor_x(text);
            // print("cursor: r: % ; c: % ; x: %\n", row, col, cx);

            Simp.set_shader_for_color();

            top := (my_font.default_line_spacing+line_height) * row;
            left_pos := ml;
            // _i := "("; // @Todo: find the highest character in the glyphs list
            // glyph_data := Simp.find_or_create_glyph_utf8(my_font, _i.data);
            // // print("%\n\n", <<glyph_data);
            // h := glyph_data.height;
            h := my_font.character_height;

            Simp.immediate_quad(cx+ml, window_height - top + (h-h*0.1), cx+ml+my_font.em_width, window_height - top - (h/2-(h*0.2)), .{.9, .0, .0, 1.0});
        }

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
                bottom := xx window_height - ((my_font.default_line_spacing+line_height) * row);
                Simp.draw_prepared_text(my_font, xx ml, xx bottom, text_color /*.{.8, .8, .8, 1}*/);

                if i != -1 {
                    row += 1; advance(*t, i+1);
                }
            }
        }

        Simp.swap_buffers(window);

        // sleep_milliseconds(20);
        reset_temporary_storage();
    }
    
}

get_char_at_string_index :: (t: string, index: s64) -> string {
    assert(index < t.count);
    c := advance(t, index);
    c.count = 1;
    return c;
}

get_cursor_row :: (text: string) -> s64 {
    if cursor_pos == 0 return 1;

    row := 1;

    ln := false;
    for 0..text.count-1 {
        c := text.data[it];

        defer { if ln row += 1; }
        if it == cursor_pos {
            // if ln row += 1;
            // print("ln: % ; row: %\n", ln, row);
            return row;      
        }

        ln = c == #char "\n";
    }

    // print("row: %\n", row);
    return row;
}

get_cursor_col :: (text: string) -> s64 {
    col := 0;
    ln := false;
    for 0..text.count-1 {
        c := text.data[it];
        if ln then col = 0;
        if it == cursor_pos return col;
        ln = c == #char "\n";
        col += 1;
    }

    return col;
}

ranges: [..] s64;

get_cursor_x :: (text: string) -> s64 {
    if cursor_pos == 0 return 0;
    col := 0;
    ln := false;
    for 0..cursor_pos {
        defer { if it < cursor_pos then col += 1; };

        c := text.data[it];
        if ln col = 0;
        ln = c == #char "\n";
    }

    return col * current_font_width();
}

append_text :: (b: *String_Builder, t: string) {
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

    cursor_pos += t.count;
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.
    path := path_strip_filename(get_path_of_running_executable());

    set_working_directory(path);
    pixel_height := 16; // print(">>> %\n", window_height/40);

    my_font = Simp.get_font_at_size("data", "FiraCode-Retina.ttf", pixel_height);
    // print("%\n\n", my_font);
    assert(my_font != null);
}

current_font_width :: () -> s64 {
    assert(my_font != null);
    return my_font.em_width;
}

#import "System";
#import "Basic";
#import "String";
// #import "String_Builder";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Keymap";
#import "Unicode";
// #import "GetRect";
#import "Unicode";
Simp    :: #import "Simp";