find_occurences :: (_text: string) {
    using find_text_dialog;

    array_reset_keeping_memory(*occurences);
    current_occurance = -1;
    if !_text return;

    _, buffer := get_active_editor_and_buffer();

    s := to_string(buffer);
    at := 0;
    while true {
        i := find_index_from_left_nocase(s, _text, at);
        if i == -1 {
            break;
        }
        at = i + _text.count;

        array_add(*occurences, i);
    }
}

next_occurance :: ($roundtrip: bool) {
    using find_text_dialog;

    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if occurences.count == 0 return;
    #if !roundtrip {
        if current_occurance == occurences.count-1 return;
    }

    // Jump to the first occurance after the current cursor position
    if current_occurance == -1 {
        cursor_pos := editor.cursor.pos;
        for pos, index: occurences {
            // Use less-than instead of less-than-or-equal,  
            // because with that, we get stuck on the current occurrence based on the cursor position.  
            // This would require an extra keypress to move to the next match,  
            // which we want to avoid.
            if cursor_pos < pos {
                current_occurance = index;
                set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
                return;
            }
        }
    }

    Clamp(*current_occurance, 0, occurences.count-1);
    current_occurance = (current_occurance + 1) % occurences.count;

    pos := occurences[current_occurance];

    set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
}

previous_occurance :: () {
    using find_text_dialog;

    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if occurences.count == 0 || current_occurance == 0 return;

    // Jump to the first occurance before the current cursor position
    if current_occurance == -1 {
        cursor_pos := editor.cursor.pos;
        for pos, index: occurences {
            if cursor_pos <= pos {
                if index != 0 {
                    index -= 1;
                    pos = occurences[index];
                }

                current_occurance = index;
                set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
                return;
            }
        }
    }

    current_occurance -= 1;

    pos := occurences[current_occurance];

    set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
}

open_find_text_dialog :: () {
    using find_text_dialog;
    
    if !input then input = create_text_input(cast(u64, #location()));
    if input.text then select_all(input);

    switch_editor_mode(.WIDGET);
    active_widget = Find_Text_Dialog;
}

update_find_text_dialog :: () {
    using find_text_dialog;

    if input.typed {
        if input.text {
            find_occurences(input.text);
        } else {
            array_reset_keeping_memory(*occurences);
        }
    }

    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_UP;   previous_occurance();
                    case ARROW_DOWN; next_occurance(roundtrip=false);
                    case ENTER;      next_occurance(roundtrip=true);
                }
            }
        }
    }

}

find_text_dialog: Find_Text_Dialog;

Find_Text_Dialog :: struct {
    input: *Text_Input;

    occurences: [..] s64;
    current_occurance: s64 = -1;
}