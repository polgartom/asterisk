open_find_global_text_dialog :: () {
    using find_global_text_dialog;
    
    if !fgt_input {
        fgt_input = create_text_input(cast(u64, #location()));
    }

    init_string_builder(*output_builder);
    init_string_builder(*error_builder);

    if fgt_input.text {
        select_all(fgt_input);
    }

    switch_editor_mode(.WIDGET);
    active_widget = Find_Global_Text_Dialog;

} @EditorCommandUnlisted(editor_keymap)

update_find_global_text_dialog :: () {
    using find_global_text_dialog;

    if process {
        output_buffer := ensure_contiguous_space_and_return_available_range(*output_builder);
        error_buffer := ensure_contiguous_space_and_return_available_range(*error_builder);

        success, output_bytes, error_bytes := read_from_process(process, output_buffer, error_buffer, -1);

        if output_bytes {
            advance_through_ensured_space(*output_builder, output_bytes);
        }
        
        if error_bytes {
            advance_through_ensured_space(*error_builder, error_bytes);
        }

        output_string := builder_to_string(*output_builder,, temporary_allocator);
        error_string  := builder_to_string(*error_builder,, temporary_allocator);

        log("[read_from_process]: success: % ; out: % ; err: %\n", success, output_bytes, error_bytes);
        log("[out]:\n\n|%|\n\n", output_string);
        log("[err]:\n\n|%|\n\n", error_string);

        if process.output.eof && process.error.eof {
            success = kill_process(process);
            if !success {
                log_error("Failed to KILL the process!\n");
                return;            
            }

            deinit(process);

            free(process);
            process = null;
        }

        redraw_requested = true;
    }

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

    success: bool;

    if process {
        success = kill_process(process);
        if !success {
            log_error("Failed to KILL the process: %\n", command);
            return;            
        }

        deinit(process);

        free(process);
        process = null;
    }

    process = New(Process);
    success = create_process(process, ..command, get_workdir(), capture_and_return_output=true, .NEVER_QUOTE);
    if !success {
        log_error("Failed to START the process: %\n", command);
        return;
    }

    // result, out_str, err_str, timeout_reached := Process.run_command(
    //     ..command, 
    //     working_directory=get_workdir(), 
    //     capture_and_return_output=true, 
    //     print_captured_output=false,
    //     arg_quoting=.NEVER_QUOTE,
    //     timeout_ms=10*1000,
    //     ,, allocator=temp
    // );

    // if !timeout_reached && result.type == .EXITED && result.exit_code == 0 {
    //     normalize_line_endings(*out_str);
    //     lines := split(out_str, "\n");

    //     for lines {
    //         slices := split(it, ":");
    //         if slices.count < 3 continue;

    //         file := slices[0];
    //         path_overwrite_separators(file, #char "/");

    //         line := string_to_int(slices[1], base=10, u32);

    //         opt := array_add(*options);
    //         modify_string(*opt.label, it);
    //         modify_string(*opt.ref.filepath, file);
    //         opt.ref.line = line;
    //     }
    // }

}
#scope_export

find_global_text_dialog: Find_Global_Text_Dialog;

Find_Global_Text_Dialog :: struct {
    process: *Process;
    output_builder: String_Builder;
    error_builder: String_Builder;
    
    fgt_input: *Text_Input;

    Result :: struct {
        filepath: string;
        line: u32;
    };

    options: [..] List_Input.Option(Result);
}