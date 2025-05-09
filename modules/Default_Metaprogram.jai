is_absolute_path :: (path: string) -> bool { // This routine is probably not as correct as we'd like. We'd like to put in a better one! But maybe we will stop doing the cwd thing, or do it differently; hard to say.
    if !path return false;

    if path[0] == #char "/" return true;   // Backslashes have not been converted to forward slashes by this point.
    if path[0] == #char "\\" return true;  // Backslashes have not been converted to forward slashes by this point.
    if (path.count > 2) && (path[1] == #char ":") && (OS == .WINDOWS) return true;  // Drive letter stuff. Probably incomplete.

    if path.count >= 3 {
        // @Robustness: Check for a drive letter in character 0?  Anything else?
        if path[1] == #char ":" return true;
    }

    return false;
}

build :: () {
    //
    // Create a workspace to contain the program we want to compile.
    // We can pass a name to compiler_create_workspace that gets reported
    // back to us in error messages:
    //
    w := compiler_create_workspace("Target Program");
    if !w {
        log_error("Workspace creation failed.\n");
        return;
    }

    args := get_build_options().compile_time_command_line;

    options := get_build_options(w);

    do_initial_cwd   := true;
    check_bindings   := true;
    do_check         := true;  // Import modules/Check if true.

    if verbose  print("Arguments:   %\n", args); // @Cleanup: 'verbose' cannot be true yet so this will never fire.

    printed_help    := false;
    printed_version := false;

    // User-processed options will give us entries for either 'files' (files to load)
    // or 'run_strings' (strings to add to the build with #run in front.)
    files:         [..] string;
    add_strings:   [..] string;
    run_strings:   [..] string;
    modules_paths: [..] string;

    plugin_names:  [..] string;
    plugin_names2: [..] string;

    user_arguments: [..] string;

    index := 0;

    //
    // First we do a pass where we scan for -plug arguments, and import those plugins.
    // Why? So that the plugins can handle unknown arguments and the like.
    // Note that it is not strictly correct to scan for -plug since theoretically
    // the string -plug could be an argument to some other option. Even though this isn't
    // realistically a problem, it feels bad, so we at least check for it in pass 2,
    // which is what plugin_names2 is for -- we make sure during pass 2 that we get
    // the same results as pass 1.
    //

    while index < args.count {
        defer index += 1;

        it := args[index];
        if it == {
            case "-plugin"; #through;
            case "-plug";
                if index >= args.count-1 {
                    break;  // Silent. We'll catch this the second time around.
                }

                index += 1;
                array_add(*plugin_names, args[index]);

            case "-ps5";
                array_add(*plugin_names, "ps5_build");

                // We need to know about no_check bindings in pass 1 because that is how we determine if that plugin is in the set! Argh.
            case "-no_check";           do_check = false;
            case "-no_check_bindings";  check_bindings = false;
            case "-check_bindings";     check_bindings = true; // Not necessary anymore since we changed the default. I just left it in for backwards compatibility. -rluba, 2022-03-23
            case "-";  // Do not process anything after -!
                break;
        }
    }

    if do_check {
        if check_bindings array_add(*plugin_names, "Check");
        else              array_add(*plugin_names, "Check(CHECK_BINDINGS=false)");
    }

    // Now that we know what the plugins are, init them.
    init_plugins(plugin_names, *plugins, w);

    //
    // Pass 2: Handle all the various options, or delegate them to plugins
    // if we do not handle them.
    //
    index = 0;  // Starting over!
    got_user_arguments_delimiter := false;
    got_error       := false;

    output_executable_name: string;
    output_path:            string;

    intercept_flags: Intercept_Flags;

    while index < args.count {
        defer index += 1;

        it := args[index];

        if got_user_arguments_delimiter {
            array_add(*user_arguments, it);
            continue;
        }

        if !it continue;  // @Temporary?

        if it[0] == #char "-" {
            if it == {
                case "-";
                    // Everything after this is user arguments.
                    got_user_arguments_delimiter = true;

                case "-release";
                    set_optimization(*options, .OPTIMIZED);
                    options.stack_trace = false;

                case "-very_debug";
                    set_optimization(*options, .VERY_DEBUG);

                case "-no_inline";
                    options.enable_bytecode_inliner = false;
                
                case "-quiet";
                    options.text_output_flags = 0;

                case "-x64";
                    options.backend = .X64;
                case "-llvm";
                    options.backend = .LLVM;

                case "-no_cwd";
                    do_initial_cwd = false;

                case "-no_dce";
                    options.dead_code_elimination = .NONE;

                case "-no_split";
                    options.llvm_options.enable_split_modules = false;

                case "-output_ir";
                    options.llvm_options.output_llvm_ir_before_optimizations = true;
                    options.llvm_options.output_llvm_ir = true;

                case "-debug_for";
                    options.debug_for_expansions = true;

                case "-msvc_format";
                    options.use_visual_studio_message_format = true;

                case "-natvis";
                    options.use_natvis_compatible_types = true;

                case "-no_check";           // nop; we handled this in pass 1.
                case "-no_check_bindings";  // nop; we handled this in pass 1.
                case "-check_bindings";     // nop; we handled this in pass 1.

                case "-no_backtrace_on_crash";
                    options.backtrace_on_crash = .OFF;

                case "-version";
                    s := compiler_get_version_info(null);
                    print("Version: %.\n", s);
                    printed_version = true;

                case "-exe";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -exe.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    output_executable_name = args[index];

                case "-output_path";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -output_path.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    output_path = args[index];

                case "-add";

                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -add.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*add_strings, args[index]);

                case "-run";

                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -run.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*run_strings, args[index]);

                case "-plugin"; #through;
                case "-plug";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to %.\n", it);
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*plugin_names2, args[index]);  // So we can check this later.

                case "-ps5";
                    array_add(*plugin_names2, "ps5_build");

                case "-help"; #through;
                case "-?";
                    log("%", HELP_STRING);

                    printed_help = true;

                case "-debugger";
                    options.interactive_bytecode_debugger = true;
                    set_build_options_dc(.{interactive_bytecode_debugger=true});

                case "-context_size";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -context_size.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;

                    value, success := to_integer(args[index]);
                    if success {
                        CONTEXT_SIZE_MAX :: 0x4_0000;  // This has to be kind of reasonable because people declare Contexts on the stack and so forth...? Also must fit into 32 bits because that is the size of the value in Build_Options.
                        if value > CONTEXT_SIZE_MAX {
                            log_error("Command line: Invalid argument to -context_size. The context must be less than or equal to CONTEXT_SIZE_MAX, which is % (but the value provided was %). The size needs to be reasonable because contexts get declared on the stack, in other structs, and so forth. (If you think you should be able to exceed this limit, you can modify or replace Default_Metaprogram.)\n", CONTEXT_SIZE_MAX, value);
                        } else if value < size_of(Context_Base) {
                            log_error("Command line: Invalid argument to -context_size. The context must be at least as large as size_of(Context_Base), which is %.\n", size_of(Context_Base));
                        } else {
                            options.context_size_max = cast(s32) value;
                        }
                    } else {
                        log_error("Command line: Unable to parse an integer argument to context size; got '%'.\n", args[index]);
                    }
                case "-import_dir";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -import_dir.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*modules_paths, args[index]);

                case "-no_color";
                    options.use_ansi_color = false;

                case "-verbose";
                    verbose = true;

                case;
                    handled := false;
                    for p, plugin_index: plugins {
                        if !p.handle_one_option continue;

                        new_index := p.handle_one_option(p, args, index);
                        if new_index > index {
                            index = new_index - 1;  // -1 Because it will be incremented at the bottom of the loop.
                            handled = true;
                            break;
                        } else if new_index < index {
                            log_error("Plugin % decreased argument index. That is illegal!\n", plugin_names[plugin_index]);
                            got_error = true;
                            break;
                        }
                    }

                    if handled continue;

                    log_error("Unknown argument '%'.\nExiting.\n", it);
                    got_error = true;
                    break;
            }

            continue;
        }

        // If we got here, it's a plain file. Add it to the array.
        array_add(*files, it);
    }

    if got_error {
        exit(1);
    }

    if !(files || add_strings || run_strings) {
        if !(printed_help || printed_version)  log("You need to provide an argument telling the compiler what to compile! Sorry. Pass -help for help.\n");
        if printed_version && !printed_help exit(0);
        if !printed_help exit(1);  // If we printed help, we want to fall through to print help for all the modules, so don't exit yet.
    }

    if do_check { // @Copypasta, just to make the plugin name arrays come out the same. This is getting silly!
        if check_bindings array_add(*plugin_names2, "Check");
        else              array_add(*plugin_names2, "Check(CHECK_BINDINGS=false)");
    }

    plugins_match := true;
    if plugin_names.count != plugin_names2.count  plugins_match = false;
    else {
        for plugin_names if it != plugin_names2[it_index] plugins_match = false;
    }

    if !plugins_match {
        log_error("Plugins in pass 1 and pass 2 do not match, meaning that -plug was used as an argument to another option. This is an error.\n");
        exit(1);
    }

    old_wd := get_working_directory();
    absolute_files: [..] string;
    if files {
        if output_path             options.output_path            = output_path;
        if output_executable_name  options.output_executable_name = output_executable_name;

        array_reserve(*absolute_files, files.count);
        for files {
            absolute_file := it;
            if !is_absolute_path(it) {
                #if OS == .WINDOWS {
                    absolute_file = get_absolute_path(it);
                } else {
                    absolute_file = sprint("%/%", old_wd, it);
                }
            }

            array_add(*absolute_files, absolute_file);
        }

        basename, path := get_basename_and_path(absolute_files[0]);

        if basename || path {
            if path && !output_path {
                options.output_path = path;
                if verbose print("options.output_path = \"%\";\n", path);
            }

            if basename && !output_executable_name {
                options.output_executable_name = basename;
                if verbose print("options.output_executable_name = \"%\";\n", basename);
            }
        }

        if do_initial_cwd && path {
            if verbose  print("Changing working directory to '%'.\n", path);
            set_working_directory(path);
        }
    }

    if printed_help {
        log("\n\n");

        for plugins {
            name := plugin_names[it_index];

            if it.log_help {
                log("---- Help for plugin '%': ----\n\n", name);
                it.log_help(it);
                log("\n");
            } else {
                log("---- Plugin '%' provides no help.\n", name);
            }
        }

        if !(files || run_strings) exit(0);
    }

    if modules_paths {
        prefix := "";
        if files {
            // Because modules_paths are intended to be relative to the source code, but these aren't coming from the
            // source code themselves, we need to tell the compiler where they live. We do this by just prefixing
            // the import_paths with the path to the first source file. This is weird and kind of a hack, but it's unclear
            // what is a better thing to do.
            basename, path := get_basename_and_path(absolute_files[0]);
            if path {
                for * modules_paths if !is_absolute_path(it.*) { it.* = tprint("%0%", path, it.*); }
            }
        }

        array_add(*modules_paths, ..options.import_path);  // Put these behind whatever the user specified.
        options.import_path = modules_paths;
    }

    options.compile_time_command_line = user_arguments;

    // Make a fake location...
    loc: Source_Code_Location;
    loc.fully_pathed_filename = ifx absolute_files then absolute_files[0] else tprint("%/fake_file.fake", old_wd);  // In case someone does a #run that imports stuff but adds no files!

    set_build_options(options, w, loc=loc);

    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);

    // As the compiler builds the target program, we can listen in on messages
    // that report the status of the program. In later examples we can use
    // these messages to do sophisticated things, but for now, we'll just
    // use them to report on the status of compilation.

    // To tell the compiler to give us messages, we need to call compiler_begin_intercept
    // before we add any code to the target workspace.
    compiler_begin_intercept(w, intercept_flags);

    if verbose {
        print("Input files: %\n", absolute_files);
        print("Add strings: %\n", add_strings);
        print("Run strings: %\n", run_strings);
        print("Plugins:     %\n", plugins);
    }
