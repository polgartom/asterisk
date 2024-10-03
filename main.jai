window_width := 1280;
window_height := 720;

should_quit := false;

// background_color : Vector4 = .{.0, .155, .125, 1};
my_font: *Simp.Dynamic_Font;

cursor_pos := 0;
cursor_moved := false;

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

// ml :: 5.0; // margin left
line_height :: 0.0;//5.0; // what is this metric, px?
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
    
    // sample := read_entire_file("TODO");
    // sample := read_entire_file("sample.txt");

    sample := read_entire_file("main.jai");
    append(*builder, sample);
    should_rebuild_row_table = true;

    last_time = seconds_since_init();
    last_second_time: float64 = 0.0;
    second_elapsed := false;

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

                    // Dev hotkeys (for now)
                    if event.key_code == .F1 {
                        show_debug_info = !show_debug_info;
                    }
                    if event.key_code == .F2 {
                        draw_special_chars = !draw_special_chars;
                    }
                    if event.key_code == .F3 {
                        draw_row_table = !draw_row_table;
                    }

                    if key == .ARROW_LEFT   key_left  = event.key_pressed;
                    if key == .ARROW_RIGHT  key_right = event.key_pressed;
                    if key == .ARROW_DOWN   key_down  = event.key_pressed;
                    if key == .ARROW_UP     key_up    = event.key_pressed;

                    if key == .BACKSPACE {
                        key_backspace = event.key_pressed;

                        // Delete from right
                        if cursor_pos-1 > -1 {
                            text := builder_to_string(*builder, do_reset = true);
                            defer free(text);

                            r := 1;

                            // Check if we would delete a tab
                            ch := text.data[cursor_pos-1];
                            if ch == #char " " {
                                i := 0;
                                spaces := 1;
                                for < cursor_pos-1..0 {
                                    // print("ch: |%|\n", get_char_at_string_index(text, it));
                                    if text.data[it] == #char " " {
                                        spaces += 1;
                                        if spaces == TAB_SIZE_IN_SPACES {
                                            r = TAB_SIZE_IN_SPACES;
                                            break;
                                        }
                                    } else {
                                        break;
                                    }
                                }
                            }

                            // print("r: %\n", r);
                            i := cursor_pos - r;
                            if i > -1 {
                                append(*builder, text.data, i); // @Todo replace with append_text()
                                t := advance(text, cursor_pos);
                                append(*builder, t);
                                set_cursor_pos(cursor_pos-r);
                                should_rebuild_row_table = true;
                            }

                        }
                    }

                    if key == .ENTER {
                        text := builder_to_string(*builder, do_reset = false);
                        defer free(text);

                        if cursor_pos-1 > -1 {
                            // A basic smart indent count characters in the current row until the first non-space character.

                            start := cursor_pos-1;
                            index := -1;
                            for < start..0 {
                                if text.data[it] == #char "\n" {
                                    index = it;
                                    break;
                                }
                            }

                            if index+1 < text.count {
                                index += 1;
                                index2 := find_index_from_left_until_not(text, #char " ", index);
                                spaces := index2 - index;
                                // print("spaces: % ; index-1: %\n", spaces, index-1);
                                
                                if cursor_pos >= index && cursor_pos < index2 {
                                    // We're in the first n empty space range
                                    set_cursor_pos(index2); // jump to the first non-whitespace char in the row
                                }

                                append_text(*builder, "\n");

                                while spaces != 0 {
                                    append_text(*builder, " ");
                                    spaces -= 1;
                                }
                            } else {
                                append_text(*builder, "\n");
                            }


                        } else {
                            append_text(*builder, "\n");
                        }
                    }

                    if key == .TAB {
                        // @Todo: convert < TAB_SIZE_IN_SPACES spaces to tab

                        // text := builder_to_string(*builder, do_reset = false);
                        // defer free(text);

                        // if cursor_pos != text.count {
                        //     ch := text.data[cursor_pos];
                        //     // ok, sc := surround_chars(text, cursor_pos);
                        //     // if ok print("surround_chars: |%|\n", sc);
                        //     // else print("failed to get the surround_chars!\n");
                        // }

                        append_text(*builder, TAB_SPACE_CHARS);
                    }

                }

            }
        }

        text := builder_to_string(*builder, do_reset = false);
        defer free(text);

        if should_rebuild_row_table {
            rebuild_row_table(text);

            // if draw_row_table {
            //     print("\n----------------\nrow_table | rows: %\n", row_table.count);
            //     for row_table {
            //         print("#% | pos: % cols: %\n", it_index, it.pos, it.cols);
            //     }
            // }
        }

        // Handle cursor movement
        if key_left && cursor_pos != 0 {
            increase_cursor_pos(-1);
        }

        if key_right && cursor_pos < text.count {
            increase_cursor_pos(1);
        }

        if key_up {
            assert(row_table.count != 0);
            for row_table {
                if cursor_pos <= it.pos {
                    if it_index == 0 break; // no more row above
                    prev_row_index := it_index-1;
                    prev_row := row_table[prev_row_index];
                    assert(prev_row.cols != 0);

                    current_col := cursor_pos - first_row_col(it);
                    set_cursor_pos(first_row_col(prev_row) + min(prev_row.cols, current_col));
                    break;
                }
            }
        }

        if key_down {
            cursor_col := get_cursor_col(text);
            i := find_index_from_left(text, #char "\n", start_index=cursor_pos);
            if i != -1 {
                new_pos := i+1;
                col := 0;
                for i+1..text.count-1 {
                    if col == cursor_col || text.data[it] == #char "\n" {
                        break;
                    }
                    col += 1;
                }
                new_pos += col;

                set_cursor_pos(new_pos);
            }
        }

        if cursor_moved {
            rel_x := get_cursor_rel_x(text);
            if rel_x - window_width >= 0 {
                left_offset += rel_x - window_width;
            } else if rel_x - my_font.em_width < 0 {
                left_offset -= (rel_x * -1) + my_font.em_width;
            }

            rel_y := get_cursor_rel_y(text);            
            if rel_y < 0 {
                top_offset += abs(rel_y);
            } else if rel_y + my_font.character_height > window_height {
                top_offset -= rel_y + my_font.character_height - window_height;
            }
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

        if show_debug_info {
            PrintDev("F1 toggle dev | F2 show tabs\n");
            PrintDev("w: % ; h: % ; t: % ; l: %\n", window_width, window_height, top_offset, left_offset);
            PrintDev("cp: % abs: % % rel: % %\n", cursor_pos, get_cursor_x(text), get_cursor_y(text), get_cursor_rel_x(text), get_cursor_rel_y(text));

            // PrintDev("rows: %\n", row_table.count);
            // for row_table {
            //     PrintDev("r: % ; s: % ; e: % ; c: %\n", it_index, it.pos-it.cols, it.pos, it.cols);
            // }

            // Row
            // PrintDev("---------------\n");
            // new_row := 0;
            // new_col := 0;
            // for row_table {
            //     if cursor_pos <= it.pos {
            //         PrintDev("!FOUND! -> rt.pos: % ; rt.row: % ; rt.cols: %\n", it.pos, it_index, it.cols);
            //         new_row = it_index;
            //         new_col = it.cols - (it.pos-cursor_pos);
            //         break;
            //     }
            //     PrintDev("skip -> rt.pos: % ; rt.row: % ; rt.cols: %\n", it.pos, it_index, it.cols);
            // }
            // PrintDev("---------------\n");
            // PrintDev(
            //     "col: % % | row: % % | (rowtable: %ms) | chars: %\n", 
            //     get_cursor_col(text),
            //     new_col,
            //     get_cursor_row(text)-1, 
            //     new_row, 
            //     formatFloat(row_table_recalc_time, trailing_width=2),
            //     text.count
            // );

        }        

        /////////////////////
        /// Draw frame

        // Draw cursor
        {
            row := get_cursor_row(text);
            col := get_cursor_col(text);
            cx  := get_cursor_x(text);
            PrintDev("row: % ; col: % ; cx: %\n", row, col, cx);

            Simp.set_shader_for_color();

            top  := window_height - ((my_font.default_line_spacing+line_height) * row) + top_offset;
            left := cx - left_offset;
            h := my_font.character_height;

            Simp.immediate_quad(left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)), cursor_color);

            // ch := get_char_at_string_index(text, cursor_pos);
            // PrintDev("cursor | i: % % ; x1: % y1: % x2: % y2: %\n", cursor_pos, ch, left, top + (h-h*0.1), left + my_font.em_width, top - (h/2-(h*0.2)));
        }

        // Draw lines
        if text.count {
            rendered_rows := 0;

            for row_table {
                if it.cols == 0 continue;
                row := it_index+1;
                l := get_line_height();
                bottom := window_height - (l*row) + top_offset;
                if bottom < 0 break;
                if xx (bottom) > window_height continue;

                left := -left_offset;
                t := slice(text, it.pos-it.cols, it.cols);
                left += draw_text(t, xx left, xx bottom, text_color);

                if draw_special_chars {
                    s := tprint("¶");
                    draw_text(s, xx left, xx bottom, .{1.0, 1.0, 1.0, .8});
                }

                rendered_rows += 1;
            }

            PrintDev("rendered rows/total: %/%\n", rendered_rows, row_table.count);
        }

        // Draw debug info
        if show_debug_info {

            {
                ct := seconds_since_init();
                if second_elapsed {
                    frametime = (ct - last_time) * 1000; // frametime
                    fps       = 1000/frametime;
                }

                PrintDev("%fps %ms %sec\n", 
                    formatFloat(fps, trailing_width=0), 
                    formatFloat(frametime, trailing_width=2), 
                    formatFloat(last_time, trailing_width=0)
                );
            }

            row := 1;
            max := 0;
            for debug_infos if it.count > max then max = it.count;
            for debug_infos {
                s := it;
                ln := s[s.count-1] == #char "\n";
                if ln then s.count -= 1;

                // roffset := max - it.count;
                rmargin := 10;

                w := Simp.prepare_text(my_font, s);
                top := ((my_font.default_line_spacing+line_height) * row);
                Simp.draw_prepared_text(my_font, xx (window_width - w - rmargin), xx (window_height-top), .{.8, .8, .8, 1});

                if ln then row += 1;

                free(it.data);
            }

            array_reset(*debug_infos);
        }

        Simp.swap_buffers(window);

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

