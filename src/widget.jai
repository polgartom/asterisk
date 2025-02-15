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
        if !found {
            log_error("I cannot found the basedir: '%'\n", basedir); // @Todo: error hint for the user 
            close_current_widget(); // this will prevent the flickering of the file browser window
            return;
        }

        if should_recalc_scroll_offsets {
            top := 0.0;
            for index: -1..list.count { // -1 means the first entry of the file list which is the parent directory 
                if index == selected_entry_index {
                    break;
                }
                top += floor(label_height * 1.1 + 0.5);
            }

            // This will cause a scrolling animation, because we're working with the value of "floor(label_height * 1.1 + 0.5)" on every frame
            // until it's not below 0 or above s.y
            if top - scroll_value < 0 {
                scroll_value -= floor(label_height * 1.1 + 0.5);
            } else if r.y + top > s.y {
                scroll_value += floor(label_height * 1.1 + 0.5);
            } else {
                should_recalc_scroll_offsets = false;
            }
        }

        {
            parent := parent_dir(current_directory);
            PrintDev("parent_dir: %\n", parent);

            _, found := table_find(*table, parent);
            
            theme := button_theme;
            theme.surface_color = Vector4.{.3,.3,.3,1.0};
            if !found {
                theme.surface_color.w = .2;
                theme.text_color.w    = .5;
            }
            if selected_entry_index == -1 {
                theme.frame_color = .{.2,.9,.3,1.0};
            }

            text := tprint("[UP] %", ifx found then parent else "");
            _, _, was_just_released := button(s, text, *theme, -1, disable_over=!found, disable_press=!found);
        
            if found && was_just_released {
                file_browser_change_directory(parent);
            }
            
            s.y -= floor(label_height * 1.1 + 0.5);
        }

        id := 0;

        for list {
            theme := button_theme;
            if id == selected_entry_index {
                theme.frame_color = .{.2, .6 ,.3, 1.0};
            }

            _, _, was_just_released := button(s, it.name, *theme, id);
            if was_just_released {
                if it.is_directory {
                    child_dir := tprint("%1%2/", basedir, it.name);
                    _, found := table_find(*table, child_dir);
                    assert(found, "child_dir: %\n", child_dir);
                    
                    file_browser_change_directory(child_dir);                    
                } else {
                    fpath := tprint("%1/%2", basedir, it.name);
                    assert(file_exists(fpath), "fpath: %\n", fpath);

                    open_file_or_create_empty_buffer(active_editor, fpath);
                    array_add(*user_events, .{ type = .CLOSE_WIDGET });
                }
            }
            
            s.y -= floor(label_height * 1.1 + 0.5);
            
            id += 1;
        }

        end_scrollable_region(region, s.x + s.w, s.y, *file_browser_widget.scroll_value);
    }
}

file_browser_change_directory :: (dir: string) {
    using file_browser_widget;

    if current_directory { // @Hacky
        list, found := table_find(*table, dir);
        if !found {
            log_error("% directory cannot be selected!", dir);
            return;
        }
    }

    modify_string(*current_directory, copy_string(dir));
    selected_entry_index = -1;
}

file_browser_select_entry :: (index: s64) {
    using file_browser_widget;
    
    list, found := table_find(*table, current_directory);
    assert(found, "%\n", current_directory);
    assert(index < list.count, "index: % ; list: %\n", index, list);

    entry := list[index];
    if entry.is_directory {
        dir := tprint("%1%2/", current_directory, entry.name);
        file_browser_change_directory(dir);
    } else {
        fpath := tprint("%1/%2", current_directory, entry.name);
        assert(file_exists(fpath), "fpath: %\n", fpath);

        open_file_or_create_empty_buffer(active_editor, fpath);
        array_add(*user_events, .{ type = .CLOSE_WIDGET });
    }
}

file_browser_scan :: (start_dir: string) {
    timer := seconds_since_init();

    using file_browser_widget;
    
    if table.entries.count {
        table_reset(*table);
    }

    t := tprint("%1%2", start_dir, ifx !ends_with(start_dir, "/") then "/" else "");
    file_browser_change_directory(t);

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

close_current_widget :: () {
    switch_editor_mode(.EDITOR);
}

active_widget: Type;

search_widget_state: *Text_Input_State;
search_widget: Search_Widget;

file_browser_widget: File_Browser_Widget;

// Temporary
search_text: string;
Search_Widget :: struct {
    occurences: [..] s64;
    current_occurance: s64 = -1;
}

File_Browser_Widget :: struct {
    search_text: string;
    scroll_value: float;
    should_recalc_scroll_offsets: bool;

    current_directory: string;
    table: Table(string, [] Path_Info);
    selected_entry_index := -1;


    Path_Info :: struct {
        name: string;
        is_directory: bool;
    }
}
