text_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, placeholder := "", theme := Text_Input.DEFAULT_THEME) -> *Text_Input {    

    timer := seconds_since_init();
    defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    input, found := table_find(*inputs, ui_id);
    if !found {
        input = New(Text_Input);
        input.text.data = *input.input_buffer[0];
        table_add(*inputs, ui_id, input);
    }

    using input;

    typed = false;
    
    for event: events_to_handle_this_frame {
        if event.type == .TEXT_INPUT {
            #if OS == .WINDOWS if event.utf32 == 0x7F continue;

            utf8_text := character_utf32_to_utf8(event.utf32);
            defer free(utf8_text);

            insert_text(input, utf8_text);
            
            typed = true;

        } else if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_LEFT;   move_cursor_left(input, event.shift_pressed, event.ctrl_pressed);
                    case ARROW_RIGHT;  move_cursor_right(input, event.shift_pressed, event.ctrl_pressed);
                    case BACKSPACE;    backspace_from_cursor(input, event.ctrl_pressed);
                }
            }
        }
    }

    left_pad := 5.0;
    pad := 0.0;
    ch  := font.character_height;
    b   := r.y - pad - r.h*1.5;
    t   := r.y - pad;

    Simp.set_shader_for_color(true);
    Simp.immediate_quad(r.x, b, r.x + r.w, t, theme.bg_color);

    if text {
        Simp.prepare_text(font, text);
        center := t - (r.h*1.5*0.5) - ch*.3;
        Simp.draw_prepared_text(font, xx (r.x + left_pad), xx center, theme.fg_color);
    } else if placeholder {
        left   := r.x + left_pad * 2;
        bottom := t - (r.h*1.5*0.5) - ch*.3; // center
        label(xx left, xx bottom, placeholder, font, theme.placeholder_color);
    }

    {
        left := r.x + 5.0;
        if cursor.pos && text {
            t := text;
            t.count = cursor.pos;
            left += measure_text_width(font, t);
        }
        rect := get_rect(left, b + ch * .25, em(.25, font), xx ch);
        draw_cursor(rect, bg_color=theme.cursor_color, fg_color=DEFAULT_COLOR[Color.TEXT_UNDER_CURSOR]);
    }

    return input;
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

    return true;
}

clear_text :: (using i: *Text_Input) {
    text.count = 0;
}

handle_text_input_event :: (event: Event) {
    array_add(*events_to_handle_this_frame, event);
}

clear_text_input_events :: () {
    array_reset_keeping_memory(*events_to_handle_this_frame);
}

#scope_file

clamp_cursor_pos :: (using i: *Text_Input) {
    Clamp(*cursor.pos, 0, text.count);
}

move_cursor_left :: (using i: *Text_Input, shift_pressed := false, ctrl_pressed := false) {
    if !text || !cursor.pos return;

    at := seek_left_one_utf8_character_byte_pos(text, cursor.pos);
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

    cursor.pos = at;
}

move_cursor_right :: (using i: *Text_Input, shift_pressed := false, ctrl_pressed := false) {
    if !text || cursor.pos == text.count return;

    at := seek_right_one_utf8_character_byte_pos(text, cursor.pos);
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

    cursor.pos = at;
}

backspace_from_cursor :: (using i: *Text_Input, ctrl_pressed := false) {
    if !text || !cursor.pos return;

    from := cursor.pos;
    move_cursor_left(i, ctrl_pressed=ctrl_pressed);
    to := cursor.pos;
    if from == to return;

    assert(to < from);

    dest   := text.data  + to;
    source := text.data  + from;
    size   := text.count - from;

    c_memmove(dest, source, xx size);
    text.count -= (from - to);
}

events_to_handle_this_frame: [..] Event;

inputs: Table(u64, *Text_Input);

#scope_export

Text_Input :: struct {
    text: string;
    cursor: Cursor;

    typed := false;

    MAX_BUFFER_SIZE :: 8000;
    input_buffer: [MAX_BUFFER_SIZE] u8;

    DEFAULT_THEME :: Theme.{
        fg_color          = #run hex_to_vec4(0x000000ff),
        bg_color          = #run hex_to_vec4(0xa397a3ff),
        placeholder_color = Vector4.{0,0,0,.5},
        cursor_color      = #run hex_to_vec4(0x47253aff),
    };
    
    Theme :: struct {
        fg_color:          Vector4;
        bg_color:          Vector4;
        placeholder_color: Vector4;
        cursor_color:      Vector4;
    }
}
