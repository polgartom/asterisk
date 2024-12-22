#run {
    format := *context.print_style.default_format_struct;
    format.use_newlines_if_long_form = true;
    format.indentation_width = 2;

    set_build_options_dc(.{do_output = false});
    args := get_build_options().compile_time_command_line;

    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.arithmetic_overflow_check = .FATAL;
    set_optimization(*options, .DEBUG);
    options.output_path = "build";
    options.output_executable_name = "asterisk_devbuild";
    window_name := "Asterisk (dev build)";

    do_optimization := false;

    for arg: args {
        if arg == {
            case "release";
                do_optimization = true;
                set_optimization(*options, .VERY_OPTIMIZED);
                options.llvm_options.enable_split_modules = false;
                options.array_bounds_check = .ON;
                options.null_pointer_check = .ON;
                options.arithmetic_overflow_check = .OFF;
                options.output_executable_name = "asterisk";
                window_name = "Asterisk";
        }
    }

    set_build_options(options, w);

    if do_optimization {
        #if OS == .WINDOWS {
            set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]}, w);
        }
    }    

    check_message := default_check_message;
    is_dummy_compile := false;
    if options.user_data_u64 {
        check_message = <<cast(*type_of(default_check_message)) options.user_data_u64;
        is_dummy_compile = true;
    }

    if !is_dummy_compile {
        // extra work when you're actually building like choosing build mode
        // that we want to skip when we're just using the compiler to parse the
        // codebase.
    }

    compiler_begin_intercept(w);

    add_build_file("src/main.jai", w);
    
    build_constants := tprint(#string STRING
            DEBUG       :: %;
            WINDOW_NAME :: "%";
        STRING,
            ifx do_optimization then "false" else "true",
            window_name
    );
    add_build_string(build_constants, w);

    while true {
        message := compiler_wait_for_message();

        valid, complete := check_message(message);
        if complete  break;
        if !valid    continue;
    }

    compiler_end_intercept(w);
}

default_check_message :: (message: *Message) -> valid: bool, complete: bool {
    if !message return false, false;
    if message.kind == .COMPLETE return false, true;
    return true, false;
}

#import "Compiler";
#import "Basic";