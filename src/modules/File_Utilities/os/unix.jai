#scope_export;

copy_file :: (source: string, dest: string) -> bool {
    // Dumb, temporary implementation!
    data, success := read_entire_file(source);
    if !success {
        log_error("Unable to open file '%' for reading.\n", source);
        return false;
    }
    defer free(data);

    success = write_entire_file(dest, data);
    if !success {
        log_error("Unable to write file '%'.\n", dest);
        return false;
    }

    return success;
}

visit_files :: (dir_name: string, recursive: bool, user_data: $T, proc: (info: *File_Visit_Info, user_data: T), visit_files := true, visit_directories := false, visit_symlinks := true, follow_directory_symlinks := true) -> bool {
    if !proc return true;

    directories: [..] string;
    directories.allocator = temp;
    array_add(*directories, dir_name);

    info: File_Visit_Info = ---;

    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;

        dirp := opendir(temp_c_string(dir_name));
        if !dirp {
            if cursor != 1  continue;

            error_value, error_string := get_error_value_and_string();
            log_error("Unable to open directory '%': % %", dir_name, error_value, error_string);
            return false;
        }
        defer closedir(dirp);

        entry := readdir(dirp);
        while entry != null {
            name := to_string(entry.d_name.data);

            full_name := join(dir_name, "/", name,, temp);

            info.had_error = false;
            stats: stat_t;
            ret := stat(temp_c_string(full_name), *stats);
            if ret == 0 {
                info.is_directory = S_ISDIR(stats.st_mode);
            } else {
                error_value := get_error_value();
                // ENOENT happens for symlinks that point to a missing file
                // We still might want to visit those symlinks, so we report them
                // It might also happen due to a race if the file is deleted between readdir and stat, but we let the user decide what to do with that information
                // EACCES happens if we don’t have enought permissions for that file/dir. We still report it and let the user handle access errors
                // ELOOP happens if we try to follow a symlink loop for too long
                if error_value != ENOENT && error_value != EACCES && error_value != ELOOP {
                    error_string := get_error_string(error_value);
                    log_error("Unable to stat file '%': % %", full_name, error_value, error_string);
                    return false;
                }

                info.had_error = true;
                info.is_directory = false;
            }

            info.short_name = name;
            info.full_name  = full_name;
            info.descend_into_directory = false;
            info.is_symlink = (entry.d_type == .LNK);

            if info.is_directory {
                if name != "." && name != ".." {
                    info.descend_into_directory = recursive && (follow_directory_symlinks || !info.is_symlink);
                    if visit_directories && (visit_symlinks || !info.is_symlink) {
                        info.modification_time = timespec_to_apollo(stats.st_mtime);
                        proc(*info, user_data);
                    }
                }

                if info.descend_into_directory  array_add(*directories, full_name);
            } else {
                if visit_files && (visit_symlinks || !info.is_symlink) {
                    info.modification_time = timespec_to_apollo(stats.st_mtime);
                    proc(*info, user_data);
                }
            }

            entry = readdir(dirp);
        }
    }

    return true;
}

file_exists :: (path: string) -> bool {
    result := access(temp_c_string(path), 0);
    return result == 0;
}

// Why are we returning an OS-specific modtime, without documenting that or giving people
// a way to deal with it? That is garbage.
file_modtime_and_size :: (file_path: string) -> (modtime: Apollo_Time, size: s64, file_exists: bool) {
    fs: stat_t;
    result := stat(temp_c_string(file_path), *fs);
    if result != 0 return .{}, 0, false;

    return timespec_to_apollo(fs.st_mtime), fs.st_size, true;
}

atomic_file_replace_or_just_rename_if_destination_file_does_not_exist :: (old_filename: string, new_filename: string) -> bool {
    old_filename_c := temp_c_string(old_filename);
    new_filename_c := temp_c_string(new_filename);

    // @@ To guarantee atomicity we need to do more than this! See implementation in The Witness.

    return rename(old_filename_c, new_filename_c) == 0;
}

is_directory :: (path: string) -> bool, success: bool {
	stats: stat_t;
	ret := stat(temp_c_string(path), *stats);
	if ret != 0		return false, false;
	return S_ISDIR(stats.st_mode), true;
}

#scope_file

// @Cleanup: "POSIX" is huge and beefy and importing it kind of sucks, though
// someone using this probably imports it anyway. But. Should be better.

#import "POSIX";
#import "System";

