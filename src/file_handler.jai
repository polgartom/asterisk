//
// Text_File_Handler is a relatively simple and straightforward struct, with associated procedures,
// that helps you parse your own custom file format. See the examples/example.jai for a demonstration.
//

Text_File_Handler :: struct {
    short_name: string;  // short_name is just for your own reference; it's not used for any functional purpose here.
    full_path:  string;  // This is the path that will be reported in error messages.

    comment_character : u8 = #char "#";  // What character you want to start comments in your file. Set this at any time. Must be a 1-byte character (not an extended Unicode sequence).

    do_version_number                 := true;  // Do we check the version number on the file?
    strip_comments_from_ends_of_lines := true;  // Disable this if you want # (or whatever your comment character is) to be able to appear mid-line without cutting off the rest of the line.
    auto_skip_blank_lines             := true;
    
    file_data_to_free: string;  // In case we need to free this at the end. Will be empty if you called start_from_data..
    file_data:         string;  // The remaining portion of the file that we're in the middle of parsing.

    failed  := false;        // If we ever fail parsing, we set this. More about 'failed' below.
    version := -1;           // Set when parsing the file if do_version_number == true.

    line_number := 0;        // The current line number we are parsing. Used in error messages.
}


// You don't need to initialize Text_File_Handler; you just start using it.
// Call deinit when you are done if you want to free memory.
deinit :: (using x: *Text_File_Handler) { free(file_data_to_free); }


// About the 'failed' variable:
//
// For some kinds of programming, having to check a 'success' return status code,
// after calling each function, gets tedious and annoying. Especially when parsing,
// sometimes you don't care if you fail in the middle; you just want to blast through
// some stuff and then check at the end whether everything succeeded.
//
// That's what 'failed' is for. It starts false, and if anything ever fails, it gets
// set to true. Text_File_Handler will never set it back to false.

start_file :: (handler: *Text_File_Handler, short_name: string, full_path: string, optional := false, loc := #caller_location) {
    // Here we read from a file, but eventually we'll probably add an alternative
    // access point that just takes an in-memory string, so you aren't forced to
    // read from a file. In the meantime you can just factor that in yourself
    // if you want.

    data, success := read_entire_file(full_path, log_errors=!optional);

    if !success {
        // Now read_entire_file must log an error if it fails, so we don't do so here.
        // Note, this could result in silent failing (which is VERY BAD!) if for some reason
        // read_entire_file doesn't do its job and log the error. We will want to make sure of this...
        // if !optional  log_error("Unable to load file '%'.\n", full_path);
        handler.failed = true;
        return;
    }

    handler.file_data_to_free = data;
    
    start_from_memory(handler, short_name, full_path, data, loc);
}

// You can call start_from_memory directly if you already have the file data in memory,
// for example, if it's part of a bigger package:
start_from_memory :: (using handler: *Text_File_Handler, _short_name: string, _full_path: string, _file_data: string, loc := #caller_location) {
    // Note: We do NOT copy any of these name strings; we presume they remain valid
    // through the lifetime of the handler.

    short_name = _short_name;
    full_path  = _full_path;

    file_data  = _file_data;
    
    // The version number appears at the top of the file, in square brackets.
    // Why square brackets? We just wanted to have something very obvious. If there's an anonymous
    // number at the top, it might be easy to delete or mistake for something else.
    if do_version_number {
        // Parse the version number.
        line, found := consume_next_line(*file_data);  // consume_next_line skips whitespace and comments, returning the next line with actual data, or found==false.
        line_number += 1;
        
        if !found {
            log_error("Unable to find a version number at the top of file '%'!\n", full_path);
            failed = true;
            return;
        }

        // Check to ensure that we found square brackets with a number inside.
        assert(line.count > 0);
        if line[0] != #char "[" {
            log_error("Expected '[' at the top of file '%', but did not get it!\n", full_path);
            failed = true;
            return;
        }

        advance(*line, 1);
        
        version, version_success, remainder := string_to_int(line);  // Ignore the remainder of the line.
        if !version_success {
            log_error("Unable to parse the version number at the top of file '%'!\n", full_path);
            failed = true;
            return;
        }

        if (!remainder.count) || (remainder[0] != #char "]") {
            log_error("Expected ']' after version number in file '%', but did not get it! (Remainder is: %)\n", full_path, remainder);
            failed = true;
            return;
        }

        handler.version = version;
    }        
}

// Get the next line from the file that may contain useful information.
// This routine skips whitespace and comments.
consume_next_line :: (handler: *Text_File_Handler) -> (line: string, found: bool) {
    while true {
        line, found := consume_next_line(*handler.file_data);
        if !found return "", false;

        handler.line_number += 1;

        line = eat_spaces(line);
        
        if !line {
            if handler.auto_skip_blank_lines  continue;
            return "", true;
        }

        if handler.strip_comments_from_ends_of_lines {
            found, left := split_from_left(line, handler.comment_character);
            if found {
                line = left;
                if line.count == 0  continue;
            }
        } else {
            if line[0] == handler.comment_character continue;
        }
        
        line = eat_trailing_spaces(line);
        assert(line.count > 0);
        
        return line, found;
    }
}

