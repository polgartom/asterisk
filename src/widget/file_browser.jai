open_file_browser :: () {
    using file_browser;

    if !fb_text_input {
        fb_text_input = create_text_input(cast(u64)#location());
    }

    switch_editor_mode(.WIDGET);
    active_widget = File_Browser;

    if scan_requested {
        file_browser_scan();
    }

} @EditorCommandUnlisted(editor_keymap)

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

// @Speed: We don't want to run this on every file browser dialog open!
file_browser_scan :: () {
    using file_browser;

    array_reset_keeping_memory(*items);

    if !current_dir {
        wd := get_working_directory();
        assert(!!wd.count);
        file_browser_change_dir(wd);
    }

    visitor :: (info: *File_Visit_Info, browser: *File_Browser) {
        if info.is_directory {
            if workspace.exclude.count {
                found := table_find_new(*workspace.exclude, info.short_name);
                if (found) {
                    info.descend_into_directory = false;
                    return;
                }
            }

            // if workspace.paths.count {
            //     found := table_find_new(*workspace.paths, info.short_name);
            //     if (!found) {
            //         info.descend_into_directory = false;
            //         return;
            //     }
            // }
        }

        if workspace.files.count {
            match := false;
            for workspace.files {
                if wildcard_match(info.short_name, it_index) {
                    match = true;
                    break;
                }
            }

            if !match return;
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

    // @Todo: We need to make a recursive version of this file browser, like the "Search files by name" dialog in vscode
    visit_files(current_dir, recursive=true, *file_browser, visitor, visit_directories=true, follow_directory_symlinks=false);

    // for items {
    //     open_file_or_create_empty_buffer(active_editor, it.full_name);
    //     // if ends_with(it.full_name, ".jai") open_file_or_create_empty_buffer(active_editor, it.full_name);
    // }

    scan_requested = false;
} @EditorCommand(name=Rescan_Working_Directory)

file_browser: File_Browser;

File_Browser :: struct {
    fb_text_input: *Text_Input;
 
    search_text: string;
    current_dir: string;

    items: [..] File_Visit_Info;

    scan_requested := true;
}