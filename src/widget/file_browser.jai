open_file_browser :: () {
    using file_browser;

    if !fb_text_input {
        fb_text_input = create_text_input(cast(u64)#location());
    }

    switch_editor_mode(.WIDGET);
    active_widget = File_Browser;

    file_browser_scan();
}

file_browser_change_dir :: (path: string) -> (success: bool) {
    using file_browser;
    
    is, success := is_directory(path);
    assert(success, "Failed to % check if it's a directory or not.", path);
    assert(is,      "The % is doesn't a valid directory!", path);
    
    modify_string(*current_dir, path);
    path_unify_sepa(current_dir);

    modify_string(*search_text, current_dir);

    return true;
}

// @Cleanup: Remove it!
file_browser_change_dir :: (info: File_Visit_Info) -> (success: bool) {
    using file_browser;

    // @Todo: Check if the directory is still exists.
    if info.had_error || info.is_symlink || !info.is_directory return false;
    assert(!!info.full_name);

    return file_browser_change_dir(info.full_name);
}

file_browser_scan :: () {
    MeasureProc();

    using file_browser;

    array_reset_keeping_memory(*items);

    if !current_dir {
        wd := get_working_directory();
        assert(!!wd.count);
        file_browser_change_dir(wd);
    }

    // {
    //     parent_dir := array_add(*items);
    //     parent_dir.short_name = "..";
    //     modify_string(*parent_dir.full_name, current_dir);
    //     t := path_strip_filename(parent_dir.full_name);
    //     if t then parent_dir.full_name = t;

    //     if ends_with(parent_dir.full_name, "/") then parent_dir.full_name.count -= 1;
        
    //     is, success := is_directory(parent_dir.full_name);
    //     assert(success, "Failed to % check if it's a directory or not.", parent_dir.full_name);
    //     assert(is, "The % is doesn't a valid directory!", parent_dir.full_name);

    //     parent_dir.is_directory = true;
    // }

    visitor :: (info: *File_Visit_Info, browser: *File_Browser) {
        if info.is_directory return;

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
        
        // @Temporary!
        // if (info.short_name == ".git" || info.short_name == ".vs" || info.short_name == ".vscode") info.descend_into_directory = false;
        // ll("> %\n", new_item.*);
    }

    // @Todo: We need to make a recursive version of this file browser, like the "Search files by name" dialog in vscode
    visit_files(current_dir, recursive=true, *file_browser, visitor, visit_directories=true, follow_directory_symlinks=false);
}

file_browser: File_Browser;

File_Browser :: struct {
    fb_text_input: *Text_Input;
 
    search_text: string;
    current_dir: string;

    items: [..] File_Visit_Info;
}