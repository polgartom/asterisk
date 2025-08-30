open_file_browser :: () {
    using file_browser;

    if !fb_text_input {
        fb_text_input = create_text_input(cast(u64)#location());
    }
    
    change_dir(*file_browser, get_workdir());
    
//    log(">\n%\n\n", items);
    
    switch_editor_mode(.WIDGET);
    active_widget = File_Browser;

} @EditorCommandUnlisted(editor_keymap)

_draw_file_browser :: () {
    using file_browser;

    font := primary_font_xs;
    pad  := cast(float32) font.em_width * .5;
    ed_r := active_editor.rect_for_draw;
    
    theme := Text_Input.DEFAULT_THEME;
    theme.bg_color = #run hex_to_vec4(0x19_19_19_ff);
    theme.fg_color = #run hex_to_vec4(0xff_ff_ff_c5);
    theme.border_color = #run hex_to_vec4(0x30_25_0a_ff);
    theme.placeholder_color = #run hex_to_vec4(0xff_ff_ff_8a);
    theme.cursor_color = #run hex_to_vec4(0xff_ff_ff_c5);

    w := 400.0; // @Tempoary
    k := window_height * .1;
    
    h := cast(float, font.character_height * 2.0);
    b := cast(float, window_height - k*.1);
    r := make_rect(ed_r.x-pad, b-h, ed_r.w, h);
    r.x = window_width*.5 - w;
    r.w = w * 2.0;
    r.y += 5.0; 

    tinp := fb_text_input;
    update_text_input(tinp, r, font, theme=theme);
    r.y -= 5.0;

    array_reset_keeping_memory(*options);

    path := path_strip_filename(tinp.text);
    if !platform_path_equals(path, current_dir) {
        modify_string(*current_dir, path);
        file_browser_scan();
    }

    chunks := split(tinp.text, "/",, allocator=temp);
    search_chunk := "";
    if chunks search_chunk = chunks[chunks.count-1];
    
    for items {
        if !search_chunk || platform_path_contains(it.short_name, search_chunk) {
            opt := array_add(*options);
            modify_string(*opt.label, it.short_name);
        }
    }

    list_rect := r;
    list_rect.h = 1.5*k;

    linp_theme := List_Input.DEFAULT_THEME;
    linp_theme.border_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp_theme.current_item_bg_color = #run hex_to_vec4(0x30_25_0a_ff);
    linp := list_input(list_rect, xx #location(), options, font, theme=linp_theme);
    
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

        modify_string(*new_item.short_name, _short_name);
        modify_string(*new_item.full_name, info.full_name);
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

change_dir :: (using fb: *File_Browser, _dir: string) {
    //dir := append_dir_sepa(_dir,, temp);
    //defer free(dir);
    
    clear_text(fb_text_input);
    insert_text(fb_text_input, _dir);
    if (!ends_with(_dir, "/")) insert_text(fb_text_input, "/");
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

    options: [..] List_Input.Option;

    scan_requested := true;
}