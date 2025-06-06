open_find_global_text_dialog :: () {
    using find_global_text_dialog;
    
    if !fgt_input {
        fgt_input = create_text_input(cast(u64, #location()));
    }
    
    if fgt_input.text {
        select_all(fgt_input);
    }

    switch_editor_mode(.WIDGET);
    active_widget = Find_Global_Text_Dialog;

} @EditorCommandUnlisted(editor_keymap)

update_find_global_text_dialog :: () {
    using find_global_text_dialog;

    if fgt_input.typed {
        findstr(fgt_input.text);
    }
}

#scope_file
findstr :: (text: string) {
    using find_global_text_dialog;

    array_reset_keeping_memory(*options);

    if !fgt_input.text return;

    command: [..] string;
    command.allocator = temp;

    array_add(*command, "findstr.exe");
    array_add(*command, "-rsinp");
    array_add(*command, tprint("\"%\"", text));
    array_add(*command, "*.*");

    result, out_str, err_str, timeout_reached := Process.run_command(
        ..command, 
        working_directory=get_workdir(), 
        capture_and_return_output=true, 
        print_captured_output=false,
        arg_quoting=.NEVER_QUOTE,
        timeout_ms=30*1000,
        ,, allocator=temp
    );

    if !timeout_reached && result.type == .EXITED && result.exit_code == 0 {
        normalize_line_endings(*out_str);
        lines := split(out_str, "\n");

        for lines {
            slices := split(it, ":");
            if slices.count < 3 continue;

            file := slices[0];
            path_overwrite_separators(file, #char "/");

            line := string_to_int(slices[1], base=10, u32);

            opt := array_add(*options);
            modify_string(*opt.label, it);
            modify_string(*opt.ref.filepath, file);
            opt.ref.line = line;
        }
    }

}
#scope_export

find_global_text_dialog: Find_Global_Text_Dialog;

Find_Global_Text_Dialog :: struct {
    fgt_input: *Text_Input;

    Result :: struct {
        filepath: string;
        line: u32;
    };

    options: [..] List_Input.Option(Result);
}