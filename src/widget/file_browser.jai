// file_browser_select_entry :: (index: s64) {
//     using file_browser;

//     list, found := table_find(*table, current_directory);
//     assert(found, "%\n", current_directory);
//     assert(index < list.count, "index: % ; list: %\n", index, list);

//     entry := list[index];
//     if entry.is_directory {
//         dir := tprint("%1%2/", current_directory, entry.name);
//         file_browser_change_directory(dir);
//     } else {
//         fpath := tprint("%1/%2", current_directory, entry.name);
//         assert(file_exists(fpath), "fpath: %\n", fpath);

//         open_file_or_create_empty_buffer(active_editor, fpath);
//         array_add(*user_events, .{ type = .CLOSE_WIDGET });
//     }

//     clear_file_browser_text_input();
// }

// file_browser_scan_for_files :: (start_dir: string) {
//     using file_browser;

//     timer := seconds_since_init();

//     if table.entries.count {
//         table_reset(*table);
//     }

//     t := tprint("%1%2", start_dir, ifx !ends_with(start_dir, "/") then "/" else "");
//     file_browser_change_directory(t);

//     entries := scan_dir2(current_directory, recursive=true, follow_directory_symlinks=false, files_only=false);

//     last_dir := current_directory;
//     temp_list: [..] File_Browser.Path_Info;
//     for * entries {
//         it.full_name = path_strip_filename(it.full_name);
//         dir := it.full_name;

//         if dir != last_dir {
//             key := copy_string(last_dir);
//             value := array_copy(temp_list);
//             table_add(*table, key, value);
            
//             last_dir = dir;
//             array_reset_keeping_memory(*temp_list);
//         }

//         name := copy_string(it.short_name);
//         array_add(*temp_list, .{name = name, is_directory = it.is_directory});
//     }

//     // for table {
//     //     key, value := it_index, it;
//     //     print("> % ; %\n", key, value);
//     // }

//     print("[file_browser_scan] entries: % ; duration: %ms\n", table.entries.count, (seconds_since_init() - timer)*1000);
// }

// file_browser_change_directory :: (dir: string) {
//     using file_browser;

//     if current_directory { // @Hacky
//         list, found := table_find(*table, dir);
//         if !found {
//             log_error("% directory cannot be selected!", dir);
//             return;
//         }
//     }

//     modify_string(*current_directory, copy_string(dir));
//     selected_entry_index = -1;
// }

// clear_file_browser_text_input :: () {
//     using file_browser;

//     if state set_text(state, "");
//     if search_text search_text.count = 0;
// }

// update_file_browser :: () {
//     loc := #location(); // remove it!

//     k  := window_width * .1;
//     k2 := window_height * .1;

//     font := my_font_small;

//     {
//         width  := 4.0*k;
//         height := my_font_small.character_height * 2.0;
//         r := get_rect(window_width*0.5-width, window_height-height-2.5-15.0, width*2, height);

//         w := *file_browser;
//         text_theme := my_theme.text_input_theme;
//         text_theme.rectangle_shape.roundedness = .0;
//         text_theme.font = my_font_small;
        
//         action, _, state := text_input(r, w.search_text, *text_theme, input_action=.ACTIVATE);

//         if action & .TEXT_MODIFIED {
//             if state.text {
//                 if state.text[state.text.count-1] == 0x7F { // Prevent insertion of the "Delete character" (127) because of the Ctrl-Backspace @Hacky
//                     clear_file_browser_text_input();
//                 } else {
//                     modify_string(*w.search_text, state.text);
//                 }
//             } else {
//                 if w.search_text {
//                     w.search_text.count = 0;
//                 }
//             }
//         }
//     }

//     {
//         using file_browser;

//         width := 4.0*k;
//         height := 4.5*k2;

//         theme := my_theme.scrollable_region_theme;
//         theme.region_background.shape.rounding_flags = 0;
//         theme.scrollbar_nib_theme.rectangle_shape.roundedness = .0;

