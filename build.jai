#run {
    has_argument :: (argument: string) -> bool #expand {
        for arg: `args  if arg == argument return true;
        return false;
    }

    format := *context.print_style.default_format_struct;
    format.use_newlines_if_long_form = true;
    format.indentation_width = 2;

    set_build_options_dc(.{do_output = false});
    args := get_build_options().compile_time_command_line;

    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.array_bounds_check = .ON;
    options.null_pointer_check = .ON;

    options.output_path = "build";
    window_name         := "Asterisk"; // We can specify a version number

    do_optimization := false;
    use_baked_font  := false;

    if has_argument("release") {
        // Release build
        
        options.output_executable_name = "asterisk";

        do_optimization = true;

        // @Investigate WTF? The row_table gentime is faster on the .X64 backend!!
        options.backend = .LLVM;
        options.llvm_options.enable_split_modules = false;
        
        set_optimization(*options, .VERY_OPTIMIZED);
        options.arithmetic_overflow_check = .OFF;

    } else {
        // Development build
        window_name = "Asterisk (devbuild)";
        options.output_executable_name = "devbuild";

        do_optimization = false;
        
        options.backend = .X64;

        set_optimization(*options, .VERY_DEBUG);
        options.arithmetic_overflow_check = .FATAL;
    }

    if has_argument("bake_font") {
        use_baked_font = true;
        log("[BUILD] We will bake the font, see my_init_fonts() in main.jai\n");
    }

    log("\n");

    set_build_options(options, w);

    if do_optimization {
        #if OS == .WINDOWS {
            set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]}, w);
        }
    }    

    compiler_begin_intercept(w);

    add_build_file("src/main.jai", w);
    
    build_constants := tprint(#string STRING
            DEBUG           :: %;
            USE_BAKED_FONT  :: %;
            WINDOW_NAME     :: "%";
        STRING,
            ifx do_optimization then "false" else "true",
            ifx use_baked_font  then "true"  else "false",
            window_name,
    );
    
    add_build_string(build_constants, w);

    while true {
        message := compiler_wait_for_message();

        if message.kind == {
            case .PHASE;
                phase := cast(*Message_Phase) message;
                if phase.phase == .POST_WRITE_EXECUTABLE {
                    set_icon(message);
                }
            case .COMPLETE;
                break; // Exit from the compiler's message loop
        }

        // Visual Studio
        // Project_Generator.process_message(message);
    }

    compiler_end_intercept(w);
}

set_icon :: (message: *Message) {
    // Wait for a post_write_executable message. Then we
    // modify the executable by writing the icon to it.

    assert(message.kind == .PHASE);
    phase := cast(*Message_Phase) message;
    assert(phase.phase == .POST_WRITE_EXECUTABLE);

    exe_filename := tprint("%/%", get_build_options(message.workspace).output_path, phase.executable_name);
    
    #if OS == .WINDOWS {
        #import "Windows_Resources";
        success := set_icon_by_filename(exe_filename, ICON_FILEPATH);
        if !success {
            log_error("\n\n[Icon] Failed to set the icon for exe '%' to filename '%'.\n\n", exe_filename, ICON_FILEPATH);
        }
    }
}

ICON_FILEPATH :: "data/icon/icon.ico";

// #import "Project_Generator";
#import "Compiler";
#import "Basic";
#import "Metaprogram_Plugins";