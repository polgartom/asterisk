init_workspace :: (using w: *Workspace, new_dir_: string) {
    new_dir := new_dir_;

    if !new_dir || !is_directory(new_dir) {
        log_error("Unable to locate the given workspace directory's absolute location (%), so we use the current working direcoty.\n", new_dir);
        new_dir = get_working_directory();
    }

    new_dir = File.get_absolute_path(new_dir,, temp); // using temp alloc
    modify_string(*dir_os, new_dir);
    
    modify_string(*dir, new_dir);
    path_unify_sepa(dir);

    set_working_directory(dir_os);

    print("[Workspace]: Working dir: '%'\n", dir);

    load_global_config();

    {
        for files   free_string(*it_index);
        for paths   free_string(*it_index);
        for exclude free_string(*it_index);
    
        table_reset(*files);
        table_reset(*paths);
        table_reset(*exclude);
        
        load_project_config();
        
        if files.count == 0   for DEFAULT_FILES table_add(*files, copy_string(it), true);
        if paths.count == 0   for DEFAULT_PATHS table_add(*paths, copy_string(it), true);
        if exclude.count == 0 for DEFAULT_EXCLUDE table_add(*exclude, copy_string(it), true);
    }    

    init_keymaps();
    init_fonts();

    if watcher {
        deinit(watcher);
        free(watcher);
    }

    watcher = New(File_Watcher(void));
    start_file_watcher(w.watcher);
}

ReloadWorkspace :: () {
    init_workspace(*workspace, workspace.dir);
} @EditorCommand

workspace: Workspace;

Workspace :: struct {
    watcher: *File_Watcher(void);

    dir: string;
    dir_os: string;

    files: Table(string, bool);
    paths: Table(string, bool);
    exclude: Table(string, bool);

    DEFAULT_FILES    :: string.[];
    DEFAULT_PATHS    :: string.[];
    DEFAULT_EXCLUDE :: string.[".git", ".vs", ".vscode", ".idea", "vendor", "node_modules"];
}

#scope_file

#import "Flat_Pool";