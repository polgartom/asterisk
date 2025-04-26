/*

We wanted some of the most basic string operations to be in Basic.
So this String.jai now has only the more-involved stuff ... not every
single basic manipulation you might do to a string. As we develop it
and it gets more of an identity, maybe we want to name it something
more descriptive, or maybe split it into multiple modules (like
String and Scan, or something like that, I don't know!)

                  -jblow, 28 January 2019
*/

/*

We will probably change the _from_left and _from_right later on to _from_start and _from_end,
so that they aren't confusing when using right-to-left languages. But, I dunno, maybe not, hmm.
The decision was to ship this for now with the _left and _right terminology and see how
things evolve.

*/

/*

Here are the routines in this file:


compare :: (a: string, b: string) -> int;

    Compare two strings in a way that matches C's strcmp semantics, and that is convenient
    for passing to sorting functions.

compare_nocase :: (a: string, b: string) -> int;

    A case-insensitive version of 'compare'.

equal :: (a: string, b: string) -> bool;

    Just a wrapper for a == b. You might want this for polymorphism reasons, but it still
    seems a bit silly. It makes more sense in light of:

equal_nocase :: (a: string, b: string) -> bool;

    Are to strings equal, case-insensitively? Uses to_lower() to compare letters
    in lowercase, thus is subject to the constraints of to_lower(). Only does ASCII,
    not general Unicode.

contains :: (str: string, substring: string) -> (found: bool, remainder: string);

    Does 's' contain any occurrence of 'substring'?
    Searches from left to right.
    If the substring is matched, we return found=true,
    and the string that remains after that substring as 'remainder'.
    If the substring is not matched, found=false, remainder="".
    Note that remainder can be "" if found==true, because 'substring'
    might match the end of 'str'!
    If 'remainder' is not empty, it is guaranteed to point into 
    the same memory as 'str'; it will never be a copy, so you can 
    write to it accordingly. (But if 'remainder' is the empty string
    its data pointer may well be null, as you probably expect).

contains_nocase :: (s: string, substring: string) -> (found: bool, remainder: string);

    Case-insensitive version of 'contains'.

contains :: (s: string, char: u8) -> (found: bool, remainder: string);

    Does 's' contain the character 'char'?

contains_any_character :: (s: string, chars: string) -> (found: bool, remainder: string);

    Does s contain any character in 'chars'?

contains_any_string :: (s: string, substrings: .. string) -> (found: bool, remainder: string);

    Does s contain any string in 'substrings'?

begins_with :: (s: string, prefix: string) -> bool;

    Are the first 'prefix.count' characters of 's' identical to 'prefix'?

ends_with   :: (s: string, suffix: string) -> bool;

    Are the last 'suffix.count' characters of 's' identical to 'suffix'?

begins_with_nocase :: (s: string, prefix: string) -> bool;
ends\ _with_nocase :: (s: string, suffix: string) -> bool;

    Case-insensitive versions of 'begins_with' and 'ends_with'.

replace_chars :: (s: string, chars: string, replacement: u8);

    For any bytes in 's' also contained in 'chars', overwrite those bytes
    with 'replacement'. This modifies 's' destructively in-place. If s
    is in read-only memory, this will crash!

    @Cleanup: Probably the word 'chars' will be replaced with 'bytes' for clarity.

replace :: (s: string, old: string, new: string) -> (result: string, ocurrences: int);

    Returns a new string, where each occurrence 'old' inside 's' is replaced by 'new'.
    Replacement scans from left to right, and does not consider overlaps.
    The resulting string is allocated with alloc().

to_lower_in_place :: (s: string);

    Modify 's' destructively in-place to convert all ASCII upper-case characters
    to lowercase. Does not do general Unicode characters, just ASCII.
    Only modifies uppercase characters (those from 'A'-'Z').
    WARNING: You cannot call this on string contants; they are in read-only memory,
    so this will crash. (If the compiler knows it's a constant, it will compile-time assert).

to_lower_copy :: (s: string, allocator := Basic.temporary_allocator) -> string;

    Make a copy of 's' and convert all ASCII upper-case characters
    to lowercase. Does not do general Unicode characters, just ASCII.
    Only modifies uppercase characters (those from 'A'-'Z').

to_upper_in_place :: (s: string);

    Like 'to_lower_in_place', but converting to uppercase.
    Only modifies lowercase characters (those from 'a'-'z').
    WARNING: You cannot call this on string contants; they are in read-only memory,
    so this will crash. (If the compiler knows it's a constant, it will compile-time assert).

to_upper_copy :: (s: string, allocator := Basic.temporary_allocator) -> string;

    Like 'to_lower_copy', but converting to uppercase.
    Only modifies lowercase characters (those from 'a'-'z').

slice :: inline (s: string, index: s64, count: s64) -> string;

    Return a string view on 's', starting at 'index', 'count' characters long.
    I don't like the name 'slice' because it sounds like a modification operation,
    so we will probably change the name of this.

join :: (inputs: .. string, separator := "", before_first := false, after_last := false) -> string;

    Make a string, consisting of each member of 'inputs', with 'separator' sandwiched in between.
    For example, if 'inputs' is ["One", "Two", "Three"] and 'separator' is "::", the result
    (if before_first and after_last are false) is "One::Two::Three".

    If before_first == true,  and after_last == false, this example yields "::One::Two::Three".
    If before_first == false, and after_last == true,  this example yields "One::Two::Three::".
    Of course you can turn on both of these and get "::One::Two::Three::".



find_index_from_left  :: (s: string, byte: u8, start_index := 0) -> s64;

    Search for the first occurrence of 'byte' in 's', starting from the beginning of the string
    (or start_index, if provided) and proceeding forward. If a match is found, return the index
    in 's' where 'byte' was found. If no match is found, return -1.

    For example, find_index_from_left("Hello", #char "l") == 2.

find_index_from_right :: (s: string, byte: u8) -> s64;

    Like find_index_from_left, but starting at the right and proceeding leftward.

    For example, find_index_from_right("Hello", #char "l") == 3.


find_index_from_left  :: (s: string, substring: string, start_index := 0) -> s64;

    Like the 'byte' version of find_index_from_left, but searching for an entire string
    instead of a byte. In practice this will be slower than the byte version.

    Search for the first occurrence of 'substring' in 's', starting from the beginning of the string
    and proceeding forward. If a match is found, return the index of the first character in 's' where
    'substring' is found. If no match is found, return -1.

    For example, find_index_from_left("Testing", "ing") == 4.
                 find_index_from_left("Testing a thing", "ing") == 4.

find_index_from_right :: (s: string, substring: string) -> s64;

    Like find_index_from_left, but starting on the right and moving leftward. If a match is found,
    return the index of the first charcter in 's' where 'substring' is found.

    For example, find_index_from_right("Testing", "ing") == 4.
                 find_index_from_right("Testing a thing", "ing") == 12.

find_index_of_any_from_left  :: (s: string, bytes: string) -> s64;

   Like the single-'byte' version of 'find_index_from_left', but returns a match when
   any of the bytes in 'bytes' are found.

   For example, find_index_of_any_from_left("Chattanooga", "x?to") == 3.

   Be careful, because this takes the same argument types as the string version of
   find_index_from_left, so calling the wrong routine would be an easy mistake to make.

find_index_of_any_from_right :: (s: string, bytes: string) -> s64;

   Like the 'bytes' version of find_index_of_any_from_left, but starting from the right.

   For example, find_index_of_any_from_right("Chattanooga", "x?to") == 8.


split_from_left  :: (s: string, byte: u8) -> (found: bool, left: string, right: string);

    Using the same index returned by find_index_from_left(s, byte), split 's' into two
    strings, 'left', which contains all of 's' before the byte, and 'right', which contains
    all of 's' after the byte. The particular occurrence of 'byte' will not be contained
    in either 'left' or 'right', but other instances of that byte value may be contained
    in 'right'.

    The returned strings are just views into 's', so no allocation occurs.

    Example: split_from_left("The Perennial Philosophy", #char " ") returns (true, "The", "Perennial Philosophy").

    If no match is found, the return value is (false, s, "").

split_from_right :: (s: string, byte: u8) -> (found: bool, left: string, right: string);

    Like split_from_left, but starting on the right and proceeding leftward.

    Example: split_from_right("The Perennial Philosophy", #char " ") returns (true, "The Perennial", "Philosophy").

    If no match is found, the return value is (false, "", s).

split_from_left  :: (s: string, separator: string) -> (found: bool, left: string, right: string);

    Like the 'byte' version of split_from_left, but splitting by a substring.
    Generally, this will be slower than the byte version.

    Example: split_from_left("Apple and Banana and Cake", "and") returns (true, "Apple ", " Banana and Cake").


split_from_right :: (s: string, separator: string) -> (found: bool, left: string, right: string);

    Like the 'byte' version of split_from_right, but splitting by a substring.
    Generally, this will be slower than the byte version.

    Example: split_from_right("Apple and Banana and Cake", "and") returns (true, "Apple and Banana ", " Cake").


split_from_left_by_any  :: (s: string, bytes: string) -> (found: bool, left: string, right: string);

    Like the 'byte' version of split_from_left, but splitting upon finding the occurrence of
    any of the bytes contained in 'bytes'.

    Example: split_from_left_by_any("Apple and Banana and Cake", "and") returns (true, "Apple ", "nd Banana and Cake").

    Be careful calling this, since it takes the same argument types as split_from_left, so calling
    the wrong function would be an easy mistake to make.


split_from_right_by_any :: (s: string, bytes: string) -> (found: bool, left: string, right: string);

    Like the 'byte' version of split_from_right, but splitting upon finding the occurrence of
    any of the bytes contained in 'bytes'.

    Example: split_from_right_by_any("Apple and Banana and Cake", "and") returns (true, "Apple and Banana and C", "ke").

    Be careful calling this, since it takes the same argument types as split_from_right, so calling
    the wrong function would be an easy mistake to make.


split :: (s: string, separator: $T) -> (result: [] string);

    Split 's' at all occurrences of 'separator', returning an array of result strings.
    'separator' can be either of type u8 or string.

    Example: split("Apple and Banana and Cake", "and") returns ["Apple ", " Banana ", " Cake"].

    The return strings are just views on 's', so they do not incur allocations.
    The array data for 'result' is allocated via Temporary_Storage.


trim_left :: (s: string, chars := DEFAULT_SPACES) -> string;

    Start scanning from left to right, removing all bytes in 's' that are contained
    in 'chars'. As soon as a non-matching byte is found, stop and return the rest of
    the string.

    Example: trim_left("+-+ Word -+-", "-+ x") == "Word -+-".

    The returned string is just a view on s, so no allocation occurs.

    @Cleanup: 'chars' should be called 'bytes' for consistency, and this will probably
    be changed in the future.


trim_right :: (s: string, chars := DEFAULT_SPACES) -> string;

    Like trim_left, but starting from the right and proceeding leftward.

    Example: trim_right("+-+ Word -+-", "-+ x") == "+-+ Word".


trim :: (s: string, chars := DEFAULT_SPACES) -> string;

    Trim from both sides.  Equivalent to trim_right(trim_left(s, chars), chars).

    Example: trim("+-+ Word -+-", "-+ x") == "Word".


stop_at_any :: (s: string, bytes: string) -> string;

    Start at the beginning of 's', scanning from left to right.
    When any of the bytes in 'bytes' is detected, stop and return
    the contents of 's' up to that point.

    The returned string is just a view on s, so no allocation occurs.

    Example: stop_at_any("Gravity's Rainbow", "bcdefgh") returns "Gravity's Rain".


eat_trailing_spaces :: (_s: string) -> string;
eat_until_space     :: (_s: string) -> string;

    These will probably go away since they are redundant with trim(), but to minimize
    disruption we are keeping them for now. @Cleanup.


Path routines:


path_decomp :: (name: string) -> (path: string, basename: string, extension: string, basename_with_extension: string);

    Separate the file path 'name' into its compontents.

    Example: path_decomp("/home/wizard/rezrov.foo") returns ("/home/wizard/", "rezrov", "foo", "rezrov.foo").

    The returned strings are just views on 'path', so no allocation is performed.

    path_decomp calls the path routines below to generate the various results, so, refer to them for details.

    (@Incomplete: We should document here what happens with .. kinds of things, and the various corner cases
    in the code.)


path_filename :: (path: string) -> string;

    path_filename("/home/wizard/rezrov.foo") returns "rezrov.foo".

path_extension :: (path: string) -> (extension: string, found_extension: bool);

    path_extension("/home/wizard/rezrov.foo") returns "foo".

path_strip_filename :: (path: string) -> string;

    path_strip_filename("/home/wizard/rezrov.foo") returns "/home/wizard/".

path_strip_extension :: (path: string) -> string;

    path_strip_extension("/home/wizard/rezrov.foo") returns "/home/wizard/rezrov".
    path_strip_extension("hello.aji") returns "hello".

path_overwrite_separators :: (path: string, separator: u8 = PATH_SEPARATOR);

    Modify 'path' in-place to convert one kind of directory separator to another.
    Any occurrence of #char "\" or #char "/" in 'path' will be replaced by 'separator'.

    This routine is basically made to deal with annoyances involving backslashes in Windows.

    Ensure 'path' is writable or you will have a sad time.

    Example: path_overwrite_separators("C:\\sokoban\\src", #char "/") modifies 'path' to contain "C:/sokoban/src".

    (This example is confusing because of the backslashed backslashes in the string literal,
    but as the string is represented in memory, there is only one backslash at each of those
    locations).

    @Cleanup: We will get rid of PATH_SEPARATOR default. This is bad.


is_absolute_path :: (path: string) -> bool;

    If 'path' starts with "/" or "\\", or a drive letter on Windows, return true.
    Otherwise return false.


wildcard_match :: (s: string, pat: string) -> bool;

    Match simple wildcard patterns. Supports: `*`, `?`, `[]` and `[-]` only.
    @Incomplete: There's no support for `+`, `(|)`, `[^]`
    @Incomplete: This needs to be documented much more when it is finished.

scan :: (format: string, text: string) -> bool, [] Any;

    This scan implementation supports the following patterns:
    * `%f` -> float value
    * `%i` -> integer
    * `%b` -> `true` or `false`
    * `%s` -> quoted string. @@ escape characters not supported yet! (`\n` `\r` `\t` `\"` `\\`)
    * `%%` -> `%`

    // @Incomplete: Make scan handle \% for %.

    This function returns an array of `Any` structs, where the values of each element are allocated in temporary memory.


scan2 :: (text: string, format: string, args: ..Any) -> bool;

    A new experiment. This scan function matches the text string based on the type of the arguments.
    ~~~~~~~~~
      v: Vector3;
      scan2(text, "(% % %)", *v.x, *v.y, *v.z);
    ~~~~~~~~~
    Note, arguments must be passed by reference (as pointers). We could support arguments that are implicitly passed by reference, but it's not entirely
    obvious when this happens, and when the reference is an l-value that we can output the result to.
    For example, this reads a vector and the second component must be 1.0, otherwise it fails:
    ~~~~~~~~~
      scan2(text, "(% % %)", *v.x, 1.0, *v.z);
    ~~~~~~~~~
    Not sure how useful would that be, so for now this is not implmented.

*/

