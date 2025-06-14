init_workspace :: (w: *Workspace, dir_: string) {
    dir := dir_;
    if !dir {
        dir = get_working_directory();
    }

    if !is_directory(dir) {
        log_error("Unable to locate the given workspace directory's absolute location (%), so we use the current working direcoty.\n", dir);
        dir = get_working_directory();
        assert(is_directory(dir), "%\n", dir);
    }

    dir = File.get_absolute_path(dir); // using temp alloc
    path_unify_sepa(dir);
    modify_string(*w.dir, dir);

    set_working_directory(dir);

    print("[Workspace]: Working dir: '%'\n", w.dir);

    load_global_config();

    {
        using w;
    
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

    if w.watcher {
        deinit(w.watcher);
        free(w.watcher);
    }

    w.watcher = New(File_Watcher(void));
    start_file_watcher(w.watcher);
}

ReloadWorkspace :: () {
    init_workspace(*workspace, workspace.dir);
} @EditorCommand
 
workspace: Workspace;

Workspace :: struct {
    watcher: *File_Watcher(void);

    dir: string;

    files: Table(string, bool);
    paths: Table(string, bool);
    exclude: Table(string, bool);

    DEFAULT_FILES    :: string.[];
    DEFAULT_PATHS    :: string.[];
    DEFAULT_EXCLUDE :: string.[".git", ".vs", ".vscode", ".idea", "vendor", "node_modules"];
}

#scope_file

#import "Flat_Pool";