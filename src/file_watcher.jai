init_file_watcher :: () {
    success := init(
        *file_watcher,
        file_watcher_change_callback,
        user_data = null,
        events_to_watch = .ALL_EVENTS,
        watch_recursively = true,
        verbose = true,
    );
    
    
    dir := get_workdir();
    log("Adding root folders: %\n", dir);
    if !add_directories(*file_watcher, dir) {
        log_error("Could not watch directories %\n", dir);
        exit(4);
    }
    
    assert(success, "Failed to initialize the file watcher!\n");
}

file_watcher_change_callback :: (watcher: *File_Watcher(string), change: *File_Change, user_data: *string) {
    log("Change for path %: % (user_data points to %)", change.full_path, change.events, <<user_data);
    
    for b: buffers {
        if !b.exists_on_disk continue;
        if change.full_path == b.filepath { // @Speed
            if change.events & .MODIFIED {
                ok, hash := meow_hash_from_file(change.full_path);
                if !ok {
                    log_error("Failed to make meow hash from '%'\n", change.full_path);
                    continue;
                }
                if b.hash != hash {
                    b.disk_state = .modified;
                    b.disk_hash = hash;
                }
            } else if change.events & (.REMOVED | .MOVED) {
                b.disk_state = .removed;
                b.disk_hash = 0;
                b.exists_on_disk = false;
            }
            
        }
    }
}


file_watcher: File_Watcher(string);