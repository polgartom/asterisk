update_search_widget :: () {
    loc := #location();

    k := window_height * .1;
    width := window_width * .15;
    height := my_font_small.character_height*2.0;
    top_pad := 0.1*k;
    text_theme := my_theme.text_input_theme;
    text_theme.font = my_font_small;
    r := get_rect((window_width-width*2)-0.1*k, window_height-height-top_pad, width*2, my_font_small.character_height*2.0);
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

update_file_browser_widget :: () {
    loc := #location(); // remove it!

    k  := window_width * .1;
    k2 := window_height * .1;

    font := my_font_small;


    {
        width  := 4.0*k;
        height := my_font_small.character_height * 2.0;
        r := get_rect(window_width*0.5-width, window_height-height-2.5-15.0, width*2, height);

        w := *file_browser_widget;
        text_theme := my_theme.text_input_theme;
        text_theme.rectangle_shape.roundedness = .0;
        text_theme.font = my_font_small;
        
        action, _, state := text_input(r, w.search_text, *text_theme, input_action=.ACTIVATE);

        // if action & .TEXT_MODIFIED {
        //     if state.text.count == 0 || state.text[state.text.count-1] == 0x7F { // Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace @Hacky
        //         if state.text                    then modify_string(*state.text,                  "");
        //         if state.pre_modification_text   then modify_string(*state.pre_modification_text, "");
        //         if w.search_text                 then modify_string(*w.search_text,               "");
            
        //         w.items.count = 0;
        //     } else {
        //         modify_string(*w.search_text, state.text);
        //     }
        // } else if action & .ENTERED {
        //     using file_browser_widget;

        // }
    }

    {
        using file_browser_widget;

        width := 4.0*k;
        height := 4.5*k2;

        theme := my_theme.scrollable_region_theme;
        theme.region_background.shape.rounding_flags = 0;
        theme.scrollbar_nib_theme.rectangle_shape.roundedness = .0;

        r := get_rect(window_width*0.5-width, window_height-(height*1.5+my_font_small.character_height*1.5), width*2, height*1.5-my_font_small.character_height*2);

        region, inside := begin_scrollable_region(r, *theme, loc=loc);

        label_height := window_height * .03;

        s := inside;
        s.y = s.y + s.h - label_height;
        s.h = label_height;
        s.y += scroll_value;

        label_theme := my_theme.label_theme;
        label_theme.alignment = .Left;

        button_theme := my_theme.button_theme;
        button_theme.alignment = .Left;
        button_theme.font = my_font_small;

        basedir := current_directory;

        list, found := table_find(*table, basedir);
        assert(found, "basedir: %\n", basedir);
        
        id := 0;
        for list {
            _, _, was_just_released := button(s, it.name, *button_theme, id);
            if was_just_released {
                if it.is_directory {
                    child_dir := tprint("%1%2/", basedir, it.name);
                    _, found := table_find(*table, child_dir);
                    assert(found, "child_dir: %\n", child_dir);
                    
                    modify_string(*current_directory, child_dir);
                } else {
                    fpath := tprint("%1/%2", basedir, it.name);
                    assert(file_exists(fpath), "fpath: %\n", fpath);

                    open_file_or_create_empty_buffer(editor, fpath);
                }
            }
            
            s.y -= floor(label_height * 1.1 + 0.5);
            
            id += 1;
        }

        // button_id := 0;
        // for file_browser_widget.items {
        //     text := it;
        //     if begins_with(text, basedir) {
        //         advance(*text, basedir.count);
        //         if text[0] == #char "/" then advance(*text, 1);
        //     }
            
        //     already_loaded_into_this_buffer: *Buffer = null;

        //     if is_directory(it) {
        //         text = tprint("%/", text);
        //     } else {
        //         for *buffer: editor.buffers {
        //             if buffer.filepath == it {
        //                 already_loaded_into_this_buffer = buffer;
        //                 text = tprint("% (opened)", text);
        //                 break;
        //             }
        //         }
        //     }

        //     theme := button_theme;
        //     if button_id == 0 {
        //         theme.frame_color = .{.1, .49, .1, 1.0};
        //     } else {
        //         theme.surface_color = .{.1, .1, .1, 1.0};
        //     }

        //     _, _, was_just_released := button(s, text, *theme, button_id);
        //     if was_just_released {
        //         using file_browser_widget;
                
        //         if is_directory(it) {
        //             file_browser_change_directory(it);
        //             break;

        //         } else if already_loaded_into_this_buffer {
        //             change_active_buffer(editor, already_loaded_into_this_buffer);
                
        //         } else {
        //             if file_exists(it) {
        //                 open_file_or_create_empty_buffer(editor, it);
        //                 // @Todo should_close_widgets_in_next_frame = true
        //             } else {
        //                 // @Todo: Error hint
        //                 log_error("I unable to load this file! %\n", it);
        //             }
        //         }
        //     }

        //     s.y -= floor(label_height * 1.1 + 0.5);
            
        //     button_id += 1;
        // }

        end_scrollable_region(region, s.x + s.w, s.y, *file_browser_widget.scroll_value);
    }
}

file_browser_scan :: (start_dir: string) {
    timer := seconds_since_init();

    using file_browser_widget;
    
    if table.entries.count {
        table_reset(*table);
    }

    t := tprint("%1%2", start_dir, ifx !ends_with(start_dir, "/") then "/" else "");
    modify_string(*current_directory, t);

    entries := scan_dir2(current_directory, recursive=true, follow_directory_symlinks=false, files_only=false);

    last_dir := current_directory;
    temp_list: [..] File_Browser_Widget.Path_Info;
    for * entries {
        it.full_name = path_strip_filename(it.full_name);
        dir := it.full_name;

        if dir != last_dir {
            key := copy_string(last_dir);
            value := array_copy(temp_list);
            table_add(*table, key, value);
            
            last_dir = dir;
            array_reset_keeping_memory(*temp_list);
        }

        name := copy_string(it.short_name);
        array_add(*temp_list, .{name = name, is_directory = it.is_directory});
    }

    // for table {
    //     key, value := it_index, it;
    //     print("> % ; %\n", key, value);
    // }

    print("[file_browser_scan] entries: % ; duration: %ms\n", table.entries.count, (seconds_since_init() - timer)*1000);
}

active_widget: Type;

search_widget_state: *Text_Input_State;
search_widget: Search_Widget;

file_browser_widget: File_Browser_Widget;

Search_Widget :: struct {
    occurences: [..] s64;
    current_occurance: s64 = -1;
}

File_Browser_Widget :: struct {
    search_text: string;

    scroll_value: float;

    current_directory: string;
    table: Table(string, [] Path_Info);

    Path_Info :: struct {
        name: string;
        is_directory: bool;
    }

}

// Temporary
search_text: string;

// Temporary
modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}