/*

It seems likely that we might move this parse_* stuff to a different module later on.
But for now it still lives here.
I don't recommend parsing things this way, since this is a weird structure that passes
'delimiters' and 'spaces' down to leaf routines, which is a backward way to make
your parser too complicated and confusing. They're here in case people are using
them, but we recommend people not use them, as they will be deprecated eventually.

Since we don't recommend using them, I am not documenting them here.

         -jblow, 18 August 2021

parse_bool  :: (line: *string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> (value: bool, success: bool);
parse_enum  :: (line: *string, $T : Type, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> (value: T, success: bool);
parse_float :: (line: *string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> (value: float, success: bool);
parse_int   :: (line: *string, $T : Type = int, spaces:=" \t", delimiters:=DEFAULT_DELIMITERS) -> (value: T, success: bool);

The parse_token, match_token, match_token_nocase will probably be removed sooner than later.

*/


// String comparison:

/// compare has the same semantics as strcmp from C.
compare :: (a: string, b: string) -> int {
    for 0..min(a.count, b.count)-1 {
        if a[it] > b[it] return 1;
        if a[it] < b[it] return -1;
    }
    if a.count > b.count return 1;
    if a.count < b.count return -1;
    return 0;
}

/// compare_nocase has the same semantics as stricmp or strcasecmp, but only supports English characters.
compare_nocase :: (a: string, b: string) -> int {
    for 0..min(a.count,b.count)-1 {
        if to_lower(a[it]) > to_lower(b[it]) return 1;
        if to_lower(a[it]) < to_lower(b[it]) return -1;
    }
    if a.count > b.count return 1;
    if a.count < b.count return -1;
    return 0;
}

