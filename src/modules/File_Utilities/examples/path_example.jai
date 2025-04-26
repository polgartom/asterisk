

main :: () {

    set_working_directory(#filepath);  // So it doesn't matter where you run this from. It is hardcoded to report facts about the file tree located next to this source file.
    
    {
        print("\n--- String to Path and Back: ---\n");
        
        // Start with a path written as a string, decompose it into a Path,
        // then recompose it into a string:
        s := "https://zombo.com/the/only/limit/is/your/imagination.txt";
        print("s:  %\n", s);

        path1 := parse_path(s);

        print("path1: %\n", path1);

        s1 := path_to_string(path1);

        print("s:  %\n", s);
        print("s1: %\n", s1);

        print("s1 == s: %\n", s1 == s);
    }

    {
        print("\n--- Reduction to Canonical Path: ---\n");
        
        // Start with a path written as a string, decompose it into a Path,
        // with reduction turned on (which is actually the default, it's just
        // that the string in the previous example didn't require any reduction).

        s := "c:/a/b/c/./.././d/./////e/../../f/g.txt";
        path := parse_path(s);   // Parse_path's "reduce" argument defaults to true, which means, clean up the path.
        t := path_to_string(path);

        print("s: %\n", s);
        print("t: %\n", t);
    }

    {
        print("\n--- Path Contains Path: ---\n");

        t := "a/lovely";
        print("The sub-path is: %\n", t);
        sub_path := parse_path(t);
        
        path_strings :: string.[ "what/a/lovely/pizza/pie",
                                 "https://hello/sailor/a/love/of/a/lovely/day/is/lovely",
                                 "a/lovely/a/lovely/thing",  // We only detect the first sub-path.
                                 "c:/a/b/c/d/e/lovely/a/g" ];


        for path_strings {
            print("Input path: %\n", it);

            path := parse_path(it);
            contains, position := path_contains(path, sub_path.words);
            if contains {
                print("It contains the sub-path, starting at index %.\n", position);
            } else {
                print("It does not contain the sub-path.\n");
            }
        }
    }
    
    {
        print("\n--- Expansion of Sub-Paths: ---\n");

        // Here we'll do ~ expansion, which is an OS-specific thing...
        
        path_strings :: string.[ "~jon/jai/main.cpp",
                                 "~jeffr/lib/rr_sprintf.c",
                                 "~tim_apple/secret_plans/how_to_make_uis_even_worse_in_2021.ppt",
                                 "/usr/local/bin/escape_from_tarkov.uml" ];


        lookup_home_directory_from_username :: (username: string) -> string {
            // Just pretend this is a real function.

            if username == "jon"    return "/home/jon";
            if username == "jeffr"  return "/var/local/home_directories/on_the_drobo/jeffr";

            return "";  // Unknown!
        }

        for path_strings {
            path := parse_path(it);  // This does cleanup.

            result: string;
            success: bool;
            if path.words && path.words[0] && path.words[0][0] == #char "~" {
                // Expand the ~, which indicates the user's home directory.
                username := advance(path.words[0], 1);

                home_string := lookup_home_directory_from_username(username);
                if home_string {
                    home_path := parse_path(home_string);

                    // Let's just append the rest of 'path' onto home_path.
                    new_words: [..] string;
                    array_add(*new_words, ..home_path.words);
                    for 1..path.words.count-1  array_add(*new_words, path.words[it]);
                    
                    home_path.trailing_slash = path.trailing_slash;
                    home_path.words          = new_words;

                    result = path_to_string(home_path);
                    success = true;
                } else {
                    log_error("Unknown username '%'. Maybe that person was fired from the company.", username);
                    result = it;  // Just punt and return the same path we got.
                    success = false;
                }
            } else {
                // If no ~ in the first slot, we don't need to substitute. Just return the input.
                result = it;
                success = true;
            }

            print("Input:  %\n", it);
            print("Result: %\n", result);
            print("Success: %\n", success);
        }
    }

    {
        // Throughout history, many programmers and users of computers would suffer
        // an almost-uncountable number of hours of frustrating wasted time, when they would
        // type in a filename into some program and would get "file not found" error, but
        // the program would not help them understand WHY the file was not found, like wtf
        // is going on, it sure looks to me like it's correct, what the hell.

        // Then once upon a time, unlikely champion of UIs, Intel Corporation, released a
        // program called VTune that, when you got a path wrong, would actually highlight
        // the portion of the path that was correct, and the portion that was wrong, as you typed it,
        // interactively, so you could see wtf the problem was. This saved much time and
        // avoided many gray hairs, and there was much rejoicing ...

        // ... among people who used VTune only. Because even though this was obviously
        // a great thing, apparently nobody in the world who is in charge of programming
        // computers cares about you or wants you to succeed in life, so they all just
        // keep giving you the sucky UI that makes you grow old while hating computers.

        // It is a complete embarrassment, for example, that open source people think
        // they are making reasonable UIs, but this is not a thing that happens everywhere.
        // But of course it doesn't, because open source people cannot design anything new,
        // they can only copy Windows or the Mac, and neither Windows or the Mac have
        // done this either.

        // It has been suggested that it might be better to search backwards, for example,
        // a/b/c/d, then a/b/c, then a/b, etc, in case you do not have access to a or whatever,
        // but, it's not clear to me in what cases this would apply. But it's an option.
        // e.g. firefox0067 says, "NTFS supports traverse checking bypass, so you can be granted
        // access to the subfolder but not the parent."
        
        // Here we will demonstrate in simple fashion how to do the VTune thing.

        print("\n--- How Much Exists: ---\n");

        input_paths :: string.[ "path_example_data/alpha/beta/gamma/delta/bravo.txt",
                                "path_example_data/alpha/beta/game/delta/bravo.txt",
                                "path_example_data/alpha/beta/game/engine/secrets.txt" ];

        for input: input_paths {
            path := parse_path(input, false);  // Do not canonicalize the path on parsing, because we maybe want to line this up with the original input.

            print("\n");
            print("..................\n");
            defer print("..................\n");
            print("Input Path: %\n", input);
            fully_exists, how_much_exists := how_much_of_path_exists_on_the_local_filesystem(path);
            if fully_exists {
                print("'%' fully exists.\n", input);
            } else {
                print("\n");
                
                partial := path;
                partial.words.count = how_much_exists;
                partial_string := path_to_string(partial);
                print("This much exists: %\n", partial_string);

                remainder: Path;
                remainder.trailing_slash = path.trailing_slash;
                
                remainder_words := path.words;
                remainder_words.data += how_much_exists;
                remainder_words.count -= how_much_exists;
                
                remainder.words = remainder_words;
                remainder_string := path_to_string(remainder);
                print("Therefore this much does not exist: %\n", remainder_string);

                print("This could be hilit, or in red or something, and you would save millions of accumulated user-hours in a brief time. You would be the hero of humanity.\n");

                print("For example (I hope your console supports color!):\n");
                print_color("%/",  partial_string,   color=.GREEN);
                print_color("%\n", remainder_string, color=.RED);
                
                // In the third path, the reason we can't keep going is because "engine" is a plain file,
                // but we are trying to go through it like a directory. A good version of this code would
                // tell users why they can't go -- the program doesn't have permission to open a certain
                // directory name, or that directory name doesn't exist, or, this is a file, not a directory.
                // We could approximate that here by highlighting the file differently, but, this is an example,
                // and the more real functionality you put into an example, the more you obfuscate the point
                // it is trying to show, which here is, just how to do this basic kind of thing.
            }
        }
    }

    
    {
        print("\n--- Long-Term Path Storage: ---\n");

        // As mentioned in the comments in modules/Path, the Path data structure is meant to be manipulated
        // while you have a temporary or pool allocator pushed. It does not perform internal accounting
        // over its memory, so you should manipulate it in a regime where such accounting is not necessary.

        // But if you are manipulating paths in termporary storage, for example, at some point you might
        // want to keep the result for a long time, after that storage is cleared. For these purposes
        // you can use copy_to_permanent() and free_permanent().

        piece_a := "/usr/local/windows/Program Files (x87)/WoW64";
        piece_b := "steamapps/common/Dungeon Warfare 2";

        temporary_result: Path; // So our temporary path can be visible after the scope closes.
        {
            push_allocator(temp);  // This macro in Basic makes temporary_allocator active until the scope closes.
            path_a := parse_path(piece_a);
            path_b := parse_path(piece_b);

            // Copy path_a.
            temporary_result = path_a;

            // Append path_b.
            array_add(*temporary_result.words, ..path_b.words);
            temporary_result.trailing_slash |= path_b.trailing_slash;

            print("Temporary path: %\n", temporary_result);
        }

        // temporary_result still exists; our temporary allocator does not free things
        // when the scope closes, but rather, sometime later in program execution.
        permanent_result := copy_to_permanent(temporary_result);
        
        s := path_to_string(permanent_result);
        defer free(s);  // The temporary allocator was no longer pushed, so we must free s!

        print("Output path: %\n", s);

        // Our program can run a long time and use long_term_result just fine.
        // Then when we are done, we free it:
        
        free_permanent(permanent_result);
    }
}


#import "Basic";
#import "File_Utilities";
#import "Print_Color";
