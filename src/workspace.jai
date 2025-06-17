init_workspace :: (using w: *Workspace) {
    // new_dir = File.get_absolute_path(new_dir,, temp); // using temp alloc

    // print("[Workspace]: Working dir: '%'\n", dir);

    // {
    //     for files   free_string(*it_index);
    //     for paths   free_string(*it_index);
    //     for exclude free_string(*it_index);
    
    //     table_reset(*files);
    //     table_reset(*paths);
    //     table_reset(*exclude);
        
    //     load_project_config();
        
    //     if files.count == 0   for DEFAULT_FILES table_add(*files, copy_string(it), true);
    //     if paths.count == 0   for DEFAULT_PATHS table_add(*paths, copy_string(it), true);
    //     if exclude.count == 0 for DEFAULT_EXCLUDE table_add(*exclude, copy_string(it), true);
    // }    

    // if watcher {
    //     deinit(watcher);
    //     free(watcher);
    // }

    // watcher = New(File_Watcher(void));
    // start_file_watcher(w.watcher);
}

ReloadEditor :: () {
    load_global_config();
    load_project_config();
    init_workspace(*workspace);

    init_fonts();

} @EditorCommand

workspace: Workspace;

Workspace :: struct {
    // watcher: *File_Watcher(void);
}

#scope_file

#import "Flat_Pool";