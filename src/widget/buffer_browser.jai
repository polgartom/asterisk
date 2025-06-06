open_buffer_browser :: () {
    using buffer_browser;

    if bb_text_input {
        select_all(bb_text_input);
    } else {
        bb_text_input = create_text_input(cast(u64)#location());
    }

    array_reset_keeping_memory(*options);
    array_reserve(*options, buffers.count);

    wd := get_workdir();

    for b: buffers {
        if !b.initialized continue;

        title := "* New *";
        if b.exists_on_disk {
            assert(!!b.filepath);

            title = b.filepath;
            if begins_with(title, wd) {
                advance(*title, wd.count);
            }
        } else if b.name {
            title = b.name;
        }

        opt := array_add(*options);
        opt.ref = b;
        modify_string(*opt.label, title);
        
        if !b.readonly opt.priority = 1; // prioritize the non-scratch buffers
    }

    update_visible_options(*buffer_browser);

    switch_editor_mode(.WIDGET);
    active_widget = Buffer_Browser;

} @EditorCommandUnlisted(editor_keymap)

update_visible_options :: (using browser: *Buffer_Browser) {
    assert(bb_text_input != null);
    tinp := bb_text_input;
    
    array_reset_keeping_memory(*visible_options);
    array_reserve(*visible_options, options.count);

    for opt: options {
        if tinp.text {
            found, rem := contains_nocase(opt.label, tinp.text);
            if !found continue;
        }

        array_add(*visible_options, opt);
    }
    
    quick_sort(visible_options, (a, b) => cast(s64) ((b.priority) - (a.priority)));
}

buffer_browser: Buffer_Browser;

Buffer_Browser :: struct {
    search_text: string;

    options: [..] List_Input.Option(*Buffer);
    visible_options: [..] List_Input.Option(*Buffer);

    bb_text_input: *Text_Input;
}