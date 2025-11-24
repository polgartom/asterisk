open_find_text_dialog :: () {
    using find_text_dialog;
    
    if !input then input = create_text_input(FIND_TEXT_DIALOG_UI_ID);
    
    if input.text {
        select_all(input);

        // The occurrences locations may changed since we last opened this dialog, so we need to find the new position of them.
        find_occurrences(input.text);
    }

    switch_editor_mode(.WIDGET);
    active_widget = Find_Text_Dialog;
}

find_occurrences :: (_text: string) {
    using find_text_dialog;

    array_reset_keeping_memory(*occurrences);
    current_occurrence = -1;
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

        array_add(*occurrences, i);
    }
}

next_occurrence :: () {
    using find_text_dialog;

    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if occurrences.count == 0 return;
    
    // Jump to the first occurrence after the current cursor position
    if current_occurrence == -1 {
        cursor_pos := editor.cursor.pos;
        for pos, index: occurrences {
            // Use less-than instead of less-than-or-equal,  
            // because with that, we get stuck on the current occurrence based on the cursor position.  
            // This would require an extra keypress to move to the next match,  
            // which we want to avoid.
            if cursor_pos < pos {
                current_occurrence = index;
                set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
                return;
            }
        }
    }

    Clamp(*current_occurrence, 0, occurrences.count-1);
    current_occurrence = (current_occurrence + 1) % occurrences.count;

    pos := occurrences[current_occurrence];

    set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
}

previous_occurrence :: () {
    using find_text_dialog;

    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    if occurrences.count == 0 || current_occurrence == 0 return;

    // Jump to the first occurrence before the current cursor position
    if current_occurrence == -1 {
        cursor_pos := editor.cursor.pos;
        for pos, index: occurrences {
            if pos >= editor.cursor.pos {
                break;
            }

            current_occurrence = index;
        }
    } else {
        current_occurrence -= 1;
    }

    Clamp(*current_occurrence, 0, occurrences.count);

    pos := occurrences[current_occurrence];
    set_cursor_pos(buffer, *editor.cursor, pos, horizontal=true, with_selection=true);
}

update_find_text_dialog :: () {
    using find_text_dialog;

    if input.typed {
        if input.text {
            find_occurrences(input.text);
        } else {
            array_reset_keeping_memory(*occurrences);
        }
    }

    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ARROW_UP;   previous_occurrence();
                    case ARROW_DOWN; next_occurrence();
                    case ENTER;      next_occurrence();
                }
            }
        }
    }

}

FIND_TEXT_DIALOG_UI_ID :: cast(Ui_Id) #location();

find_text_dialog: Find_Text_Dialog;

Find_Text_Dialog :: struct {
    input: *Text_Input;

    occurrences: [..] s64;
    current_occurrence: s64 = -1;
}