//         r := get_rect(window_width*0.5-width, window_height-(height*1.5+my_font_small.character_height*1.5), width*2, height*1.5-my_font_small.character_height*2);

//         region, inside := begin_scrollable_region(r, *theme, loc=loc);

//         label_height := window_height * .03;

//         s := inside;
//         s.y = s.y + s.h - label_height;
//         s.h = label_height;
//         s.y += scroll_value;

//         label_theme := my_theme.label_theme;
//         label_theme.alignment = .Left;

//         button_theme := my_theme.button_theme;
//         button_theme.alignment = .Left;
//         button_theme.font = my_font_small;

//         basedir := current_directory;

//         list, found := table_find(*table, basedir,, temp);
//         if !found {
//             log_error("I cannot found the basedir: '%'\n", basedir); // @Todo: error hint for the user 
//             close_current_widget(); // this will prevent the flickering of the file browser window
//             return;
//         }

//         _list: [..] Path_Info;
//         _list.allocator = temp;

//         if search_text {
//             for e: list {
//                 index := index_of_string_nocase(e.name, search_text);
//                 if index != -1 {
//                     array_add(*_list, e);
//                 }
//             }

//             list = _list;
//         }

//         if should_recalc_scroll_offsets {
//             top := 0.0;
//             for index: -1..list.count { // -1 means the first entry of the file list which is the parent directory 
//                 if index == selected_entry_index {
//                     break;
//                 }
//                 top += floor(label_height * 1.1 + 0.5);
//             }

//             // This will cause a scrolling animation, because we're working with the value of "floor(label_height * 1.1 + 0.5)" on every frame
//             // until it's not below 0 or above s.y
//             if top - scroll_value < 0 {
//                 scroll_value -= floor(label_height * 1.1 + 0.5);
//             } else if r.y + top > s.y {
//                 scroll_value += floor(label_height * 1.1 + 0.5);
//             } else {
//                 should_recalc_scroll_offsets = false;
//             }
//         }

//         {
//             parent := parent_dir(current_directory);
//             PrintDev("parent_dir: %\n", parent);

//             _, found := table_find(*table, parent);
            
//             theme := button_theme;
//             theme.surface_color = Vector4.{.3,.3,.3,1.0};
//             if !found {
//                 theme.surface_color.w = .2;
//                 theme.text_color.w    = .5;
//             }
//             if selected_entry_index == -1 {
//                 theme.frame_color = .{.2,.9,.3,1.0};
//             }

//             text := tprint("[UP] %", ifx found then parent else "");
//             _, _, was_just_released := button(s, text, *theme, -1, disable_over=!found, disable_press=!found);
        
//             if found && was_just_released {
//                 file_browser_change_directory(parent);
//             }
            
//             s.y -= floor(label_height * 1.1 + 0.5);
//         }

//         id := 0;

//         for list {
//             theme := button_theme;
//             if id == selected_entry_index {
//                 theme.frame_color = .{.2, .6 ,.3, 1.0};
//             }

//             _, _, was_just_released := button(s, it.name, *theme, id);
//             if was_just_released {
//                 if it.is_directory {
//                     child_dir := tprint("%1%2/", basedir, it.name);
//                     _, found := table_find(*table, child_dir);
//                     assert(found, "child_dir: %\n", child_dir);
                    
//                     file_browser_change_directory(child_dir);                    
//                 } else {
//                     fpath := tprint("%1/%2", basedir, it.name);
//                     assert(file_exists(fpath), "fpath: %\n", fpath);

//                     open_file_or_create_empty_buffer(active_editor, fpath);
//                     array_add(*user_events, .{ type = .CLOSE_WIDGET });
//                 }
//             }
            
//             s.y -= floor(label_height * 1.1 + 0.5);
            
//             id += 1;
//         }

//         end_scrollable_region(region, s.x + s.w, s.y, *file_browser.scroll_value);
//     }
// }

file_browser: File_Browser;

File_Browser :: struct {
    search_text: string;
    state: *Text_Input_State;

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
