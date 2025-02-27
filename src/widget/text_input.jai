text_input :: (r: Rect, ui_id: u64) -> *Text_Input {
    input, found := table_find(*inputs, ui_id);
    if !found {
        input = New(Text_Input);
        input.text.data = *input.input_buffer[0];
        table_add(*inputs, ui_id, input);
    }

    using input;

    for event: events_to_handle_this_frame {
        if event.type == .TEXT_INPUT {
            utf8_text := character_utf32_to_utf8(event.utf32);
            defer free(utf8_text);

            insert_text(input, utf8_text);
        } else if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_LEFT;   move_cursor_left(input, event.shift_pressed);
                    case ARROW_RIGHT;  move_cursor_right(input, event.shift_pressed);
                    case BACKSPACE;    backspace_from_cursor(input);
                }
            }
        }
    }

    // push_scissor(r);
    // defer pop_scissor();

    left_pad := 5.0;
    pad := 0.0;
    ch  := primary_font.character_height;
    b   := r.y - pad - r.h*1.5;
    t   := r.y - pad;

    Simp.set_shader_for_color(true);
    Simp.immediate_quad(r.x, b, r.x + r.w, t, #run hex_to_vec4(0xa397a3ff));

    if text {
        Simp.prepare_text(primary_font, text);
        center := t - (r.h*1.5*0.5) - ch*.3;
        Simp.draw_prepared_text(primary_font, xx (r.x + left_pad), xx center, .{.0,.0,.0,1.0});
    } else {
        left   := r.x + left_pad * 2;
        bottom := t - (r.h*1.5*0.5) - ch*.3; // center
        label(xx left, xx bottom, "Try to type something...", primary_font, .{.0,.0,.0,.5});
    }

    {
        left := r.x + 5.0;
        if cursor.pos && text {
            t := text;
            t.count = cursor.pos;
            left += measure_text_width(primary_font, t);
        }
        rect := get_rect(left, b + ch * .25, em(.25, primary_font), xx ch);
        draw_cursor(rect, Color.WIDGET_CURSOR);
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

move_cursor_left :: (using i: *Text_Input, shift_pressed := false) {
    if !text || cursor.pos == 0 return;

    cursor.pos = seek_left_one_utf8_character_byte_pos(text, cursor.pos);
    // pos := 0;
    // while pos < text.count {
    //     size := 1 + trailingBytesForUTF8[text[pos]];
    //     pos += size; 

    //     if pos == cursor.pos {
    //         assert(cursor.pos - size > -1);
    //         cursor.pos -= size;
    //         break;
    //     }
    // }
}

move_cursor_right :: (using i: *Text_Input, shift_pressed := false) {
    if !text || cursor.pos == text.count return;
    cursor.pos = seek_right_one_utf8_character_byte_pos(text, cursor.pos);
}

backspace_from_cursor :: (using i: *Text_Input) {
    if !text || !cursor.pos return;

    // if nonempty(selection) {
    //     replace_selection(state, "");
    //     pending_result_actions |= .TEXT_MODIFIED;
    // } else if (insert_point <= text.count) && (insert_point >= 1) {
    //     prev_point := seek_left_one_utf8_character(text, insert_point);
    //     nbytes := insert_point - prev_point;
    //     for i: prev_point..text.count-1-nbytes {
    //         text[i] = text[i+nbytes];
    //     }

    //     insert_point -= nbytes;
    //     text.count   -= nbytes;
    //     update_auto_complete(state);
    //     pending_result_actions |= .TEXT_MODIFIED;
    // }
}

events_to_handle_this_frame: [..] Event;

inputs: Table(u64, *Text_Input);

#scope_export

Text_Input :: struct {
    text: string;
    cursor: Cursor;

    MAX_BUFFER_SIZE :: 8000;
    input_buffer: [MAX_BUFFER_SIZE] u8;
}