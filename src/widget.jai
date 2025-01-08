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

update_file_browser_widget :: () {
    loc := #location(); // remove it!

    k  := window_width * .1;
    k2 := window_height * .1;

    {
        width  := 4.0*k;
        height := my_font.character_height * 2.0;
        r := get_rect(window_width*0.5-width, window_height-height-2.5-15.0, width*2, height);

        w := *file_browser_widget;

        text_theme := my_theme.text_input_theme;
        text_theme.rectangle_shape.roundedness = .0;
        // text_theme.font = my_font;
        
        action, _, state := text_input(r, w.search_text, *text_theme, input_action=.ACTIVATE);

        if action & .TEXT_MODIFIED {
            if state.text.count == 0 || state.text[state.text.count-1] == 0x7F { // Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace @Hacky
                if state.text                    then modify_string(*state.text,                  "");
                if state.pre_modification_text   then modify_string(*state.pre_modification_text, "");
                if w.search_text                 then modify_string(*w.search_text,               "");
            
                w.items.count = 0;
            } else {
                modify_string(*w.search_text, state.text);

                file_browser_find_matches();
            }
        } else if action & .ENTERED {
            using file_browser_widget;
        
            if items.count {
                it := items[0];

                if is_directory(it) {
                    file_browser_change_directory(it);
                } else {
                    already_loaded_into_this_buffer: *Buffer = null;
                    for *buffer: editor.buffers {
                        if buffer.filepath == it {
                            already_loaded_into_this_buffer = buffer;
                            break;
                        }
                    }

                    if already_loaded_into_this_buffer {
                        change_active_buffer(editor, already_loaded_into_this_buffer);
                    } else if file_exists(it) {
                        open_file_or_create_empty_buffer(editor, it);
                        // @Todo should_close_widgets_in_next_frame = true
                    } else {
                        // @Todo: Error hint
                        log_error("I unable to load this file! %\n", it);
                    }

                    switch_editor_mode(.EDITOR);
                }

            }

        }

    }

    {
        width := 4.0*k;
        height := 4.5*k2;

        theme := my_theme.scrollable_region_theme;
        theme.region_background.shape.rounding_flags = 0;
        theme.scrollbar_nib_theme.rectangle_shape.roundedness = .0;

        r := get_rect(window_width*0.5-width, window_height-(height*1.5+my_font.character_height*1.5), width*2, height*1.5-my_font.character_height*2);

        region, inside := begin_scrollable_region(r, *theme, loc=loc);

        label_height := window_height * .03;

        s := inside;
        s.y = s.y + s.h - label_height;
        s.h = label_height;
        s.y += file_browser_widget.scroll_value;

        label_theme := my_theme.label_theme;
        label_theme.alignment = .Left;

        button_theme := my_theme.button_theme;
        button_theme.alignment = .Left;

        basedir := file_browser_widget.base_directory;

        button_id := 0;
        for file_browser_widget.items {
            text := it;
            if begins_with(text, basedir) {
                advance(*text, basedir.count);
                if text[0] == #char "/" then advance(*text, 1);
            }
            
            already_loaded_into_this_buffer: *Buffer = null;

            if is_directory(it) {
                text = tprint("%/", text);
            } else {
                for *buffer: editor.buffers {
                    if buffer.filepath == it {
                        already_loaded_into_this_buffer = buffer;
                        text = tprint("% (opened)", text);
                        break;
                    }
                }
            }

            theme := button_theme;
            if button_id == 0 {
                theme.frame_color = .{.1, .49, .1, 1.0};
            } else {
                theme.surface_color = .{.1, .1, .1, 1.0};
            }

            _, _, was_just_released := button(s, text, *theme, button_id);
            if was_just_released {
                using file_browser_widget;
                
                if is_directory(it) {
                    file_browser_change_directory(it);
                    break;

                } else if already_loaded_into_this_buffer {
                    change_active_buffer(editor, already_loaded_into_this_buffer);
                
                } else {
                    if file_exists(it) {
                        open_file_or_create_empty_buffer(editor, it);
                        // @Todo should_close_widgets_in_next_frame = true
                    } else {
                        // @Todo: Error hint
                        log_error("I unable to load this file! %\n", it);
                    }
                }
            }

            s.y -= floor(label_height * 1.1 + 0.5);
            
            button_id += 1;
        }

        end_scrollable_region(region, s.x + s.w, s.y, *file_browser_widget.scroll_value);
    }
}

file_browser_change_directory :: (new_directory: string) -> (changed: bool) {
    using file_browser_widget;

    if new_directory == base_directory return false;

    base_directory = copy_string(new_directory);
    path_overwrite_separators(base_directory, #char "/");
    
    file_browser_find_matches();
    // items = scan_dir(base_directory, follow_directory_symlinks=false);

    return true;
}

file_browser_find_matches :: () {
    w := *file_browser_widget;

    if !w.search_text {
        w.items.count = 0;
        return;
    }

    dir := w.base_directory;
    files := scan_dir(dir, recursive=true, follow_directory_symlinks=false, files_only=true);
    
    matches: [..] string;
    for fpath: files {
        if find_index_from_left_nocase(fpath, ".git") != -1 continue;

        i := find_index_from_left_nocase(fpath, w.search_text);
        if i != -1 then array_add(*matches, fpath);
    }

    w.items = xx matches;
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

    base_directory: string;
    // list: [..] File_Visit_Info;
    items: [] string;
}

// Temporary
search_text: string;

// Temporary
modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}