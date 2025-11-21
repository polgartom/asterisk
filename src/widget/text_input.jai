text_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, placeholder := "", theme := Text_Input.DEFAULT_THEME, prefix := "") -> *Text_Input {
    // timer := seconds_since_init();
    // defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    found, input := table_find(*inputs, ui_id);
    if !found {
        input = create_text_input(ui_id);
    }

    update_text_input(input, r, font, placeholder, theme, prefix);

    return input;
}

create_text_input :: (ui_id: u64) -> *Text_Input {
    input := New(Text_Input);
    input.text.data = *input.input_buffer[0];
    table_add(*inputs, ui_id, input);

    return input;
}

update_text_input :: (using input: *Text_Input, rect: Rect, font: *Simp.Dynamic_Font, placeholder := "", theme := Text_Input.DEFAULT_THEME, prefix := "") {
    
    typed = false;

    for event: events_to_handle_this_frame_for_widgets {
        // ll("> %\n", event);

        if event.type == .TEXT_INPUT {
            #if OS == .WINDOWS if event.utf32 == 0x7F continue;

            utf8_text := character_utf32_to_utf8(event.utf32);
            defer free(utf8_text);

            delete_selected_text(input);

            insert_text(input, utf8_text);
            
            typed = true;

        } else if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                // @Temporary @Todo Temporary hotfix for altGr+something keycombos.
                // This is how the input events come if we press altGr+v:
                // [update_text_input] > {
                //   type = KEYBOARD;
                //   key_pressed = 1;
                //   key_code = CTRL;
                //   modifier_flags = (union);
                //   utf32 = 0;
                //   repeat = false;
                //   text_input_count = 0;
                //   typical_wheel_delta = 0;
                //   wheel_delta = 0;
                //   files = [];
                //   touch_type = MOVED;
                //   touch_index = 0;
                // }
                // [update_text_input] > {
                //   type = KEYBOARD;
                //   key_pressed = 1;
                //   key_code = ALT;
                //   modifier_flags = (union);
                //   utf32 = 0;
                //   repeat = false;
                //   text_input_count = 0;
                //   typical_wheel_delta = 0;
                //   wheel_delta = 0;
                //   files = [];
                //   touch_type = MOVED;
                //   touch_index = 0;
                // }
                // [update_text_input] > {
                //   type = KEYBOARD;
                //   key_pressed = 1;
                //   key_code = (enum out of range: 86);
                //   modifier_flags = (union);
                //   utf32 = 0;
                //   repeat = false;
                //   text_input_count = 0;
                //   typical_wheel_delta = 0;
                //   wheel_delta = 0;
                //   files = [];
                //   touch_type = MOVED;
                //   touch_index = 0;
                // }
                // [update_text_input] > {
                //   type = TEXT_INPUT;
                //   key_pressed = 0;
                //   key_code = UNKNOWN;
                //   modifier_flags = (union);
                //   utf32 = 64;
                //   repeat = false;
                //   text_input_count = 0;
                //   typical_wheel_delta = 0;
                //   wheel_delta = 0;
                //   files = [];
                //   touch_type = MOVED;
                //   touch_index = 0;
                // }                
                if event.ctrl_pressed && event.alt_pressed {
                    continue;
                }

                if key == {
                    case 65 /* a */; if (event.ctrl_pressed) select_all(input);
                    case 67 /* c */; if (event.ctrl_pressed) copy_to_os_clipboard(input);
                    case 86 /* v */; if (event.ctrl_pressed) { insert_os_clipboard_text(input); typed = true; }

                    case HOME; {
                        if event.alt_pressed {
                            move_cursor_to_end(input, event.shift_pressed);
                        } else {
                            move_cursor_to_start(input, event.shift_pressed);
                        }
                    }
                    case END;          move_cursor_to_end(input, event.shift_pressed);
                    case ARROW_LEFT;   move_cursor_left(input, event.shift_pressed, event.ctrl_pressed);
                    case ARROW_RIGHT;  move_cursor_right(input, event.shift_pressed, event.ctrl_pressed);
                    case BACKSPACE;    { backspace_from_cursor(input, event.ctrl_pressed); typed = true; };
                }
            }
        }
    }

    get_cursor_x :: (pos: s64) -> s64 #expand {
        t := `text;
        t.count = cursor.pos;
        return measure_text_width(`font, t);
    }

    draw_quad_with_radius(expand(rect, 2.0), theme.border_color, r_rect_radius);
    draw_quad_with_radius(rect, theme.bg_color, r_rect_radius);
    
    text_rect := shrink_x(rect, 5.0);
    push_scissor(text_rect);
    defer pop_scissor();
    
    left := text_rect.x;
    text_x := text_rect.x - left_offset;
    text_y := text_rect.y + default_text_baseline(font, text_rect.h);
    p1, p2 := get_y_range(font, text_y);
    cursor_width := max(em(0.25, font), 3.0);
    
    if arrange_offset_this_frame {
        x_threshold := cursor_width;
        cursor_x := get_cursor_x(cursor.pos) - left_offset - text_rect.w;
    
        target := left_offset;
        if cursor_x + x_threshold > 0 {
            target += abs(cursor_x + x_threshold);
        } else if abs(cursor_x - x_threshold) > xx text_rect.w {
            target -= abs(cursor_x - x_threshold) - text_rect.w;
            if target < 0 then target = 0;
        }
        
        left_offset = target;
    }
    
    arrange_offset_this_frame = true;
    
    {
        // Draw selection
        
        start, end := selected_range(*cursor);
        if start != end {
            start_x := cast(float)measure_text_width(font, slice(text, 0, start));
            start_x = text_rect.x + start_x - left_offset;
            width   := cast(float)measure_text_width(font, slice(text, start, end - start));
            
            Simp.set_shader_for_rect();
            Simp.immediate_quad_with_radius(start_x, p1, start_x + width, p2, map_color_to_vec4(.TEXT_SELECTION), radius=4.0);
        }
    }
    
    if text {
        draw_text(xx text_x, xx text_y, text, font, theme.fg_color);
    } else if placeholder {
        draw_text(xx text_x, xx text_y, placeholder, font, theme.placeholder_color);
    }
    
    {
        // Draw cursor
        
        Simp.set_shader_for_color(true);
        
        x := text_rect.x + get_cursor_x(cursor.pos) - left_offset;
        Simp.immediate_quad(x, p1, xx (x + cursor_width), p2, theme.cursor_color);
    }
}

