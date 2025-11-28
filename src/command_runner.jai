init_command_runner :: () {
    thread_group = Thread_Group.{};  // in case we need to reinitialise it later
    
    init(*output_lock);
    
    init(*thread_group, num_threads = 1, group_proc = command_threadproc);
    start(*thread_group);
}

deinit_command_runner :: () {
    shutdown(*thread_group);
}

execute_custom_command :: (buffer: *Buffer, command: string) {
    assert(buffer.kind == .stdout && buffer.readonly);
    
    buffer.stdout_in_progress = true;
    buffer.stdout_stalled = true;
    
    work := New(Custom_Command_Work); // @leak free it!
    work.buffer = buffer;
    modify_string(*work.command, command);
    modify_string(*work.workdir, get_workdir());
        
    add_work(*thread_group, work);
}

command_runner_update :: () {
    output: string;
    output_err: string;

    if current_work {
        lock(*output_lock);
        output = builder_to_string(*stdout, do_reset=true);
        output_err = builder_to_string(*stderr, do_reset=true);
        
        buffer := current_work.buffer;
        
        if current_work.done {
            current_work = null; // @leak
        }
        
        unlock(*output_lock);
               
        insert_text_at_raw(buffer, buffer.count, output);
        insert_text_at_raw(buffer, buffer.count, output_err);
        rescan_line_ends(buffer);
        
        free_string(*output);
        free_string(*output_err);
    }
    
    works := get_completed_work(*thread_group);
    if works {
        for works {
            work := cast(*Custom_Command_Work) it;
            free_string(*work.command);
            defer free(work);
            log("work: %\n", work.*);
        }
    }
}

#scope_file

Custom_Command_Work :: struct {
    buffer: *Buffer;
    workdir: string;
    done: bool;
    command: string;
}

stdout: String_Builder;
stderr: String_Builder;
output_lock: Mutex;

current_work: *Custom_Command_Work;

command_threadproc :: (group: *Thread_Group, thread: *Thread, _work: *void) -> Thread_Continue_Status {
    assert(_work != null);
    
    defer reset_temporary_storage();
    
    work := cast(*Custom_Command_Work)_work;
    assert(!!work.command);
    
    lock(*output_lock);
    current_work = work;
    work.buffer.destroyable = false;
    work.buffer.stdout_stalled = false;
    unlock(*output_lock);
     
    command: [..] string;
    command.allocator = temporary_allocator;
    
    array_add(*command, work.command);

//     
    // // @Temporary
    // #if DEBUG {
        // array_add(*command, "../dwrite_jai/main.exe");
    // } else {
        // array_add(*command, "jai first.jai - autorun");
    // }
    
    KILL_PROCESS_IF_THE_MAIN_PROCESS_DIES :: true;
    process := New(Process);
    success := create_process(process, args=..command, work.workdir, capture_and_return_output=true, .NEVER_QUOTE, kill_process_if_parent_exits = KILL_PROCESS_IF_THE_MAIN_PROCESS_DIES);
    
    eof := false;
    while !eof {
        lock(*output_lock);
        
        stdout_buf := ensure_contiguous_space_and_return_available_range(*stdout);
        stderr_buf := ensure_contiguous_space_and_return_available_range(*stderr);
        
        INFINITE :: -1;
        timeout_ms := 5;
        success, output_bytes, error_bytes := read_from_process(process, stdout_buf, stderr_buf, timeout_ms);
        eof = (process.output.eof && process.error.eof) || !success;
        
        if output_bytes {
            advance_through_ensured_space(*stdout, output_bytes);
        }
        
        if error_bytes {
            advance_through_ensured_space(*stderr, error_bytes);
        }
    
        // ll("success: % ; out: % ; err: % ; eof: %\n", success, output_bytes, error_bytes, eof);
        
        unlock(*output_lock);
        sleep_milliseconds(10);
    }
    
    {
        success := kill_process(process);
        deinit(process);
        free(process);
    }
    
    log("stop..\n");
    
    lock(*output_lock);
    work.buffer.stdout_in_progress = false;
    work.buffer.destroyable = true;
    work.done = true;
    unlock(*output_lock);
    
    return .CONTINUE;
}

thread_group: Thread_Group;