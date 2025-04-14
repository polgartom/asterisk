//
// @Todo: Handle overflowing text by scrolling when moving the cursor left or right
//

text_input :: (r: Rect, ui_id: u64, font: *Simp.Dynamic_Font, placeholder := "", theme := Text_Input.DEFAULT_THEME, prefix := "") -> *Text_Input {
    // timer := seconds_since_init();
    // defer PrintDev("[%] %ms\n", #procedure_name(), formatFloat((seconds_since_init()-timer)*1000, trailing_width=4));
    
    input, found := table_find(*inputs, ui_id);
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

update_text_input :: (using input: *Text_Input, r: Rect, font: *Simp.Dynamic_Font, placeholder := "", theme := Text_Input.DEFAULT_THEME, prefix := "") {
    typed = false;

    for event: events_to_handle_this_frame_for_widgets {
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
                // ll("> %\n", key);
                if key == {
                    case 65 /* a */;   if (event.ctrl_pressed) select_all(input);
                    case 67 /* c */;   if (event.ctrl_pressed) copy_to_os_clipboard(input);
                    case 86 /* v */;   if (event.ctrl_pressed) { insert_os_clipboard_text(input); typed = true; }

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

    left_pad := 5.0;
    ch  := font.character_height;
    b   := r.y;
    t   := r.y + r.h;

    Simp.set_shader_for_color(true);
    
    weight :: 2; // border weight
    Simp.immediate_quad(r.x-weight, b-weight, r.x + r.w + weight, t+weight, theme.border_color); // border
    Simp.immediate_quad(r.x, b, r.x + r.w, t, theme.bg_color); // input background

    left := r.x + left_pad;
    center := b + (t-b)*.5 - ch*.3; // With ch*.3 the text seems to be better aligned to center. 
    // center := b + (t-b)*.5 - ch*.25;
    
    // @Incomplete: Icon as prefix
    if prefix {
        left += label(xx left, xx center, prefix, font, theme.fg_color);
    }

    if text {
        label(xx left, xx center, text, font, theme.fg_color);

        if has_selection(cursor) {
            start, end := selected_range(*cursor);
            
            s := slice(text, 0, start);
            x := left + measure_text_width(font, s);
            
            s = advance(text, start);
            s.count = end - start;
            w := measure_text_width(font, s);

            Simp.set_shader_for_color(true);
            Simp.immediate_quad(x, b + (t-b)*.5 - ch*.7, x + w, t - (t-b)*.5 + ch*.7, theme.selection_color);
        }

    } else if placeholder {
        label(xx left, xx center, placeholder, font, theme.placeholder_color);
    }

    {
        // Draw cursor

        Simp.set_shader_for_color(true);

        left = left - left_pad + 5.0;
        if cursor.pos && text {
            t := text;
            t.count = cursor.pos;
            left += measure_text_width(font, t);
        }
        
        width  := em(.25, font);
        right  := left + width;
        bottom := b + (t-b)*.5 - ch*.5;
        top    := bottom + ch;
        Simp.immediate_quad(left, bottom, right, top, theme.cursor_color);
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

    // @Todo: Handle buffer overflows
    MAX_BUFFER_SIZE :: 8000;
    input_buffer: [MAX_BUFFER_SIZE] u8;

    DEFAULT_THEME :: Theme.{
        fg_color          = #run hex_to_vec4(0x000000ff),
        bg_color          = #run hex_to_vec4(0xa397a3ff),
        placeholder_color = Vector4.{0,0,0,.5},
        cursor_color      = #run hex_to_vec4(0x47253aff),
        selection_color   = #run map_color_to_vec4(.TEXT_SELECTION),
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