equal :: (a: string, b: string) -> bool {
    return a == b;
}

equal_nocase :: (a: string, b: string) -> bool {
    if a.count != b.count return false;
    for 0..a.count-1 {
        if to_lower(a[it]) != to_lower(b[it]) return false;
    }
    return true;
}

contains :: (s: string, substring: string) -> (found: bool, remainder: string) {
    index := find_index_from_left(s, substring);

    if index == -1  return false, "";

    return true, advance(s, index + substring.count);
}

contains_nocase :: (s: string, substring: string) -> (found: bool, remainder: string) {
    index := index_of_string_nocase(s, substring);

    if index == -1  return false, "";

    return true, advance(s, index + substring.count);
}

contains :: (s: string, char: u8) -> (found: bool, remainder: string) {
    index := find_index_from_left(s, char);

    if index == -1  return false, "";

    return true, advance(s, index + 1);
}

// Returns true if the string 'str' contains any occurrence of any of the characters in the string 'chars'.
contains_any_character :: (s: string, chars: string) -> (found: bool, remainder: string) {
    index := find_index_of_any_from_left(s, chars);

    if index == -1  return false, "";

    return true, advance(s, index + 1);
}

contains_any_string :: (s: string, substrings: .. string) -> (found: bool, remainder: string) {
    for substrings {
        found, remainder := contains(s, it);
        if found  return true, remainder;
    }
    
    return false, "";
}


begins_with :: (s: string, prefix: string) -> bool {
    if s.count < prefix.count  return false;

    t := slice(s, 0, prefix.count);

    return t == prefix;
}

ends_with :: (s: string, suffix: string) -> bool {
    if s.count < suffix.count  return false;

    t := slice(s, s.count-suffix.count, suffix.count);

    return t == suffix;
}

begins_with_nocase :: (s: string, prefix: string) -> bool {
    if s.count < prefix.count  return false;

    t := slice(s, 0, prefix.count);

    return equal_nocase(t, prefix);
}

