
update_search_widget :: () {
    loc := #location();

    k := window_height * .1;
    width := window_width * .15;
    height := my_font.character_height*2.0;
    top_pad := 0.1*k;
    text_theme := my_theme.text_input_theme;
    // text_theme.
    text_theme.font = my_font;
    // r := get_rect((window_width/2.0)-width, window_height-height-top_pad, width+width, my_font.character_height*2.0);
    r := get_rect((window_width-width*2)-0.1*k, window_height-height-top_pad, width*2, my_font.character_height*2.0);
    action, _, state := text_input(r, search_text, *text_theme, input_action=.ACTIVATE, loc=loc);
    
    {
        hash := get_hash(loc, 0);
        last_widget_state=, _ := find_or_create_state(Text_Input_State, hash, false);
    }

    last_widget_state = state;
    // print("input: % ; %\n", action, state.*);
    if action & .ENTERED { // Enter pressed
        print("entered\n");    
        find_next_occurance(search_text);
    } else if action & .TEXT_MODIFIED {
        modify_string(*search_text, state.text);
    }
    if action & .ESCAPED {

    }
    //     modify_string(*state.pre_modification_text, "");
    //     memset(*state.input_buffer, 0, state.MAX_BUFFER_SIZE);
    //     CloseCurrentWidget();

    //     // getrect_handle_event(
    //     // modify_string(*state.text, "");
    //     // modify_string(*state.pre_modification_text, "");
    //     // modify_string(*state.last_saved_input, "");
    // }
}

show_search_widget :: () {
    w := *search_widget;
    using w;
    
    current_occurance_pos = -1;
}

hide_search_widget :: () {
    w := *search_widget;
    using w;

    current_occurance_pos = -1;
}

find_next_occurance :: (text: string) {
    editor, buffer := get_active_editor_and_buffer();
    using buffer;

    w := *search_widget;
    using w;

    if !text || !(_cursor.pos < buffer.count) {
        current_occurance_pos = -1;
        return;
    }
    
    s := to_string(buffer);
    i := find_index_from_left(s, text, _cursor.pos);
    assert(i < buffer.count);
    current_occurance_pos = i;

    if i != -1 {
        set_cursor_pos(buffer, *_cursor, i, horizontal=true, with_selection=true);
    }
}

search_widget: Search_Widget;

Search_Widget :: struct {
    has_occurence := false;
    current_occurance_pos: s64;
}