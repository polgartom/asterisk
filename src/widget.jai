
update_search_widget :: () {
    loc := #location();

    k := window_height * .1;
    width := window_width * .15;
    height := my_font.character_height*2.0;
    top_pad := 0.1*k;
    text_theme := my_theme.text_input_theme;
    text_theme.font = my_font;
    r := get_rect((window_width-width*2)-0.1*k, window_height-height-top_pad, width*2, my_font.character_height*2.0);
    action, _, state := text_input(r, search_text, *text_theme, input_action=.ACTIVATE, loc=loc);
    
    {
        hash := get_hash(loc, 0);
        search_widget_state=, _ := find_or_create_state(Text_Input_State, hash, false);
    }

    search_widget_state = state;
    if action & .ENTERED { // Enter pressed
        to_next_occurance();

    } else if action & .TEXT_MODIFIED {
        if state.text.count && state.text[state.text.count-1] == 0x7F {
            // @Hacky Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace
            reset_search_widget();
        } else {
            modify_string(*search_text, state.text);
            find_occurences(search_text);
        }
        
    } 
    // if action & .ESCAPED {
    // }
}

reset_search_widget :: () {
    w := *search_widget;
    using w;

    array_reset_keeping_memory(*occurences);
    current_occurance = -1;

    if search_widget_state {
        if search_widget_state.text modify_string(*search_widget_state.text, "");
        if search_widget_state.pre_modification_text modify_string(*search_widget_state.pre_modification_text, "");
    }

    if search_text modify_string(*search_text, "");
}

find_occurences :: (text: string) {
    w := *search_widget;
    using w;

    array_reset_keeping_memory(*occurences);
    current_occurance = -1;
    if !text return;

    _, buffer := get_active_editor_and_buffer();

    s := to_string(buffer);
    at := 0;
    while true {
        i := find_index_from_left_nocase(s, text, at);
        if i == -1 {
            break;
        }
        at = i + text.count;

        array_add(*occurences, i);
    }
}

to_next_occurance :: () {
    _, buffer := get_active_editor_and_buffer();
    using buffer;

    w := *search_widget;
    using w;

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

search_widget_state: *Text_Input_State;
search_widget: Search_Widget;

Search_Widget :: struct {
    occurences: [..] s64;
    current_occurance: s64 = -1;
}

// Temporary
search_text: string;

// Temporary
modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}