consume_next_line :: (sp: *string) -> string, bool {
    // To find the end of the line, we look for a linefeed character.
    // We will trim a carriage return off the end if there is one there also.
    // Thus this works on both 'dos' and 'unix'-style files.

    s := sp.*;
    found, result, right := split_from_left(s, 10);

    if !found {
        // This is the last line; there may not have been a linefeed after that,
        // but we still want to handle that data, so we return true if there was
        // a nonzero amount of stuff there.
        
        sp.* = "";

        return s, (s.count > 0);
    }

    // Chop the characters we are going to return from 'sp',
    // which holds the remaining file data.
    advance(sp, result.count + 1);

    if result {
        if result[result.count-1] == 13  result.count -= 1;  // If there's a carriage return at the end, remove it by decrementing the string's length.
    }
    
    return result, true;
}


// break_by_spaces performs a basic activity that is very useful when parsing your own
// simple file format: Look for non-whitespace characters, followed by whitespace, followed by other stuff,
// and split by whitespace: 'left' is what came before the whitespace, and 'right' is what came after,
// with spaces trimmed from both of those.
break_by_spaces :: (line: string) -> (left: string, right: string) {
    left  := line;
    right := eat_until_space(line);  // 'right' now has everything from the first space to the end of the line.
    left.count -= right.count;
            
    right = eat_spaces(right);       // Trim the spaces from 'right'.

    return left, right;
}

break_by_colon :: (line: string) -> (left: string, right: string) {
    // left  := line;

    // right := eat_until_space(line);  // 'right' now has everything from the first space to the end of the line.
    // left.count -= right.count;
            
    // right = eat_spaces(right);       // Trim the spaces from 'right'.

    found, left, right := split_from_left(line, ":");
    if !found return "", "";

    return trim(left), trim(right);
}

// Report errors and warnings. It's convenient to do this by calling these procedures,
// since 'handler' tracks the filename and line number for you; you don't have to pass those
// around to your various parsing routines.
error :: (handler: Text_File_Handler, format: string, args: .. Any, flags := Log_Flags.NONE, loc := #caller_location) {
    new_format := tprint("Line % of '%'! %", handler.line_number, handler.full_path, format);
    log(new_format, .. args, flags=Log_Flags.ERROR|.CONTENT|flags, loc=loc);
} @PrintLike

warn :: (handler: Text_File_Handler, format: string, args: .. Any, flags := Log_Flags.NONE, loc := #caller_location) {
    new_format := tprint("Line % of '%': %", handler.line_number, handler.full_path, format);
    log(new_format, .. args, flags=Log_Flags.WARNING|.CONTENT|flags, loc=loc);
} @PrintLike


// In file_to_array and file_to_table,
// if use_data_from_memory is true, we use that as the file data, and just use the filename
// for error reporting. Otherwise, we open the file by name.
file_to_array :: (filename: string, do_trim := true, skip_blank_lines := true, do_version_number := false, use_data_from_memory := false, data_from_memory := "", loc := #caller_location) -> (success: bool, array: [..] string) {
    handler: Text_File_Handler;
    handler.do_version_number = do_version_number;

    array: [..] string;

    if use_data_from_memory  start_from_memory(*handler, filename, filename, data_from_memory, loc);
    else                     start_file       (*handler, filename, filename, loc=loc);
    
    if handler.failed  return false, array;
    
    while true {
        line, found := consume_next_line(*handler);
        if !found break;

        if do_trim  line = trim(line);
        if skip_blank_lines && !line  continue;
        
        array_add(*array, copy_string(line));
    }

    return true, array;
}

file_to_table :: (filename: string, do_trim := true, skip_blank_lines := true, do_version_number := false, use_data_from_memory := false, data_from_memory := "", loc := #caller_location) -> (success: bool, table: Table(string, void)) {
    handler: Text_File_Handler;
    handler.do_version_number = do_version_number;

    table: Table(string, void);

    if use_data_from_memory  start_from_memory(*handler, filename, filename, data_from_memory, loc);
    else                     start_file       (*handler, filename, filename, loc=loc);
    
    if handler.failed  return false, table;
    
    while true {
        line, found := consume_next_line(*handler);
        if !found break;

        if do_trim  line = trim(line);
        if skip_blank_lines && !line  continue;

        the_void: void;
        table_set(*table, copy_string(line), the_void);
    }

    return true, table;
}

#scope_file

#import "Basic";  // For log, tprint, etc.
#import "File";
#import "String";
#import "Hash_Table";
