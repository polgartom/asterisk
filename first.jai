build :: () {    
    format := *context.print_style.default_format_struct;
    format.use_newlines_if_long_form = true;
    format.draw_type_name = true;
    format.indentation_width = 2;

    //~

    release_build := false;
    window_name := "Asterisk";
    
    // User-processed options will give us entries for either 'files' (files to load)
    // or 'run_strings' (strings to add to the build with #run in front.)
    files:         [..] string;
    add_strings:   [..] string;
    modules_paths: [..] string;

    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace("Target Program");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_path = "build";
    options.output_type = .EXECUTABLE;

    options.array_bounds_check = .ON;
    options.null_pointer_check = .ON;

    metaporgram_args := get_build_options(-1).compile_time_command_line;
    for arg: metaporgram_args {
        if arg == {
            case "release"; {
                release_build = true; 
            }
        }    
    }

    if release_build {
        options.backend = .LLVM;
        options.llvm_options.enable_split_modules = false;
        options.arithmetic_overflow_check = .OFF;
        set_optimization(*options, .VERY_OPTIMIZED);

        #if OS == .WINDOWS {
            // Prevent to run the console, we just want the window
            set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]}, w);
        }

        options.output_executable_name = "asterisk";

    } else {
        options.backend = .X64;
        options.arithmetic_overflow_check = .FATAL;
        set_optimization(*options, .VERY_DEBUG);
        options.output_executable_name = "devbuild";

        window_name = "Asterisk (devbuild)";
    }

    set_build_options(options, w);
    
    compiler_begin_intercept(w);

    build_constants := tprint(#string STRING
            DEBUG           :: %;
            WINDOW_NAME     :: "%";
            USE_BAKED_FONT  :: true; 
        STRING,
            ifx release_build then "false" else "true",
            window_name,
    );
    
    add_build_string(build_constants, w);
    add_build_file("./src/main.jai", w);

    while true {
        message := compiler_wait_for_message();

        for plugins if it.message it.message(it, message);

        if message.kind == {
            case .FILE;
                msg := cast(*Message_File) message;
            case .PHASE;
                msg_phase := cast(*Message_Phase) message;
                phase := msg_phase.phase;
                if phase == {
                    case .TYPECHECKED_ALL_WE_CAN;
                    case .POST_WRITE_EXECUTABLE;
                        // set_icon(message);
                }

            case .COMPLETE;
                break; // Exit from the compiler's message loop
        }

    }

    compiler_end_intercept(w);
}

#run,stallable build();

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

plugins: [..] *Metaprogram_Plugin;
verbose := false;

ICON_FILEPATH :: "data/icon/icon.ico";

#load "src/common.jai";

String :: #import "String";
#import "Compiler";
#import "Basic";
#import "Metaprogram_Plugins";