// assert(false);
    for plugins {
        if it.add_source {
            it.add_source(it);
            // print("add source: %\n", it.*);
        }
    }

    for absolute_files {
        add_build_file(it, w);
    }

    for add_strings  add_build_string(tprint("%;", it), w);
    for run_strings  add_build_string(tprint("#run %;\n", it), w); // run_strings is kind of redundant now! We could remove it.

    // Call message_loop(), which is a routine of ours below that will receive the messages.
    message_loop(w);

    // When we're done, message_loop will return.
    // We call compiler_end_intercept to tell the compiler we are done.
    compiler_end_intercept(w);

    for plugins if it.finish   it.finish  (it);
    for plugins if it.shutdown it.shutdown(it);

    {
        // None of the code in this file is intended to end up in an executable
        // of any kind. So, we tell the compiler not to make an executable for us:

        set_build_options_dc(.{do_output=false, write_added_strings=false});
    }
}

#run,stallable build();

//
// message_loop() runs the event loop that reads the messages.
// You can do whatever you want with those messages. The goal
// of this example is just to show the different kinds of messages,
// so we don't do anything crazy yet. But you can do some things
// that are crazy.
//
message_loop :: (w: Workspace) {
    while true {
        // We ask the compiler for the next message. If one is not available,
        // we will wait until it becomes available.
        message := compiler_wait_for_message();
        // Pass the message to all plugins.
        for plugins if it.message it.message(it, message);

        if message.kind == .COMPLETE break;
    }
}