insert_text :: (using input: *Text_Input, s: string) -> bool {
    if !s || text.count + s.count > input_buffer.count return false;

    clamp_cursor_pos(input);

    at             := cursor.pos;
    insert_at      := text.data  + at;
    new_right      := insert_at  + s.count;
    right_rem_size := text.count - (insert_at - text.data);

    if right_rem_size then c_memmove(new_right, insert_at, xx right_rem_size);
    memcpy(insert_at, s.data, s.count);

    text.count += s.count;
    cursor.pos += s.count;
    cursor.sel += s.count;
    
    return true;
}

insert_os_clipboard_text :: (using i: *Text_Input) {
    delete_selected_text(i);

    clipboard_text := Clipboard.os_clipboard_get_text();
    defer free(clipboard_text);

    insert_text(i, clipboard_text);
}

copy_to_os_clipboard :: (using i: *Text_Input) {
    if !has_selection(i.cursor) return;

    s := get_selected_text(i);
    Clipboard.os_clipboard_set_text(s);
}

get_selected_text :: (using i: *Text_Input) -> string {
    start, end := selected_range(*cursor);
    return slice(text, start, end - start);
}

clear_text :: (using i: *Text_Input) {
    text.count = 0;
    cursor.pos = 0;
    cursor.sel = 0;
    left_offset = 0;
}

