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

next_occurance :: () {
    using find_text_dialog;

    _, buffer := get_active_editor_and_buffer();
    using buffer;

    if occurences.count == 0 return;

    if current_occurance != -1 {
        current_occurance += 1;
        if current_occurance == occurences.count then current_occurance = 0;        
    } else {
        for occurences {
            if _cursor.pos <= it {
                current_occurance = it_index;
                break;
            }
        }

        if current_occurance == -1 {
            current_occurance = 0;
        }
    }

    pos := occurences[current_occurance];

    assert(pos != -1, "occurences: % ; current: %\n", occurences, current_occurance);

    set_cursor_pos(buffer, *buffer._cursor, pos, horizontal=true, with_selection=true);
}

open_find_text_dialog :: () {
    using find_text_dialog;
    
    if !input then input = create_text_input(cast(u64, #location()));
    clear_text(input);

    switch_editor_mode(.WIDGET);
    active_widget = Find_Text_Dialog;
}

update_find_text_dialog :: () {
    using find_text_dialog;

    if input.typed && input.text {
        find_occurences(input.text);
    }

    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ENTER; next_occurance();
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