#import "Basic";
#import "File";
#import "Compiler";
#import "Metaprogram_Plugins";


verbose  := false;
plugins: [..] *Metaprogram_Plugin;


HELP_STRING :: #string DONE
Available Command-Line Arguments:

-add arg         Add the string 'arg' to the target program as code.
                 Example: -add "MY_VARIABLE :: 42";
-context_size n  Set the size of #Context, in bytes (you only need this if your program has a really big context).
                 Example: -context_size 2048
-debugger        If there is a crash in compile-time execution, drop into the interactive debugger.
-debug_for       Enable debugging of for_expansion macros. (Otherwise the debugger will never step into them to make stepping through for loops more convenient.)
-exe name        Set output_executable_name on the target workspace to 'name'.
-import_dir arg  Add this directory to the list of directories searched by #import. Can be
                     used multiple times.
-llvm            Use the LLVM backend by default (unless overridden by a metaprogram).
                     The LLVM backend is the default normally, so this isn't too useful.
-msvc_format     Use Visual Studio's message format for error messages.
-natvis          Use natvis compatible type names in debug info (array<T> instead of [] T, etc).
-no_backtrace_on_crash    Do not catch OS-level exceptions and print a stack trace when your program crashes.
                     Causes less code to be imported on startup. Depending on your OS (for example, on Windows),
                     crashes may look like silent exits.
