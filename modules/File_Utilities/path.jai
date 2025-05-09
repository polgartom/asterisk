
//
// Here are some routines to treat a path as an array of folder/filenames.
// Often people will operate on paths with regexps, but this is messy and
// weakly typed. This gives you a more-strongly-typed way of doing things.
//

// It is meant that you push a Pool allocator, a temporary allocator, or
// something like that before calling these routines. parse_path points at
// substrings of the input string, reduce_path points at its input strings,
// and so forth; we don't copy strings all over the place, and don't necessarily
// return a data structure where you could iterate over individual strings
// and free them.

// Because these routines do not have to account for who owns what piece of
// memory, you can assign one path to another just using operator =
// (which in this language is a memory copy that cannot be overloaded).
// If you want to save a Path for permanent use, you can call copy_to_permanent()
// and free_permanent(). But you don't want to do this all the time
// for intermediate results, or else your program will become slow and cumbersome,
// like a C++ program.
Path :: struct {
    header_string: string;  // A drive letter in Windows, or "https:", or something else wacky like that.
    number_of_leading_slashes: int;
    
    trailing_slash: bool;   // True if there was a trailling slash at the end of the path.
        
    words: [..] string;  // The different pieces of the path. For "/a/b/hello.txt" this will be ["a", "b", "hello.txt"].
}    


// It is possible that we should not have 'reduce' in parse_path default to true,
// because it will turn a/b/../c into a/c, but if b is a symlink, this would
// do something weird, and if the first thing you do is reduce when you parse
// a path, that would break handling there. So umm... maybe we want to reduce
// later. Or maybe these are just shenanigans we don't want to entertain.
// Actually the correct behavior here depends on what meaning your shell assigns
// to ..? 
parse_path :: (_s: string, reduce := true) -> Path {
    s := _s;
    result: Path;

    // Look for a prefix.
    prefix_length: int;
    for i: 0..s.count-1 {
        if s[i] == #char "/" break;  // We reached the first slash, so by definition this isn't a prefix.
        
        if s[i] == #char ":" {
            prefix_length = i+1;  // Include the : in the prefix length.
        }
    }

    if prefix_length {
        result.header_string = s;
        result.header_string.count = prefix_length;
        advance(*s, prefix_length);
    }

    while s && (s[0] == #char "/") {
        result.number_of_leading_slashes += 1;
        advance(*s, 1);
    }
    
    words := split(s, "/");
    if words && words[words.count-1] == "" {
        result.trailing_slash = true;
        words.count -= 1;
    }

    // words.data is in Temporary_Storage, so set that on the array...
    result.words = resizable(words, false);  // Promote [] to [..]
    result.words.allocator = temp;
    
    if reduce  return reduce_path(result);
    else       return result;
}

reduce_path :: (path: Path) -> Path {  // The returned Path is in Temporary_Storage (and we use Temporary_Storage for the words array).
    result := path;

    words: [..] string;
    words.allocator = temp;
    for path.words {
        if it == "." {
            // Skip this!
        } else if it == ".." {
            // Backtrack by one folder, unless
            // result.words is empty, in which case just put this in there as the first element,
            // signifying that we are backing up into unknown territory.

            if words.count {
                words.count -= 1;
            } else {
                array_add(*words, it);
            }
        } else if it == "" {
            // Skip this!
        } else {
            array_add(*words, it);
        }
    }
    
    result.words = words;
    
    return result;
}

path_contains :: (path: Path, words: [] string) -> (contains: bool, position: s32) {
    for outer_loop, i: path.words {
        if i + words.count > path.words.count  break;

        for word, j: words {
            if path.words[i+j] != word  continue outer_loop;
        }

        return true, cast(s32) i;
    }
    
    return false, 0;  
}

path_to_string :: (path: Path, max_words := -1) -> string {  // max_words is here so you can do a sub-path. If it's >= 0, we stop when getting to that word index. See examples.
    builder: String_Builder;
    init_string_builder(*builder);

    append(*builder, path.header_string);

    for 1..path.number_of_leading_slashes append(*builder, "/");

    for path.words {
        if it_index == max_words break;
        
        append(*builder, it);
        if (it_index != path.words.count-1) || path.trailing_slash  append(*builder, "/");
    }
    
    return builder_to_string(*builder);
}

