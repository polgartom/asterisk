window_width := 1650;
window_height := 450;

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
cursor_color :: Vector4.{.9, .0, .0, 1.0};

ml :: 5.0; // margin left
line_height :: 0.0;//5.0; // what is this metric, px?
font_size :: 15;

top_offset := 0.0;
left_offset := 0.0;

x_cursor_scroll_treshold := 30;
y_cursor_scroll_treshold := 30;

show_debug_info := true;
debug_infos: [..] string;

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
    
    sample := read_entire_file("main.jai");
    // sample := read_entire_file("sample.txt");
    append(*builder, sample);
    // print("-- %\n", code.count);
    // append(*builder, "main :: () {\na := 21;\nb: s32;\n}");

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

        for event : events_this_frame {
            
            if event.type == .QUIT {
                // print("quit!\n");
                should_quit = true;
                break;
            }

            if event.key_code == .ESCAPE {
                if event.key_pressed should_quit = true;
            }

            // print("%\n", event.key_code);

            if event.type == .TEXT_INPUT {
                utf8_text := character_utf32_to_utf8(event.utf32);
                defer free(utf8_text);
                append_text(*builder, utf8_text);

            } else if event.type == .KEYBOARD {
                key := event.key_code;

                if event.key_pressed {

                    // {
                    //     s := sprint("input | %", );    
                    //     array_add(*debug_infos, s);
                    // }

                    if event.key_code == .F1 {
                        show_debug_info = !show_debug_info;
                    }


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

            cy := get_cursor_y(text);
            // abs_y := cy - y_cursor_scroll_treshold;
            rel_y := get_cursor_rel_y(text);
            h := my_font.default_line_spacing + line_height;

            if cy-window_height < 0 {
                if xx (rel_y+h+ml) > window_height {
                    top_offset = xx (cy+ml+ml-window_height + h);
                }
            } else {
                remainer := xx (cy+ml+ml-window_height + h);
                if (remainer*-1) < h {
                    top_offset = 0.0;
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

            cy := get_cursor_y(text);
            abs_y := cy - y_cursor_scroll_treshold;
            // rel_y := get_cursor_rel_y(text);
            if abs_y < 0 {
                top_offset = xx (cy - y_cursor_scroll_treshold);
                // print("top_offset: %\n", top_offset);
            } else {
                top_offset = 0.0;
            }
        }

        // print("top_offset 2: %\n", top_offset);

        cx := get_cursor_x(text);
        if cx + x_cursor_scroll_treshold + my_font.em_width*2 > window_width {
            left_offset = xx (cx - window_width + x_cursor_scroll_treshold + (my_font.em_width*2));
        } else {
            left_offset = 0.0;
        }

        // Draw cursor
        {
            row := get_cursor_row(text);
            // col := get_cursor_col(text);
            cx  := get_cursor_x(text);
            // print("cursor: r: % ; c: % ; x: %\n", row, col, cx);

            Simp.set_shader_for_color();

            top  := window_height - (((my_font.default_line_spacing+line_height) * row) + (top_offset + ml));
            left := cx + ml - left_offset;
            h := my_font.character_height;

            Simp.immediate_quad(left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)), cursor_color);

            ch := get_char_at_string_index(text, cursor_pos);
            PrintDev("cursor | i: % % ; x1: % y1: % x2: % y2: %\n", cursor_pos, ch, left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)));
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
                
                bottom := window_height - ((my_font.default_line_spacing+line_height) * row) - (top_offset + ml);

                Simp.draw_prepared_text(my_font, xx (ml-left_offset), xx bottom, text_color /*.{.8, .8, .8, 1}*/);

                if i != -1 {
                    row += 1; advance(*t, i+1);
                }
            }
        }

        // Draw debug info
        if show_debug_info {
            row := 1;
            for debug_infos {
                s := it;
                ln := s[s.count-1] == #char "\n";
                if ln then s.count -= 1;

                w := Simp.prepare_text(my_font, s);
                top := ((my_font.default_line_spacing+line_height) * row);
                Simp.draw_prepared_text(my_font, xx (window_width - w*1.1), xx (window_height-top), .{.8, .8, .8, 1});

                if ln then row += 1;

                free(it.data);
            }

            array_reset(*debug_infos);
        }

        Simp.swap_buffers(window);

        // sleep_milliseconds(20);
        reset_temporary_storage();
    }
    
}

PrintDev :: (fmt: string, args: .. Any) #expand {
    s := sprint(fmt, ..args); // Switch to tprint @Todo
    array_add(*debug_infos, s);  // can we use temporary allocator for dynamic arrays?
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

get_cursor_rel_y :: inline (text: string) -> s64 {
    row := get_cursor_row(text);
    top := window_height - (((my_font.default_line_spacing+line_height) * row) + (top_offset + ml));
    return xx top;
}

get_cursor_y :: (text: string) -> s64 {
    if cursor_pos == 0 return window_height;

    row := get_cursor_row(text);
    top := (my_font.default_line_spacing + line_height) * row;
    return window_height - xx top;
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
    pixel_height := font_size; // print(">>> %\n", window_height/40);

    my_font = Simp.get_font_at_size("data", "firacode-retina/FiraCode-Retina.ttf", pixel_height);
    // print("%\n\n", my_font);
    assert(my_font != null);
}

current_font_width :: () -> s64 {
    assert(my_font != null);
    return my_font.em_width;
}

#import "System";
#import "Basic";
#import "File";
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