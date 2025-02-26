reset_search_widget :: () {
    using find_text_dialog;

    if state && state.text {
        state.text.count = 0;
    }

    array_reset_keeping_memory(*occurences);
    current_occurance = -1;

    if text text.count = 0;
}

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

to_next_occurance :: () {
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

find_text_dialog_handle_event :: () {
    switch_editor_mode(.WIDGET);
    active_widget = Find_Text_Dialog;
}

find_text_dialog: Find_Text_Dialog;

Find_Text_Dialog :: struct {
    text: string;
    state: *Text_Input_State;

    occurences: [..] s64;
    current_occurance: s64 = -1;
}