ends_with_nocase :: (s: string, suffix: string) -> bool {
    if s.count < suffix.count  return false;

    t := slice(s, s.count-suffix.count, suffix.count);

    return equal_nocase(t, suffix);
}

// @Cleanup: Get rid of this or make a find_index_from_left_nocase.
// This is a nocase partner of a deprecated routine. We'll decide what to do with it.
index_of_string_nocase :: (s: string, substring: string) -> int, found:bool {
    if s.count < substring.count  return -1, false;

    for 0..s.count-substring.count {
        t := slice(s, it, substring.count);
        if equal_nocase(t, substring) return it, true;
    }

    return -1, false;
}

replace_chars :: (s: string, chars: string, replacement: u8) {
    for 0..s.count-1 {
        if is_any(s[it], chars) s[it] = replacement;
    }
}




// Match simple wildcard patterns. Supports: `*`, `?`, `[]` and `[-]` only.
// @@ There's no support for `+`, `(|)`, `[^]`
wildcard_match :: (s: string, pat: string) -> bool {
    while true {
        // If pattern is over, string must be over too.
        if !pat.count return !s.count;

        // If string is over and pattern not over, then it must be *
        if !s.count && pat[0] != #char "*" return false;

        // Handle wildcard.
        if pat[0] == #char "*" {
            advance(*pat);
            if !pat.count return true;
            while true {
                if wildcard_match(s, pat) return true;
                if !s.count return false;
                advance(*s);
            }
        }

        // Skip one character.
        if pat[0] == #char "?" {
            advance(*pat);
            advance(*s);
            continue;
        }

        // Skip any character in set or within range.
        if pat[0] == #char "[" {
            advance(*pat);
            while true {
                if (pat[0] == #char "]" || !pat.count) return false;
                if pat[0] == s[0] break;
                if pat[1] == #char "-" {
                    if pat.count == 1 return false;
                    c2 := pat[2];
                    if pat[0] <= s[0] && c2 >= s[0] break;
                    if pat[0] >= s[0] && c2 <= s[0] break;
                    advance(*pat, 2);
                }
                advance(*pat);
            }
            while pat[0] != #char "]" {
                if !pat.count {
                    advance(*pat, -1);
                    break;
                }
                advance(*pat);
            }

            advance(*pat);
            advance(*s);
            continue;
        }

        // Skip if match.
        if pat[0] != s[0] return false;

        advance(*pat);
        advance(*s);
    }

    return false; // To silence the warning.
}


scan :: (format: string, text: string) -> bool, [] Any { // The returned array is in Temporary_Storage.
    // @Cleanup: scan() should not use temp by default, probably?
    result: [..] Any;
    result.allocator = temp;

    // @@ IC: These functions are kind of lame, they are just swapping the order of the arguments.
    read_float :: (text: *string) -> bool, float {
        result: float;
        success: bool;
        result, success, <<text = string_to_float(<<text);
        return success, result;
    }
    read_int :: (text: *string) -> bool, int {
        result: int;
        success: bool;
        result, success, <<text = string_to_int(<<text);
        return success, result;
    }
    read_bool :: (text: *string) -> bool, bool {
        if begins_with(<<text, "true") {
            advance(text, 4);
            return true, true;
        }
        if begins_with(<<text, "false") {
            advance(text, 5);
            return true, false;
        }
        return false, false;
    }

    read_string :: (text: *string) -> bool, string {
        if text.count == 0 || (<<text)[0] != #char "\"" return false, "";
        advance(text, 1);

        i := 0;
        while i < text.count {
            // @@ Incomplete: Add support for escape sequences.
            /*if text[i] == #char "\\" {
                if i == text.count - 1 return false, "";
            }*/

            if (<<text)[i] == #char "\"" {
                // End of string.
                result := slice(<< text, 0, i);
                advance(text, i+1);
                return true, result;
            }

            i += 1;
        }

        return false, slice(<<text, 1, i-1);
    }

    copy_any :: (x: Any) -> Any {
        any: Any = ---;
        any.type = x.type;
        //any.value_pointer = alloc(x.type.runtime_size); // @@ Use temporary memory?
        any.value_pointer = Basic.temporary_alloc(x.type.runtime_size);
        memcpy(any.value_pointer, x.value_pointer, x.type.runtime_size);
        return any;
    }

    while true {
        if format[0] == #char "%" {
            if format.count == 1 return false, result;
            success := false;
            value : Any;
            if format.count > 1 if format[1] == {
                case #char "f";     success, value = read_float(*text);
                case #char "d";     #through;
                case #char "i";     success, value = read_int(*text);
                case #char "b";     success, value = read_bool(*text);
                case #char "s";     success, value = read_string(*text);
                case #char "%";     if text[0] != #char "%" return false, result; else success = true;  // @@ This is wrong!!
            }
            if !success return false, result;
            array_add(*result, copy_any(value));
            advance(*format, 2);
        } else {
            if text[0] != format[0] return false, result;
            advance(*format);
            advance(*text);
        }

        // If both strings are done, then we found a match.
        if format.count == 0 && text.count == 0 return true, result;

        // If only one of the strings is done, then there's a mismatch.
        if format.count == 0 || text.count == 0 return false, result;
    }

    // @@ This is unreachable, but necessary to avoid warning.
    return false, result;
}

scan2 :: (text: string, format: string, args: ..Any) -> bool {

    n := 0;

    while true {
        if format[0] == #char "%" {
            if format.count > 1 && format[1] == #char "%" {
                if text[0] != #char "%" return false;
                advance(*format, 2);
                advance(*text);
            } else {
                if n >= args.count return false;

                if args[n].type.type != .POINTER return false;

                arg_type := (cast(*Type_Info_Pointer)args[n].type).pointer_to;

                any : Any;
                any.type = arg_type;
                any.value_pointer = <<cast(**void)args[n].value_pointer;

                // The implementation of any -> string is in Print, but the implementation of string -> any is in Reflection. Maybe this should be unified.
                success := Reflection.set_value_from_string(any, *text);

                if !success return false;
                advance(*format);
                n += 1;
            }
        }
        else {
            if text[0] != format[0] return false;
            advance(*format);
            advance(*text);
        }

        // If both strings are done, then we found a match.
        if format.count == 0 && text.count == 0 return true;

        // If only one of the strings is done, then there's a mismatch.
        if format.count == 0 || text.count == 0 return false;
    }

    return true; // To silence warnings.
} @ScanLike


