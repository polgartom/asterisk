// Simple utilities for manipulating files and their contents.

#load "path.jai";    // Functions for manipulating file paths.

// Inside these OS-specific files are:

/*

visit_files :: (dir_name: string, recursive: bool, user_data: $T, proc: (info: *File_Visit_Info, user_data: T), visit_files := true, visit_directories := false, visit_symlinks := true, follow_directory_symlinks := true) -> bool;

file_exists :: (file_path: string) -> bool;

// We encourage you to use both modtime and size, rather than
// just modtime, to determine whether a file has changed, because
// modification time by itself is not particularly reliable; there are
// all kinds of reasons it can be changed, or left unchanged while
// file contents are changed.

file_modtime_and_size :: (file_path: string) -> (modtime: Apollo_Time, size: s64, success: bool);


// This atomic_file_replace* routine is meant to be used for state-save-file kinds of things,
// where you have an old state, want to save a new state, but don't want to destroy the old
// state if something goes wrong saving the new state (like the power goes out, the computer
// crashes, etc). The intended use is, you save the old state to some other file, and when
// that is completely done, you call this.
atomic_file_replace_or_just_rename_if_destination_file_does_not_exist :: (old_filename: string, new_filename: string) -> bool;

*/

// @Cleanup: The File_Visit_Info passed to 'proc' should probably not be by pointer!

#if OS == .WINDOWS  {
    #load "os/windows.jai";
} else #if OS == .PS5 {
    #load "os/ps5.jai";
} else #if OS_IS_UNIX {
    #load "os/unix.jai";
}

copy_directory :: (source: string, dest: string) {
    names: [2] string;
    names[0] = source;
    names[1] = dest;

    visitor :: (info: *File_Visit_Info, names: [2]string) {
        dest_name := advance(info.full_name, names[0].count);
        dest_name = join(names[1], dest_name);
        if info.is_directory {
            make_directory_if_it_does_not_exist(dest_name);
        } else {
            copy_file(info.full_name, dest_name);
        }
    }

    make_directory_if_it_does_not_exist(dest);
    visit_files(source, true, names, visitor, visit_directories = true);
}

file_list :: (path: string, recursive := false, follow_directory_symlinks := true) -> [] string #must {
    files : [..] string;

    visitor :: (info: *File_Visit_Info, user_data: *[..] string) {
        array_add(user_data, copy_string(info.full_name));
    }

    visit_files(path, recursive, *files, visitor, follow_directory_symlinks=follow_directory_symlinks);

    return files;
}

// File_Visit_Info is the struct given to your callback when you call visit_files().
File_Visit_Info :: struct {
    short_name:   string;
    full_name:    string;

    // 'filetime' member has been removed. It was not a very good name, or data type.
    modification_time:  Apollo_Time;

    had_error:    bool; // Whether there was an error when we tried to get all necessary information about the file (eg. due to insuficient perimssions).
    is_symlink:   bool;
    is_directory: bool;

    descend_into_directory: bool;  // Can be modified by the visit procedure to indicate that we shouldn't go into this directory.
}

#scope_module

#import "Basic";
#import "File";
#import "String";