move_cursor_left :: (using i: *Text_Input, shift_pressed := false, ctrl_pressed := false) {
    if !text return;

    at := cursor.pos;

    if cursor.pos > 0 {
        at = seek_left_one_utf8_character_byte_pos(text, at);
        if (ctrl_pressed) {
            if is_separator(text[at]) {
                while at {
                    point := seek_left_one_utf8_character_byte_pos(text, at);
                    if is_alphanum(text[point]) break;
                    at = point;
                }
            } else {
                while at {
                    point := seek_left_one_utf8_character_byte_pos(text, at);
                    if !is_alphanum(text[point]) break;
                    at = point;
                }
            }
        }
    }


    cursor.pos = at;
    if !shift_pressed {
        cursor.sel = at;
    }
}

move_cursor_right :: (using i: *Text_Input, shift_pressed := false, ctrl_pressed := false) {
    if !text return;

    at := cursor.pos;

    if at < text.count {
        at = seek_right_one_utf8_character_byte_pos(text, at);
        if (ctrl_pressed && at != text.count) {
            if is_separator(text[at]) {
                while at {
                    at = seek_right_one_utf8_character_byte_pos(text, at);
                    if at == text.count || is_alphanum(text[at]) break;
                }
            } else {
                while at {
                    at = seek_right_one_utf8_character_byte_pos(text, at);
                    if at == text.count || !is_alphanum(text[at]) break;
                }
            }
        }
    }

    cursor.pos = at;
    if !shift_pressed {
        cursor.sel = at;
    }
}

move_cursor_to_start :: (using i: *Text_Input, shift_pressed := false) {
    cursor.pos = 0;
    if !shift_pressed {
        cursor.sel = 0;
    }
}

move_cursor_to_end :: (using i: *Text_Input, shift_pressed := false) {
    cursor.pos = text.count;
    if !shift_pressed {
        cursor.sel = text.count;
    }
}

backspace_from_cursor :: (using i: *Text_Input, ctrl_pressed := false) {
    if !text return;

    if !has_selection(cursor) {
        // Do a selection "virtually"
        move_cursor_left(i, shift_pressed=true, ctrl_pressed=ctrl_pressed);
    }

    to, from := selected_range(*cursor);
    if from == to return;
    assert(to < from);

    defer {
        cursor.pos = to;
        cursor.sel = to;
    }

    dest   := text.data  + to;
    source := text.data  + from;
    size   := text.count - from;

    c_memmove(dest, source, xx size);
    text.count -= (from - to);
}

delete_selected_text :: (using i: *Text_Input) {
    if !has_selection(i.cursor) return;

    backspace_from_cursor(i);
}

select_all :: (using i: *Text_Input) {
    cursor.pos = i.text.count;
    cursor.sel = 0;
}

#scope_file

clamp_cursor_pos :: (using i: *Text_Input) {
    Clamp(*cursor.pos, 0, text.count);
    Clamp(*cursor.sel, 0, text.count);
}

inputs: Table(u64, *Text_Input);

#scope_export

Text_Input :: struct {
    text: string;
    cursor: Cursor;

    typed := false;
    
    left_offset := 0.0;
    arrange_offset_this_frame := false;

    // @Todo: Handle buffer overflows
    MAX_BUFFER_SIZE :: 8000;
    input_buffer: [MAX_BUFFER_SIZE] u8;

    DEFAULT_THEME :: Theme.{
        fg_color          = #run hex_to_vec4(0x000000ff),
        bg_color          = #run hex_to_vec4(0xa397a3ff),
        placeholder_color = Vector4.{0,0,0,.5},
        cursor_color      = #run hex_to_vec4(0x47253aff),
        selection_color   = #run hex_to_vec4(0xff_ff_ff_21),
        border_color      = #run hex_to_vec4(0x101953_ff),
    };
    
    Theme :: struct {
        fg_color:          Vector4;
        bg_color:          Vector4;
        placeholder_color: Vector4;
        cursor_color:      Vector4;
        selection_color:   Vector4;
        border_color:      Vector4;
    }
}