// Allocates a string. Also uses some temporary storage.
replace :: (s: string, old: string, new: string) -> string, ocurrences:int {
    segments := split(s, old);
    return join(..segments, new), segments.count-1;
}

to_lower_in_place :: ($$ s: string) {  // Do not call this on string constants; they are in read-only memory and will crash!
    #if is_constant(s)  #assert false "You cannot call to_lower_in_place on constant strings, as they are stored in read-only memory. They must be copied if you want to change them.";

    for 0..s.count-1 s[it] = to_lower(s[it]);
}

to_upper_in_place :: ($$ s: string) {  // Do not call this on string constants; they are in read-only memory and will crash!
    #if is_constant(s)  #assert false "You cannot call to_upper_in_place on constant strings, as they are stored in read-only memory. They must be copied if you want to change them.";

    for 0..s.count-1 s[it] = to_upper(s[it]);
}

to_lower_copy_new :: (s: string) -> string #deprecated "Just call to_lower_copy() now, as it's been updated." {
    return to_lower_copy(s);
}

to_lower_copy :: (s: string) -> string {
    t := alloc_string(s.count);
    for 0..t.count-1 t[it] = to_lower(s[it]);
    return t;
}

to_upper_copy_new :: (s: string) -> string #deprecated "Just call to_upper_copy() now, as it's been updated." {
    return to_upper_copy(s);
}

to_upper_copy :: (s: string) -> string {
    t := alloc_string(s.count);
    for 0..t.count-1 t[it] = to_upper(s[it]);
    return t;
}


// 'slice' is a bad name for this function. It should be changed.
// I don't care what Go calls it.
slice :: inline (s: string, index: s64, count: s64) -> string {
    assert(index >= 0, "index = %", index);
    assert(count >= 0, "count = %", count);
    if index >= s.count  return "";

    if index + count > s.count {
        count = s.count - index;
    }

    c: string = ---;
    c.data    = s.data + index;
    c.count   = count;
    return c;
}

join :: (inputs: .. string, separator := "", before_first := false, after_last := false) -> string {
    if !inputs return "";

    bytes := separator.count * (inputs.count-1);
    for inputs bytes += it.count;

    if before_first  bytes += separator.count;
    if after_last    bytes += separator.count;

    if !bytes return "";

    result: string;
    result.count = bytes;
    result.data  = Basic.alloc(bytes);
    assert(result.data != null);

    if !result.data  return "";  // Allocation failed. Maybe we should log an error.

    cursor := result.data;
    if before_first && inputs.count {
        memcpy(cursor, separator.data, separator.count);
        cursor += separator.count;
    }

    for input: inputs {
        memcpy(cursor, input.data, input.count);
        cursor += input.count;

        if separator {
            if (it_index == inputs.count-1) && !after_last {
                continue;
            }

            memcpy(cursor, separator.data, separator.count);
            cursor += separator.count;
        }
    }

    assert(cursor == result.data + result.count);

    return result;
}


find_index_from_left :: (s: string, substring: string, start_index := 0) -> s64 {
    if !substring return -1;

    // This is SO SLOW! @Cleanup.
    for i: start_index..s.count-substring.count {
        t := slice(s, i, substring.count);
        if t == substring return i;
    }

    return -1;
}

// To do: Support start_index as well!
find_index_from_right :: (s: string, substring: string) -> s64 {
    if !substring return -1;

    // This is SO SLOW! @Cleanup.
    for #v2 < i: 0..s.count-substring.count {
        t := slice(s, i, substring.count);
        if t == substring return i;
    }

    return -1;
}


// Returns a slice of the input string.
trim_left :: (s: string, chars := DEFAULT_SPACES) -> string {
    index := 0;

    for 0..s.count-1 {
        if is_any(s[it], chars) index += 1;
        else break;
    }

    return slice(s, index, s.count-index);
}

// Returns a slice of the input string.
trim_right :: (s: string, chars := DEFAULT_SPACES) -> string {
    count := s.count;

    for < s {
        if is_any(it, chars) count -= 1;
        else break;
    }

    return slice(s, 0, count);
}

// Returns a slice of the input string.
trim :: (s: string, chars := DEFAULT_SPACES) -> string {
    return trim_right(trim_left(s, chars), chars);
}

// Converts any \r\n into \n, overwriting the original data.
normalize_line_endings :: (s: *string) {
    dest := 0;
    src := 0;
    data := s.data;
    while src < s.count {
        if data[src] == #char "\r" && src < s.count - 1 && data[src + 1] == #char "\n" {
            src += 1;
        }
        data[dest] = data[src];
        dest += 1;
        src += 1;
    }
    s.count = dest;
}

// Converts any \r\n into \n and returns the result in a new buffer you have to free
normalize_line_endings :: (s: string) -> string #must {
    copy := copy_string(s);

    dest := 0;
    src := 0;
    dest_data := copy.data;
    src_data := s.data;
    while src < s.count {
        if src_data[src] == #char "\r" && src < s.count - 1 && src_data[src + 1] == #char "\n" {
            src += 1;
        }
        dest_data[dest] = src_data[src];
        dest += 1;
        src += 1;
    }
    copy.count = dest;
    return copy;
}

// test_normalize :: (s: string, expected: string) {
//     copy := copy_string(s);
//     normalize_line_endings(*copy);
//     assert(copy == expected, "Expected \"%\" but got \"%\"", expected, copy);
// }

// #run test_normalize("", "");
// #run test_normalize("\n", "\n");
// #run test_normalize("\r", "\r");
// #run test_normalize("\r\n", "\n");
// #run test_normalize("this\r\nis\r\nfine", "this\nis\nfine");
// #run test_normalize("this\r\nis\r\nfine\r\n", "this\nis\nfine\n");
// #run test_normalize("this\r\nis\r\nfine\r", "this\nis\nfine\r");
// #run test_normalize("this\r\nis\r\nfine\n", "this\nis\nfine\n");


//
// This path_* stuff should not go here.
// It should go into its own place!
//

// File path manipulation:

#if OS == .WINDOWS {
    PATH_SEPARATOR :: #char "\\";
} else {
    PATH_SEPARATOR :: #char "/";
}

//
// Rather than having a bunch of things that return separate aspects of the filename,
// and you have to call multiple of these to do most work, why not just make
// a routine that returns  (path, filename, extension, filename_without_extension)
// and you use whichever of these you want? I think there is some code at
// least kind of like that in Sokoban already.  -jblow, 13 January 2019
//