how_much_of_path_exists_on_the_local_filesystem :: (path: Path) -> (fully_exists: bool, how_much_exists: s32) {
    // We could in principle care about making sure files don't change underneath while we do this traversal,
    // but, we do not for now. We presume this is for interactive applications, and anyway, after we return
    // the value you will have to check again.
    
    // For now I just wanted to get this working, so we are doing a super-disgusting thing where we convert
    // to string at every step and let the filesystem handle concatenated paths, which first of all is inefficient,
    // and secondly sort of obviates the whole point of using these Path data structures instead of strings.
    // (Not totally, but kind of). Probably this should be rewritten to keep an open directory handle and
    // use FindFirstFile / FindNextFile. But then you have to start dealing with Windows path character
    // weirdnesses like the $$ and %% or whatever the F characters are used to do all the weird things.
    // For now I am just leaving this note here to say, for a fully robust system you probably want to do this.
    // If you are making an OS file API, it is well worth your time to make this kind of per-step navigation
    // as easy as possible so that users like me do not have to stress.

    // Even though we are doing this gross string concatenation thing right now, nevertheless, we persist
    // in having the API use a well-structured path, because a tremendous number of problems happen in
    // current-day programs due to treating paths as unstructured strings, and we are doing things in what
    // we think is more of the Right Way, holding out for a future, better world. (Same reason we insist
    // on, in run_command, providing all the arguments as separate words in an array: each word might
    // have spaces or punctuation or whatever, and we want to disambiguate ... but both Windows and Linux
    // promptly concatenate this into a big string, because they are losers who want to cause problems.

    // If we want to keep the string version, but make it faster, we could concatenate once,
    // then change the length of the string view as we go.
    

    push_allocator(temp);
    path_so_far := "";
    
    last_existing_index: s32 = -1;
    for path.words {
        if (it == ".") || (it == "") {
            last_existing_index = cast(s32) it_index;
            continue;
        }

        if it_index == 0  {
            n := path.number_of_leading_slashes;
            if n {
                lead := talloc_string(n);
                for 0..n-1 lead[it] = #char "/";
                path_so_far = join(lead, it);
            } else {
                path_so_far = it;
            }
        } else {
            path_so_far = join(path_so_far, "/", it);  // @Speed! This is very inefficient. Ugh.
        }

        #if OS == .WINDOWS {
            attrib := GetFileAttributesW(utf8_to_wide(path_so_far,, temp));
            if attrib == INVALID_FILE_ATTRIBUTES {
                // We could provide further data here about why the open failed.
                // We don't do this yet.
                break;
            }

            last_existing_index = cast(s32) it_index;
            if !(attrib & FILE_ATTRIBUTE_DIRECTORY) {
                // This must be the last entry in the path.
                // We already set the last_existing_index, so, break.
                break;
            }
        } else {
            fs: stat_t;
            // Yuck!! temp_c_string.
            result := stat(temp_c_string(path_so_far), *fs);
            if result != 0 {
                // We could provide further data here about why the stat failed.
                // We don't do this yet.
                break;
            }

            last_existing_index = cast(s32) it_index;
            if !S_ISDIR(fs.st_mode) {
                // This must be the last entry in the path.
                // We already set the last_existing_index, so, break.
                break;
            }
        }
    }

    // If last_existing_index is the last word index, we say the path fully exists.
    // But the path could have too much ... extra stuff after a file.
    // In that case, we don't say it fully exists.

    fully_exists := path.words && (last_existing_index == path.words.count-1);
    return fully_exists, last_existing_index+1;  // how_much_exists is the count of things that exist, not the index, so we add one.
}


// copy_to_permanent() and free_permanent() are meant to be called
// when you have a non-temporary allocator active.
// The 'words' and 'header_string' were substrings of the original
// input, but are now being given their own separate memory.
copy_to_permanent :: (path: Path) -> Path {
    result: Path;

    result.header_string = copy_string(path.header_string);

    result.number_of_leading_slashes = path.number_of_leading_slashes;
    result.trailing_slash            = path.trailing_slash;
    
    array_copy(*result.words, path.words);
    for * result.words { << it = copy_string(<< it); }

    return result;
}

free_permanent :: (using path: Path) {
    free(header_string);
    for words free(it);
    free(words.data);
}