get_cursor_row :: (text: string) -> s64 {
    if cursor_pos == 0 return 1; // @Ambiguity: use start at 0 just like we do in get_cursor_col()

    assert(row_table.count != 0);
    for row_table {
        if cursor_pos <= it.pos {
            return it_index+1;
        }
    }

    return row_table.count; // @Investigate: we will get here if we on the last char
}

get_cursor_col :: (text: string) -> s64 {
    for row_table {
        // print("> cp: % ; r: % %\n", cursor_pos, it.pos, it.cols);
        if cursor_pos <= it.pos {
            return it.cols - (it.pos - cursor_pos);
        }
    }

    return 0; // @Investigate: we will get here if we on the last char
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

set_cursor_pos :: inline (index: s64) {
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
    assert(start_index < s.count);

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

rebuild_row_table :: (s: string) {
    should_rebuild_row_table = false;
    
    row_table_recalc_time = seconds_since_init()*1000 - row_table_recalc_time;
    defer { row_table_recalc_time = seconds_since_init()*1000; };

    array_reset(*row_table); // we should not do free, we can reuse the same memory

    pos := 0;
    while true {
        ln_index := find_index_from_left(s, #char "\n");
        if ln_index == -1 {
            array_add(*row_table, .{pos=pos+s.count, cols=s.count});
            break;
        }

        pos += ln_index;
        array_add(*row_table, .{pos=pos, cols=ln_index});

        ln_index += 1;
        advance(*s, ln_index);

        pos += 1;
    }
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

// get_first_row_col :: inline (s: string, row_index: s64) {
//     assert(row_index < row_table.count && row_index > -1);

//     row := row_table[row_index];
//     end := start+row.cols;
//     assert(end <= s.count, "end: % ; s.count: %\n", end, s.count);
//     return end;
// }

first_row_col :: inline (row: Row_Info) -> s64 {
    return row.pos - row.cols;
}

draw_text :: inline (s: string, left: s64, bottom: s64, color: Vector4) -> s64 {
    w := Simp.prepare_text(my_font, s);
    Simp.draw_prepared_text(my_font, left, bottom, color);
    return w;
}

get_line_height :: inline (row: s64 = 1) -> float32 {
    return (my_font.default_line_spacing+line_height)*row;
}

row_table_recalc_time: float64 = 0.0;
draw_row_table := false;
should_rebuild_row_table := false;
row_table: [..] Row_Info;

Row_Info :: struct {
    pos:  s64; // row end index
    cols: s64;
}

#if OS == .WINDOWS {
    user32 :: #system_library "user32";
    WaitMessage :: () -> s32 #foreign user32;
}

#import "System";
#import "Basic";
#import "File";
#import "String";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Keymap";
#import "Unicode";
Simp    :: #import "Simp";