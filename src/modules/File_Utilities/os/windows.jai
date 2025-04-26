#scope_export;

copy_file :: (source: string, dest: string, silent := false) -> bool {
    source_wstr := utf8_to_wide(source,, temp);
    dest_wstr   := utf8_to_wide(dest,, temp);

    success := CopyFileW(source_wstr, dest_wstr, 0);
    if !success {
        if !silent log_error("Unable to copy file \"%\" to \"%\".\n", source, dest);
        return false;
    }

    return true;
}

// @Cleanup: Make a single heap for visit_files (allocations
// of the strings and of the array), and just free the heap
// at the end.

visit_files :: (dir_name: string, recursive: bool, user_data: $T, proc: (info: *File_Visit_Info, user_data: T), visit_files := true, visit_directories := false, visit_symlinks := true, follow_directory_symlinks := true) -> bool {

    if !proc return true;
    
    // We don't want to call auto_release_temp because it might cause unexpected behavior depending on what the user does in proc.
    // In the sokoban game, we were adding to a temp array that was passed in via user_data, and when the array resized, the new allocation would be after the mark.
    // This caused the allocation to be released when we restored the mark.
    //      -berk, 1 July 2024

    directories: [..] string;
    directories.allocator = temp;
    array_add(*directories, dir_name);

    info: File_Visit_Info = ---;
    info.had_error  = false;

    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;
        
        wildcard_name := utf8_to_wide(tprint("%/*", dir_name),, temp);

        find_data: WIN32_FIND_DATAW = ---;
        // handle := FindFirstFileW(wildcard_name, *find_data);
        handle := FindFirstFileExW(wildcard_name, FindExInfoBasic, *find_data, FindExSearchNameMatch, null, FIND_FIRST_EX_LARGE_FETCH);
        // FIND_FIRST_EX_LARGE_FETCH improves performance by a bit when searching through large numbers of files.

        if handle == INVALID_HANDLE_VALUE {
            if cursor != 1  continue;

            error_value, error_string := get_error_value_and_string();
            log_error("Unable to open directory '%': % %", dir_name, error_value, error_string);
            return false;
        }

        while true {
            name := wide_to_utf8(find_data.cFileName.data,, temp);
            full_name := join(dir_name, "/", name,, temp);

            info.short_name             = name;
            info.full_name              = full_name;
            info.descend_into_directory = false;
            // :WindowsSymlinks
            // Note that if this is a symlink then full_name, short_name and modification_time will be for the symlink file
            // and not its target. If you want the target path then you need to call the Windows DeviceIoControl function
            // with a handle to the symlink file. The target modification time and size can be retrieved by passing the
            // symlink path to file_modtime_and_size().
            //
            // This also doesn't detect symlink loops, but FindNextFileW will eventually bail... you'll just have a lot of
            // extra proc calls.
            info.is_symlink             = (find_data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && (find_data.dwReserved0 == IO_REPARSE_TAG_SYMLINK);
            info.is_directory           = (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;

            if info.is_directory {
                if name != "." && name != ".." {
                    info.descend_into_directory = recursive && (follow_directory_symlinks || !info.is_symlink);
                    if visit_directories && (visit_symlinks || !info.is_symlink) {
                        info.modification_time = filetime_to_apollo(find_data.ftLastWriteTime);
                        proc(*info, user_data);
                    }

                    if info.descend_into_directory  array_add(*directories, full_name);
                }
            } else {
                if visit_files && (visit_symlinks || !info.is_symlink) {
                    info.modification_time = filetime_to_apollo(find_data.ftLastWriteTime);

                    proc(*info, user_data);
                }
            }

            success := FindNextFileW(handle, *find_data);
            if !success break;
        }

        FindClose(handle);
    }

    return true;
}

file_exists :: (file_path: string) -> bool {
    // PathFileExists requires linking to shlwapi.lib, so don't use it!
    // return PathFileExistsW(utf8_to_wide(file_path)) != 0;
    return GetFileAttributesW(xx utf8_to_wide(file_path,, temp)) != INVALID_FILE_ATTRIBUTES;
}

file_modtime_and_size :: (file_path: string) -> (modtime: Apollo_Time, size: s64, success: bool) {
    h := CreateFileW(xx utf8_to_wide(file_path,, temp), 0 /*GENERIC_READ*/, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE, null, OPEN_EXISTING, FILE_ATTRIBUTE_READONLY|FILE_FLAG_BACKUP_SEMANTICS, null);
    if h == INVALID_HANDLE_VALUE return .{}, 0, false;

    write_time: FILETIME;
    GetFileTime(h, null, null, *write_time);

    file_size: LARGE_INTEGER;
    ret := GetFileSizeEx(h, *file_size);

    CloseHandle(h);

    apollo := filetime_to_apollo(write_time);
    return apollo, file_size.QuadPart, ret != 0;
}

atomic_file_replace_or_just_rename_if_destination_file_does_not_exist :: (old_filename: string, new_filename: string) -> bool {
    old_filename_w := utf8_to_wide(old_filename,, temp);
    new_filename_w := utf8_to_wide(new_filename,, temp);

    attribs := GetFileAttributesW(new_filename_w);
    if attribs == INVALID_FILE_ATTRIBUTES {
        success := MoveFileW(old_filename_w, new_filename_w);
        return cast(bool) success;
    } else {
        success := ReplaceFileW(new_filename_w, old_filename_w, null, 0, null, null);
        return cast(bool) success;
    }
}

is_directory :: (path: string) -> bool, success: bool {
    attrib := GetFileAttributesW(utf8_to_wide(path,, temp));
    if attrib == INVALID_FILE_ATTRIBUTES {
        return false, false;
    }

    is_dir := (attrib & FILE_ATTRIBUTE_DIRECTORY) != 0;
    return is_dir, true;
}

#scope_file;
#import "Windows";
#import "Windows_Utf8";
#import "System";

