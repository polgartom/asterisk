#run {
    set_build_options_dc(.{do_output = false});
    args := get_build_options().compile_time_command_line;

    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.arithmetic_overflow_check = .FATAL;
    set_optimization(*options, .DEBUG);
    options.output_path = "";
    options.output_executable_name = "asterisk_debug";

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
        }
    }

set_build_options(options, w);

    if do_optimization {
        #if OS == .WINDOWS {
            set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]}, w);
        }
    }    

    compiler_begin_intercept(w);

    add_build_file("src/main.jai", w);
    
    compiler_end_intercept(w);
}

#import "Compiler";
#import "Basic";