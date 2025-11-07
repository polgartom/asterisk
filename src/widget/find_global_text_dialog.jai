open_find_global_text_dialog :: () {
    using find_global_text_dialog;
    
    if !fgt_input {
        fgt_input = create_text_input(cast(u64, #location()));
    }

    fgt_list_input_ui_id = cast(u64, #location());
    
    reset_list_input(find_global_text_dialog);

    init_string_builder(*output_builder);
    init_string_builder(*error_builder);

    if fgt_input.text {
        select_all(fgt_input);
    }

    switch_editor_mode(.WIDGET);
    active_widget = Find_Global_Text_Dialog;

    {
        anim: Anim;
        anim.active = true;
        anim.start  = 0.0;
        anim.target = 1.0;
        anim.duration = .08;
        anim.started_at = frame_time64;
        
        open_animation = anim;
    }    

}

close_find_global_text_dialog :: () {
    using find_global_text_dialog;
    
    if process {
        assert(kill_find_process(), "Failed to kill the find process!\n");
    }
    
    switch_editor_mode(.EDITOR);
}

update_find_global_text_dialog :: () {
    using find_global_text_dialog;

    if fgt_input.typed {
        start_find_process(fgt_input.text);
    } else if process {
        success, eof, output_string, error_string := read_find_process();
        if success {
            if (error_string.count) {
                log_error("PROCESS STDERR:\n%\n", error_string);
            }
            output_string_to_options(output_string, eof);
        }
    }
}

reset_list_input :: (using dialog: Find_Global_Text_Dialog) {
    list_input := find_or_create_list_input(fgt_list_input_ui_id);
    list_input.scroll_value = 0.0;
    list_input.selected_index = 0;
}

#scope_file

output_string_to_options :: (out_str: string, eof: bool) {
    using find_global_text_dialog;
    
    if !out_str.count return;

    remainder := join(parser_buffer, out_str, separator="",, temp);
    while remainder {
        found, left, right := split_from_left(remainder, #char "\n");

        if found {
            remainder = right;
        } else {
            if eof {
                remainder = "";
            } else {
                break;
            }
        }

        line := trim(left);
        replace_chars(line, "\r\t", #char " ");
        slices := split(line, ":",, temp);
        if slices.count < 3 continue;

        file := slices[0];
        if !file {
            log_error("The slices[0] is empty! How??\n");
            continue; // Crash ???
        }
        
        //line_no := slices[1];
        path_overwrite_separators(file, #char "/");

        opt := array_add(*options);
        modify_string(*opt.label, line);
        
        {
            using opt.label_styled;
            
            array_reset_keeping_memory(*colors);
            array_reserve(*colors, line.count);
            colors.count = line.count;
            memset(colors.data, cast(u8)Color.TEXT_DEFAULT, colors.count);
        
            offset := find_index_from_left_nocase(line, fgt_input.text);
            if offset != -1 {
                for offset..min(offset + fgt_input.text.count, line.count)-1 {
                    colors[it] = .COLOR_GREEN;
                }
            }
        }
        
        modify_string(*opt.ref.filepath, file);
        opt.ref.line_number = string_to_int(slices[1], base=10, u32);
    }

    if !eof {
        if remainder {
            modify_string(*parser_buffer, remainder);
        }
    }

    #if DO_VERBOSE ll("options created from the output string!\n");
}

start_find_process :: (text: string) {
    using find_global_text_dialog;

    array_reset_keeping_memory(*options);

    if parser_buffer {
        free(parser_buffer);
        parser_buffer.count = 0;
    }

    if text.count < 3 return;

    command: [..] string;
    command.allocator = temp;

    #if 0 {
        // rg -n -i -F "<search>" ^
        //   --no-ignore --color=never ^
        //   --glob '!{.git/**,.vscode/**,.build/**,data/**,*.exe,*.pdb,*.rdi}' ^
        //   --glob '!**' ^
        //   --glob '{*.jai,*.txt,*.bat,*.sh,*.cfg,*.md,*Makefile}'

        {
            // @Todo: The pattern thing is temporary solution!

            array_add(*command, "rg.exe --no-heading --no-ignore --color=never");
            array_add(*command, tprint("-n -i -F '%'", text));

            if config.ignore {
                list: [..] string;
                for config.ignore {
                    s := it;
                    if !contains_any_character(s, "?*") s = tprint("%/**", it); // probably is a directory so make it glob pattern compatible, like '.git' -> '.git/**'
                    
                    array_add(*list, s);
                }    

                list_string := join(..list, separator=",",, temp);
                array_add(*command, tprint("--glob '!{%}'", list_string));
            }

            if config.allow {
                // array_add(*command, "--glob '!**'"); // If we want to allow thing explicitly we have to put this pattern between them - it is ignores all files

                list: [..] string;
                for config.allow {
                    s := it;
                    if !contains_any_character(s, "?*") s = tprint("%/**", it); // probably is a directory so make it glob pattern compatible, like '.git' -> '.git/**'
                    
                    array_add(*list, s);
                }    

                list_string := join(..config.allow, separator=",",, temp);
                array_add(*command, tprint("--glob '{%}'", list_string));
            }

            cmd := join(..command, separator=" ");
            array_reset_keeping_memory(*command);
            array_add(*command, cmd);
        }

    } else {
        array_add(*command, "findstr.exe");
        array_add(*command, "-N"); // Prints the line number before each line that matches.
        array_add(*command, "-S"); // Searches for matching files in the current directory and all subdirectories.
        array_add(*command, "-I"); // Specifies that the search is not to be case-sensitive.
        array_add(*command, "-P"); // Skip files with non-printable characters.

        array_add(*command, "-L"); // Uses search strings literally.
        // array_add(*command, "-R"); // Uses search strings as regular expressions.
        array_add(*command, tprint("-C:\"%\"", text));

        // Specify the pattern based on the project config file.
        // array_add(*command, "src/** modules/**");
        // array_add(*command, "src/** *.jai *.bat *.txt *.md");
        // array_add(*command, "app/**");
        // array_add(*command, "resources/**");
        // array_add(*command, "-D:.");

        if config.allow {
            for config.allow {
                array_add(*command, it);
            }
        } else {
            array_add(*command, "*.*");
        }

    }

    if process {
        reset(*output_builder);
        reset(*error_builder);

        assert(kill_find_process() == true);
    }

    //ll(">> %\n", command);

    process = New(Process);
    success := create_process(process, args=..command, get_workdir(), capture_and_return_output=true, .NEVER_QUOTE, kill_process_if_parent_exits = false);
    if !success {
        log_error("Failed to START the process: %\n", command);
        return;
    }

    redraw_requested = true;

    #if DO_VERBOSE ll("process created!\n");
}

read_find_process :: () -> success: bool, eof: bool, output_string: string, error_string: string {
    using find_global_text_dialog;
    assert(process != null);

    redraw_requested = true;

    output_buffer := ensure_contiguous_space_and_return_available_range(*output_builder);
    error_buffer := ensure_contiguous_space_and_return_available_range(*error_builder);

    INFINITE :: -1;
    timeout_ms := 5;
    success, output_bytes, error_bytes := read_from_process(process, output_buffer, error_buffer, timeout_ms);

    if output_bytes {
        advance_through_ensured_space(*output_builder, output_bytes);
    }
    
    if error_bytes {
        advance_through_ensured_space(*error_builder, error_bytes);
    }

    eof := process.output.eof && process.error.eof;
    #if DO_VERBOSE ll("success: % ; out: % ; err: % ; eof: %\n", success, output_bytes, error_bytes, eof);
    
    if !success || eof kill_find_process();

    output_string := builder_to_string(*output_builder, do_reset=true,, temp);
    error_string  := builder_to_string(*error_builder, do_reset=true,, temp);

    // ll("out: %\n\n", output_string);
    // ll("err: %\n\n", error_string);

    return success, eof, output_string, error_string;
}

kill_find_process :: () -> bool {
    using find_global_text_dialog;
    assert(process != null);

    success := kill_process(process);
    if !success {
        log_error("Failed to KILL the process: %\n");
        return false;
    }

    deinit(process);

    free(process);
    process = null;

    #if DO_VERBOSE ll("killed!\n");

    return true;
}

DO_VERBOSE :: false;

#scope_export

find_global_text_dialog: Find_Global_Text_Dialog;

Find_Global_Text_Dialog :: struct {
    process: *Process;
    
    output_builder: String_Builder;
    error_builder: String_Builder;
    
    parser_buffer: string;

    Result :: struct {
        filepath: string;
        line_number: u32;
    };

    fgt_input: *Text_Input;
    fgt_list_input_ui_id: u64 = 0;
    options: [..] List_Input.Option(Result);
    
    open_animation: Anim;
}