decomp_filename :: path_decomp;  // @Temporary; remove.
path_decomp :: (name: string) -> (path: string, basename: string, extension: string, basename_with_extension: string) {
    path := path_strip_filename(name);

    basename_with_extension := advance(name, path.count);
    extension := path_extension(basename_with_extension);
    basename := basename_with_extension;

    basename.count -= extension.count;

    // If there is a . at the end of the filename, path_extension returns the empty string.
    // So we want to remove that. But we also want to remove it with a non-empty extension.

    if (extension != "") || (basename && (basename[basename.count-1] == #char ".")) {
        basename.count -= 1;
    }

    return path, basename, extension, basename_with_extension;
}

// Returns a slice of the input string.
path_filename :: (path: string) -> string {
    index := find_index_of_any_from_right(path, "\\/");
    if index == -1 return path;
    index += 1;
    return slice(path, index, path.count-index);
}

// Returns extension without including the . prefix.
// Returns a view of the input string.
// 'found_extension' is here to disambiguate between having no . at the end, and having a . with the empty string afterward.
path_extension :: (path: string) -> (extension: string, found_extension: bool) {
    index := find_index_of_any_from_right(path, ".\\/");

    if index <= 0 return "", false;  // Including 0 because, I guess we let '.' in the first character be a dotfile, and don't count that as an extension. Hmm.

    if path[index] != #char "."  return "", false;


    // What if it's a . right after a slash? Well, it's a dotfile kind of thing in that case, just with directories in front.
    previous := path[index-1];
    if (previous == #char "\\") || (previous == #char "/") {
        return "", false;
    }

    // Hmm: What about something like: /..
    if previous == #char "." {
        if index == 1  return "", false;  // Because index-1 is already 0, and we can't look any more left.

        two_previous := path[index-2];
        if (two_previous == #char "\\") || (two_previous == #char "/") {
            return "", false;
        }
    }

    s := slice(path, index+1, path.count-index-1);
    return s, true;
}

// Return path with file name removed, but including path separator.
// Returns a slice of the input string.
path_strip_filename :: (path: string) -> string {
    index := find_index_of_any_from_right(path, "\\/");
    if index < 0 return "";

    return slice(path, 0, index + 1);
}

// Returns a slice of the input string.
path_strip_extension :: (path: string) -> string {
    extension, found := path_extension(path);

    if !found return path;

    result := path;
    result.count -= extension.count + 1;
    return result;
}

// Operates in place. Replaces all slashes and backslashes with whatever you
// pass as 'separator' (defaults to OS-native path separator, which honestly,
// I do not love since I think everyone is kinda standardizing on / now.)
// @Cleanup: Get rid of PATH_SEPARATOR default. This is bad.
path_overwrite_separators :: (path: string, separator: u8 = PATH_SEPARATOR) {
    for 0..path.count-1 {
        if path[it] == #char "\\" || path[it] == #char "/" {
            path[it] = separator;
        }
    }
}

basename :: (s: string) -> string {
    return path_strip_extension(path_filename(s));
}

path_basename :: basename;

// Returns the same string or a temporary string.
path_ensure_extension :: (path: string, extension: string) -> string {
    if path_extension(path) == extension return path;
    return tprint("%.%", path, extension);
}

is_absolute_path :: (path: string) -> bool {
    #if OS == .WINDOWS {
        if path.count < 3 return false;
        return path[1] == #char ":" && (path[2] == #char "/" || path[2] == #char "\\");
    } else {
        if path.count < 1 return false;
        return path[0] == #char "/";
    }
}


DEFAULT_DELIMITERS :: ";=()";
DEFAULT_SPACES     :: " \t\r\n";

