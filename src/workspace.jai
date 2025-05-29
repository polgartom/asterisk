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
}

reload_workspace :: () {
    load_global_config();

    // init_keymaps();
    init_fonts();
} @EditorCommand

Workspace :: struct {
    dir: string;
}