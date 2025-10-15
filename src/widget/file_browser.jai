open_file_browser :: () {
    using file_browser;

    if !fb_text_input {
        fb_text_input = create_text_input(cast(u64)#location());
    }
    
    if current_dir {
        // Reset the input's text to a properly formatted path so we can list all files
        // in the current directory. For example, the input might be entered as:
        // "K:\Programming\asterisk\src\sour". In this case, we searched for "source.jai",
        // but the path was only partially filled. Since we did find the file, the current
        // directory is actually ".../src". We need to restore the correct format by
        // removing the extra "sour" part and appending a separator ("/") at the end,
        // resulting in: "K:\Programming\asterisk\src\".
        insert_directory_to_text_input(current_dir);
        file_browser_scan();
    } else {
        file_browser_change_dir(get_workdir());
    }
    
    switch_editor_mode(.WIDGET);
    active_widget = File_Browser;

} @EditorCommandUnlisted(editor_keymap)

_draw_file_browser :: () {
    using file_browser;

    font := r_font_sm;
    pad  := cast(float32) font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x19_19_19_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0x3a_4a_7a_ff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    w := window_width * 0.4; // @Tempoary
    w = max(w, 400);
    k := window_height * .1;
    
    h := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x-pad, b-h, ed_r.w, h);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

    tinp := fb_text_input;
    update_text_input(tinp, r, font, theme=theme);
    //label(xx(r.x-30), xx r.y, FOLDER_ICON, r_font_icons, theme.fg_color);
    
    r.y -= 5.0;

    array_reset_keeping_memory(*options);

    // @Todo: Handle multiple drives

    path := path_strip_filename(tinp.text);
    if !platform_path_equals(path, current_dir) {
        modify_string(*current_dir, path);
        file_browser_scan();
    }

    chunks := split(tinp.text, "/",, allocator=temp);
    search_chunk := "";
    if chunks search_chunk = chunks[chunks.count-1];
    
    prefix_width := max(file_icon_md_width, folder_icon_md_width);
    
    for items {
        if !search_chunk || platform_path_contains(it.short_name, search_chunk) {
            opt := array_add(*options);
            memmove(*opt.ref, *it, size_of(File_Visit_Info));
            if it.is_directory opt.priority += items.count+1;
            
            opt.label_prefix_styled.font_override = r_font_icons;
            opt.label_prefix_styled.x_offset = 2;
            if it.is_directory {
                modify_string(*opt.label_prefix, FOLDER_ICON);
            } else {
                modify_string(*opt.label_prefix, FILE_ICON);
                opt.label_prefix_styled.default_colorv4 = #run hex_to_vec4(0xff_ff_ff_8a);
            }
            
            modify_string(*opt.label, it.short_name);
            opt.label_styled.x_offset = prefix_width + 8;
        }
    }
    
    quick_sort(options, (a, b) => cast(s64) (utf8_character_count(b.label) - utf8_character_count(a.label))); // prefer shorter files 
    quick_sort(options, (a, b) => cast(s64) ((b.priority) - (a.priority)));                                     // prefer directories over files

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x3a_4a_7a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x3a_4a_7a_8a);
    linp := list_input(list_rect, xx #location(), options, font, theme=linp_theme);
    
    if tinp.typed {
        linp.scroll_value = 0.0;
        linp.selected_index = -1;
    }
    
    if linp.selected_index == -1 linp.selected_index = 0;
    
    if linp.entered && options.count {
        if linp.selected_index >= options.count || linp.selected_index < 0 {
            log_error("Invalid index: % ; options: %\n", linp.selected_index, options);
            linp.selected_index = -1;
            return;                
        }
                
        opt := options[linp.selected_index];
        if opt.ref.is_directory {
            file_browser_change_dir(opt.ref.full_name);
        } else {
            buffer := open_file_or_create_empty_buffer(active_editor, opt.ref.full_name);
            change_active_buffer(active_editor, buffer);
            close_current_widget();
        }
        
        linp.selected_index = 0;
    }
    
}

file_browser_scan :: () {
    using file_browser;

    array_reset_keeping_memory(*items);

    visitor :: (info: *File_Visit_Info, browser: *File_Browser) {
        if should_ignore_path(info.full_name) {
            return;
        }

        new_item := array_add(*browser.items);

        // Replace the temporary allocated strings
        _short_name := advance(info.full_name, file_browser.current_dir.count);
        assert(!!_short_name);
        if _short_name[0] == #char "/" then advance(*_short_name, 1);

        fullname := info.full_name;
        chunks := split(info.full_name, "/",, allocator=temp);
        for chunks if !it remove it;
        fullname = join(..chunks, separator="/",, temp);

        //log("# %\n", fullname);

        modify_string(*new_item.short_name, _short_name);
        modify_string(*new_item.full_name, fullname);
        path_unify_sepa(new_item.short_name);
        path_unify_sepa(new_item.full_name);

        using new_item;
        modification_time      = info.modification_time;
        had_error              = info.had_error;
        is_symlink             = info.is_symlink;
        is_directory           = info.is_directory;
        descend_into_directory = info.descend_into_directory;        
    }

    visit_files(current_dir, recursive=false, *file_browser, visitor, visit_directories=true, follow_directory_symlinks=false);

    scan_requested = false;
}

#scope_file

insert_directory_to_text_input :: (dir: string) {
    using file_browser;
    
    clear_text(fb_text_input);
    insert_text(fb_text_input, dir);
    if !ends_with(dir, "/") insert_text(fb_text_input, "/");
}

file_browser_change_dir :: (dir: string) {
    using file_browser;
    
    insert_directory_to_text_input(dir);
    modify_string(*current_dir, fb_text_input.text);
    file_browser_scan();
}

#scope_export

file_browser: File_Browser;

File_Browser :: struct {
    fb_text_input: *Text_Input;
    search_text: string;
    current_dir: string;
    items: [..] File_Visit_Info;
    options: [..] List_Input.Option(File_Visit_Info);
    scan_requested := true;
}