parse_bool :: (line: *string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:bool, success:bool {
    value, ok := parse_token(line, delimiters, spaces);
    if !ok return false, false;

    if ok && equal_nocase(value, "true")  return value=true, success=true;
    if ok && equal_nocase(value, "false") return value=false, success=true;
    return false, success=false;
}


// 'parse_token' is a misleading name since it returns a string, not a token. Thus
// it will probably be changed in a future version.
parse_token :: (line: *string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:string, success:bool {
    assert(line != null);
    backup := <<line;

    // skip whitespace:
    <<line = trim_left(<<line, spaces);

    if !line {
        defer <<line = backup;
        return <<line, false;
    }

    // read until space or delimiters.
    i := 0;
	if 0 < line.count {
		if is_any((<< line)[0], delimiters) {
			// Delimiters form single character tokens.
			i = 1;
		} else {
			// Otherwise advance until space or delimiter.
			while i < line.count && !is_any((<< line)[i], spaces) && !is_any((<< line)[i], delimiters) {
				i += 1;
			}
		}
	}

    if i > 0 {
        defer advance(line, i);
        return slice(<<line, 0, i), true;
    } else {
        defer <<line = backup;
        return slice(<<line, 0, 0), false;
    }
}

match_token :: (line: *string, match: string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:string, success:bool {
    token, ok := parse_token(line, delimiters, spaces);
    return token, ok && token == match;
}

match_token_nocase :: (line: *string, match: string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:string, success:bool {
    token, ok := parse_token(line, delimiters, spaces);
    return token, ok && equal_nocase(token, match);
}


parse_enum :: (line: *string, $T : Type, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:T, success:bool {
    token, ok := parse_token(line, delimiters, spaces);
    value: T;
    if ok value, ok = Reflection.enum_name_to_value(T, token);
    return value, ok;
}

parse_float :: (line: *string, delimiters:=DEFAULT_DELIMITERS, spaces:=DEFAULT_SPACES) -> value:float, success:bool {
    token, ok := parse_token(line, delimiters, spaces);
    value: float;
    if ok value, ok = string_to_float(token);
    return value, ok;
}

parse_int :: (line: *string, $T : Type = int, spaces:=" \t", delimiters:=DEFAULT_DELIMITERS) -> value:T, success:bool {
    token, ok := parse_token(line, delimiters, spaces);

    i: int;
    if ok i, ok = string_to_int(token);

    value := cast(T) i;
    //ok = ok && cast(int)value == i;
    return value, ok;
}




split_from_left :: (s: string, byte: u8) -> (found: bool, left: string, right: string) {
    index := inline find_index_from_left(s, byte);
    if index == -1  return false, s, "";

    return true, slice(s, 0, index), slice(s, index+1, s.count - index-1);
}

split_from_right :: (s: string, byte: u8) -> (found: bool, left: string, right: string) {
    index := inline find_index_from_right(s, byte);
    if index == -1  return false, "", s;

    return true, slice(s, 0, index), slice(s, index+1, s.count - index-1);
}

split :: (s: string, separator: $T) -> [] string {  // 'separator' must be a string or byte.
    #assert (T == u8) || (T == string);

    results: [..] string;

    remainder := s;
    while remainder {
        found, left, right := split_from_left(remainder, separator);
        if found {
            array_add(*results, left);
        } else {
            array_add(*results, remainder);
            break;
        }

        remainder = right;
    }

    if !remainder array_add(*results, "");  // We want 'split' to return an unambiguous result (was there a match at the end or not?), and to be the inverse of 'join'. For this to happen, if there was a match at the very end, we just add an empty string. Maybe there is a more elegant way to structure the loop to make this happen.

    return results;
}


split_from_left_by_any :: (s: string, bytes: string) -> (found: bool, left: string, right: string) {
    index := inline find_index_of_any_from_left(s, bytes);
    if index == -1  return false, s, "";

    return true, slice(s, 0, index), slice(s, index+1, s.count - index-1);
}

split_from_right_by_any :: (s: string, bytes: string) -> (found: bool, left: string, right: string) {
    index := inline find_index_of_any_from_right(s, bytes);
    if index == -1  return false, s, "";

    return true, slice(s, 0, index), slice(s, index+1, s.count - index-1);
}



split_from_left :: (s: string, separator: string) -> (found: bool, left: string, right: string) {
    index := inline find_index_from_left(s, separator);
    if index == -1  return false, s, "";

    return true, slice(s, 0, index), slice(s, index+separator.count, s.count - (index+separator.count));
}

split_from_right :: (s: string, separator: string) -> (found: bool, left: string, right: string) {
    index := inline find_index_from_right(s, separator);
    if index == -1  return false, s, "";

    return true, slice(s, 0, index), slice(s, index+separator.count, s.count - (index+separator.count));
}



find_index_from_left :: (s: string, byte: u8, start_index := 0) -> s64  #no_abc { // Returns -1 if the byte is not found in the string.
    cursor := start_index;

    #if USE_SIMD && (CPU == .X64) {

        //
        // The following loop uses SSE instructions to scan 16 characters at a time:
        //

        #asm {
            pxor.x      zeroes:, zeroes;
            movd        source:, byte;
            pshufb.x    source, zeroes;
        }

        while s.count - cursor > SIMD_WIDTH {
            point := s.data + cursor;

            mask:    u32 = ---;
            advance: u32;
            #asm {
                movdqu.x    test:, [point];
                pcmpeqb.x   test, source;
                pmovmskb.x  mask, test;
                bsf.d       advance, mask;
            }

            if mask  return cursor + advance;

            cursor += 16;
            continue;
        }
    }

    while cursor < s.count {
        if s[cursor] == byte  return cursor;
        cursor += 1;
    }

    return -1;
}

// @ToDo: Support start_index as well!
find_index_from_right :: (s: string, byte: u8) -> s64  #no_abc {  // Returns -1 if the byte is not found in the string.
    cursor := s.count - 1;
    while cursor >= 0 {
        if s[cursor] == byte  return cursor;
        cursor -= 1;
    }

    return -1;
}

find_index_of_any_from_left :: (s: string, bytes: string, start_index := 0) -> s64  #no_abc {
    cursor := start_index;
    while cursor < s.count {
        if is_any(s[cursor], bytes) return cursor;
        cursor += 1;
    }

    return -1;
}

// @ToDo: Support start_index as well!
find_index_of_any_from_right :: (s: string, bytes: string) -> s64  #no_abc {  // Returns -1 if the byte is not found in the string.
    cursor := s.count - 1;
    while cursor >= 0 {
        if is_any(s[cursor], bytes)  return cursor;
        cursor -= 1;
    }

    return -1;
}

// Return a string view from the beginning of the string, until the first instance of the given character.
stop_at_any :: (s: string, bytes: string) -> string {
    index := find_index_of_any_from_left(s, bytes);
    if index == -1 return s;

    if index == 0 return "";
    return slice(s, 0, index);
}

starts_with :: begins_with;