-no_color        Disable ANSI terminal coloring in output messages.
-no_dce          Turn off dead code elimination. This is a temporary option,
                     provided because dead code elimination is a new and potentially
                     unstable feature. This will eventually be removed; the preferred way
                     to turn off dead code elimination is via Build_Options.
-no_split        Disable split modules when compiling with the LLVM backend.
-no_cwd          Turn off the compiler's initial change of working directory. This is a temporary option,
                     provided because the policy around working directories is new and is still
                     being worked out.
-no_check        Do not import modules/Check and run it on the code. The result will be that you won't get
                     augmented error checking for stuff like print() calls. Use this if you want to substitute
                     your own error checking plugin, or for higher speeds in builds known to be good.
-no_check_bindings Disable checking of module bindings when running modules/Check. If modules/Check is not run
                     due to -no_check, this does nothing.
-no_inline       Disable inlining throughout the program (useful when debugging).
-output_path     Set the path where your output files (such as the executable) will go.
-plug name       Import module 'name' into the metaprogram and use it as a plugin.
-quiet           Run the compiler in quiet mode (not outputting unnecessary text).
-release         Build a release build, i.e., tell the default metaprogram to disable stack traces and enable optimizations.
-run arg         Start a #run directive that parses and runs 'arg' as code.
                     Example: -run write_string(\"Hello!\n\")
                     (The extra backslashes are the shell's fault.)
-verbose         Output some extra information about what this metaprogram is doing.
-version         Print the version of the compiler.
-very_debug      Build a very_debug build, i.e. add more debugging facilities than usual, which will cause it to run slower but catch more problems.
-x64             Use the x64 backend by default (unless overridden by a metaprogram).

-                Every argument after - is ignored by the compiler itself,
                     and is passed to the user-level metaprogram for its own use.

Any argument not starting with a -, and before a - by itself, is the name of a file to compile.

Example:    jai -x64 program.jai - info for -the compile_time execution

There are also a few very tweaky compiler-front-end options that almost nobody
will ever care about. To see these, do:

            jai -- help

And that's all.
Unlike most contemporary compilers, we don't have a huge number of arcane arguments
to control all kinds of minute things, that you have to spend a long time learning about.
Our philosophy is, it's much more effective to do configuration from code, where
you have a great deal of precise control over what's happening, options can be expressed
as easy-to-understand data structures, and so forth. To get started, look into Build_Options
in modules/Compiler/Compiler.jai, or look at how_to/400_workspaces.jai and
how_to/420_command_line.jai.

This text is generated by modules/Default_Metaprogram.jai, the code that starts up
when you run the compiler. You can read the text of this file to learn how all this works
(it's pretty simple!); you can make a copy of Default_Metaprogram and modify it
to work however you want.
DONE