eat_trailing_spaces :: (_s: string) -> string {
    s := _s;
    while s {
        if (s[s.count-1] != #char " ") && (s[s.count-1] != 9)  break; // 9 is horizontal tab.
        s.count -= 1;
    }

    return s;
}

eat_until_space :: (_s: string) -> string {
    s := _s;
    while s {
        if s[0] == #char " " break;
        if s[0] == 9         break;
        advance(*s, 1);
    }

    return s;
}


// Call this to try out the string routines:
string_tests :: () {
    assert(join(.. .["foo", "bar", "puf"], ", ") == "foo, bar, puf");
    assert(join("foo", "bar", "puf", separator="/") == "foo/bar/puf");

    assert("foo/bar/puf" == join(..split("foo/bar/puf", "/"), "/"));
    assert("foo\\bar\\puf" == join(..split("foo/bar/puf", "/"), "\\"));
    assert("foo/bar/puf/grr" == join(..split("foo, bar, puf, grr", ", "), "/"));

    assert("blah" == "blah");
    assert("foot" != "foo");
    assert("bla" != "blade");

    assert(equal("blah", "blah"));
    assert(!equal("bar", "foo"));
    assert(equal("abc", "abc"));
    assert(!equal("abc", "abcd"));
    assert(!equal("abc", "Abc"));
    assert(equal_nocase("abc", "Abc"));
    assert(equal_nocase("aBc", "abC"));

    assert(compare("foo", "foo") == 0);
    assert(compare("foo", "bar") > 0);
    assert(compare("foo", "foot") < 0);
    assert(compare("foot", "foo") > 0);
    assert(compare("foam", "foot") < 0);
    assert(compare("000", "111") < 0);
    assert(compare("111", "000") > 0);
    assert(compare("1", "111") < 0);
    assert(compare("1", "000") > 0);

    assert(!contains("PaSsWoRd", "!"));
    assert(find_index_of_any_from_left("PaSsWoRd", "0123456789")  == -1);
    assert(find_index_of_any_from_left("PaSs2WoRd", "0123456789") == 4);

    assert(begins_with("Hello World", "Hello"));
    assert(ends_with("Hello World", "World"));

    // @@ Add tests for index & find

    assert(wildcard_match("filename.exe", "*.exe"));
    assert(!wildcard_match("filename.exe.not-really", "*.exe"));
    assert(wildcard_match("filename.exe", "*.*"));
    assert(wildcard_match("filename.", "*.*"));
    assert(wildcard_match(".filename", "*.*"));
    assert(!wildcard_match("filename", "*.*"));
    assert(wildcard_match("/foo/bar/filename", "/*/*"));
    assert(wildcard_match("/foo/filename", "/*/*"));
    assert(!wildcard_match("//filename", "/?*/*"));
    assert(wildcard_match("//filename//", "*/"));

    assert(trim_right("  Hi!  ", " !") == "  Hi");
    assert(trim_left("  Hi!  ", " ") == "Hi!  ");
    assert(trim("  Hi!  ") == "Hi!");

    // File path functions:
    assert(path_filename("/foo/bar/filename.ext") == "filename.ext");
    assert(path_filename("/foo/bar/file.name.ext") == "file.name.ext");
    assert(path_filename("/foo/bar.stool/") == "");
    assert(path_filename(".filename") == ".filename");
    assert(path_filename("/") == "");
    assert(path_filename("") == "");

    assert(path_extension("/foo/bar/filename.ext") == "ext");
    assert(path_extension("/foo/bar/file.name.ext") == "ext");
    assert(path_extension("/foo/bar.stool/filename") == "");
    assert(path_extension("/foo/bar/.filename") == "");         // Special case for hidden files. filename not considered an extension.
    assert(path_extension(".filename") == "");
    assert(path_extension("") == "");

    assert(path_strip_filename("/foo/bar/filename.ext") == "/foo/bar/");
    assert(path_strip_filename("\\foo\\bar\\filename.ext") == "\\foo\\bar\\");
    assert(path_strip_filename("/foo/bar/") == "/foo/bar/");
    assert(path_strip_filename("foo.ext") == "");
    assert(path_strip_filename("./foo.ext") == "./");
    assert(path_strip_filename("/") == "/");
    assert(path_strip_filename("/./") == "/./");
    assert(path_strip_filename(".") == "");
    assert(path_strip_filename("") == "");

    assert(path_strip_extension("/foo/bar/filename.ext") == "/foo/bar/filename");
    assert(path_strip_extension("/foo/bar.stool/filename") == "/foo/bar.stool/filename");
    assert(path_strip_extension("/foo/.filename.ext") == "/foo/.filename");
    assert(path_strip_extension("/foo/.filename") == "/foo/.filename");
    assert(path_strip_extension("") == "");

    assert(path_overwrite_separators(copy_string("/foo\\bar/")) == path_overwrite_separators(copy_string("\\foo/bar\\")));    // @Leak. @@ How can we make it easy to avoid these?

    // @@ These are all leaking the any array.
    assert(scan("(%f %f %f)", "(-1 +1.5e+1 3.14159)"));
    assert(scan("%s", "\"I'm a string\""));
    assert(scan("enum %i", "enum 1"));
    assert(scan("%i", "-1"));

    assert(!scan("(%f, %f, %f)", "(1 1.5e+1 3.14159)"));    // No commas!
    assert(!scan("%s ", "\"I'm a string\""));               // No space at the end of the string!
    assert(!scan("enum %i", "enum 1.3"));                   // Not an integer!

    {
        success, values := scan("(%f, %f, %f)", "(1, 1.5e+1, 3.14159)");
        assert(success && values.count == 3);

        f0 := << cast(*float) values[0].value_pointer;
        f1 := << cast(*float) values[1].value_pointer;
        f2 := << cast(*float) values[2].value_pointer;
        assert(f0 == 1);
        assert(f1 == 1.5e+1);
        assert(f2 == 3.14159);
    }

    {
        v : [3]float;
        success := scan2("(1, 1.5e+1, 3.14159)", "(%, %, %)", *v[0], *v[1], *v[2]);
        assert(success && v[0] == 1 && v[1] == 1.5e+1 && v[2] == 3.14159);

        V : struct { x,y,z :float; };
        success = scan2("(1, 1.5e+1, 3.14159)", "(%, %, %)", *V.x, *V.y, *V.z);
        assert(success && V.x == 1 && V.y == 15 && V.z == 3.14159);

        file : string;
        modtime : int;
//        a := type_info(type_of(*file));
//        aa := type_info(type_of(*modtime));
//        print("a: %\n", a);
//        print("a index: %\n", a.index_within_type_table);
//        print("a: %\n", a);
//        print("aa: %\n", aa);
        success = scan2("\"C:/Thekla/jai/build/x64/Release/jai.exe\" 131708227363563455", "% %", *file, *modtime);
        assert(success && file == "C:/Thekla/jai/build/x64/Release/jai.exe" && modtime == 131708227363563455);
    }


    assert(find_index_of_any_from_left("Chattanooga", "x?to") == 3);  // As promised in the documentation.
    assert(find_index_of_any_from_right("Chattanooga", "x?to") == 8);

    a, b, c, d := path_decomp("/home/wizard/rezrov.foo");
    assert(a == "/home/wizard/");
    assert(b == "rezrov");
    assert(c == "foo");
    assert(d == "rezrov.foo");

    assert(path_filename("/home/wizard/rezrov.foo") == "rezrov.foo");
    assert(path_extension("/home/wizard/rezrov.foo") == "foo");
    assert(path_strip_extension("/home/wizard/rezrov.foo") == "/home/wizard/rezrov");
    assert(path_strip_extension("hello.aji") == "hello");


    split_test :: (input: string, separator: string) {
        print("Input '%', separator '%':\n", input, separator);

        x := split(input, separator);
        print("x is %\n", x);

        y := join(..x, separator);
        print("y is %\n", y);

        assert(y == input);
    }


    split_test("bbb", "b");
    split_test("cowabunga", "a");
    split_test("babybabybaby", "bab");
    split_test("babybabybaby", "a");
} @test

is_any :: (c: u8, chars:string) -> bool {
    for i: 0..chars.count-1 {
        if c == chars[i] return true;
    }

    return false;
}

#scope_module

USE_SIMD   :: true;
SIMD_WIDTH :: 16;

Basic :: #import "Basic";
using Basic;

Reflection :: #import "Reflection"; // @Cleanup: Probably should not require this.

