//////////////////////////
// Array

advance :: (arr: *[] $T, steps := 1) {
    assert(arr.count - steps > -1 && steps > -1);

    arr.data  += steps;
    arr.count -= steps;
}

advance :: (arr: [] $T, steps := 1) -> [] T {
    assert(arr.count - steps > -1 && steps > -1);

    r: [] T;
    r.data  = arr.data  + steps;
    r.count = arr.count - steps;

    return r;
}

//////////////////////////
// String

free_string :: (target: *string) {
    if target.count && target.data free(target.*);
    target.data = null;
    target.count = 0;
}

modify_string :: (target: *string, new_value: string) {    
    if target.count free(target.*);
    target.* = copy_string(new_value);
}

//  @Cleanup: Naming
find_index_from_right_until_not :: (s: string, byte: u8, start_index: s64 = 0) -> s64  #no_abc {
    assert(start_index > -1 && start_index < s.count);

    cursor := start_index;
    while cursor >= 0 {
        if s[cursor] != byte return cursor;
        cursor -= 1;
    }

    return -1;
}

//  @Cleanup: Naming
find_index_from_left_until_not :: (s: string, byte: u8, start_index: s64 = 0) -> s64  #no_abc {
    assert(start_index > -1);

    cursor := start_index;
    while cursor < s.count {
        if s[cursor] != byte return cursor;
        cursor += 1;
    }

    return -1;
}

count_whitespaces_from_left :: (s: string, $space_character_only := false) -> s64 {
    count := 0;
    for c: s {
        #if space_character_only {
            if c != #char " " break;
        } else {
            if !is_whitespace(c) break;
        }
        count += 1;
    }

    return count;
}

find_index_from_left_nocase :: (s: string, substring: string, start_index := 0) -> int, found: bool {
    if s.count < substring.count  return -1, false;

    for start_index..s.count-substring.count {
        t := slice(s, it, substring.count);
        if equal_nocase(t, substring) return it, true;
    }

    return -1, false;
}

count_int_digits :: (num: int) -> int {
    count := 0;
    while true {
        num /= 10;
        count += 1;
        if num == 0 break;
    }
    return count;
}

is_separator :: inline (c: u8, $include_underscore := true) -> bool {
    #if include_underscore {
        if c == #char "_" return true;
    }

    return c == #char " " || c == #char "\n" ||
           c == #char "{" || c == #char "}"  ||
           c == #char "." || c == #char ";"  ||
           c == #char ">" || c == #char "<"  ||
           c == #char "=" || c == #char "!"  ||
           c == #char "[" || c == #char "]"  ||
           c == #char "(" || c == #char ")"  ||
           c == #char "#" || c == #char "?"  ||
           c == #char "/" || c == #char "*"  ||
           c == #char "-" || c == #char "+"  ||
           c == #char "&" || c == #char "@"  ||
           c == #char "$" || c == #char ","  ||
           c == #char ":" || c == #char "|"  ||
           c == #char "^" || c == #char "%"  ||
           c == #char "~" || c == #char "\\" ||
           c == #char "\"" || c == #char "'" ||
           c == #char "`"
           ;
}

is_alpha :: inline (c: u32) -> bool{
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

is_digit :: inline (c: u32) -> bool{
    return (c >= #char "0" && c <= #char "9");
}

is_alphanum :: inline (c: u32, $include_underscore := true) -> bool {
    #if include_underscore {
        if c == #char "_" return true;
    }
    return is_alpha(c) || is_digit(c);
}

is_whitespace :: inline (c: u32) -> bool {
    assert(c != #char "\t", "We should convert all of the tabs to spaces");
    return c == #char " " || c == #char "\n";
}

is_line_end :: inline (c: u32) -> bool {
    assert(c != #char "\r", "We should convert all of the \\r (CRs) to \\n (LRs)");
    return c == #char "\n";
}

is_printable :: (c: u8) -> bool {
    // True for any character from space to tilde (DEL not included).
    return c >= 0x20 && c < 0x7F;
}

is_ctrl :: (c: u8) -> bool {
    return !is_printable(c);
} 

is_hex_digit :: (c: u32) -> bool {
    return (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F") || (c >= #char "0" && c <= #char "9");
}

is_upper :: inline (char: u8) -> bool {
    return char >= #char "A" && char <= #char "Z";
}

Character_Type :: enum u8 { ctrl; alphanum; symbol; space; };
get_character_type :: (c: u8) -> Character_Type {
    if trailingBytesForUTF8[1] != 0 return .alphanum; // @Temporary @Todo The multi-byte character can be a symbol but it's good for now!
    if is_alphanum(c)   return .alphanum;
    if c == #char " "   return .space;
    if !is_printable(c) return .ctrl;
    return .symbol;
}

to_snake_case_copy :: (s: string) -> string {
    b: String_Builder;
    init_string_builder(*b);

    for s {
        c := it;

        if !is_alphanum(c) {
            append(*b, "_");
            continue;
        }

        if is_upper(c) {
            c = to_lower(c);
            if it_index != 0 && s[it_index-1] != #char "_" {
                append(*b, "_");
            }                
        }

        append(*b, c);
    }

    return builder_to_string(*b, do_reset=true);
}

key_to_user_friendly_string :: (s: string, $camelcase := false) -> string {
    #import "Basic";

    b: String_Builder;
    init_string_builder(*b);
    
    spaced := false;
    for s {
        c := it;
        if c == #char " " {
            spaced = true;
            append(*b, c);
            continue;
        }
        if is_separator(c, include_underscore=true) {
            if it_index != 0 && !spaced {
                append(*b, #char " ");
                spaced = true;
            }
            continue;
        }
        #if camelcase {
            if is_upper(c) {
                if !spaced {
                    if it_index != 0 {
                        append(*b, #char " ");
                        spaced = true;
                    }

                    c = to_lower(c);
                }
            }
        }

        if it_index == 0 {
            c = to_upper(c);
        }

        append(*b, c);
        spaced = false;
    }

    return builder_to_string(*b, do_reset=true);
}

/////////////////////
// File utility

get_parent_dir_path :: (file_path: string) -> string {
    path := path_strip_filename(file_path);
    if path.count > 1 && path[path.count-1] == #char "/" then path.count -= 1;  // don't include trailing path separator
    return path;
}

os_path_begins_with :: (path: string, prefix: string) -> bool {
    #if OS == .WINDOWS {
        return begins_with_nocase(path, prefix);
    } else {
        return begins_with_nocase(path, prefix);
    }
}

platform_skip_matching_path_chunks :: (path_chunks: []string, compare_chunks: []string) -> []string {
    r := path_chunks;
    for i: 0..compare_chunks.count-1 {
        if !path_chunks.count break;
        if !platform_path_equals(path_chunks[0], compare_chunks[i]) break;
        r = advance(r, 1);
    }
    return r;
}

#if OS == .WINDOWS {
    platform_path_equals :: inline (path_a: string, path_b: string) -> bool {
        return equal_nocase(path_a, path_b);
    }

    platform_path_begins_with :: inline (path: string, subpath: string) -> bool {
        return begins_with_nocase(path, subpath);
    }

    platform_path_contains :: inline (path: string, subpath: string) -> bool {
        return contains_nocase(path, subpath);
    }
} else #if OS == .LINUX {
    platform_path_equals :: inline (path_a: string, path_b: string) -> bool {
        return path_a == path_b;
    }

    platform_path_begins_with :: inline (path: string, subpath: string) -> bool {
        return begins_with(path, subpath);
    }

    platform_path_contains :: inline (path: string, subpath: string) -> bool {
        return contains(path, subpath);
    }
}

path_unify_sepa :: inline (path: string) {
    for 0..path.count-1 {
        if path[it] == #char "\\" {
            path[it] = #char "/";
        }
    }
}

append_dir_sepa :: inline (path: string) -> string {
    if ends_with(path, "/") return path;
    p := alloc_string(path.count+1);
    for p { p[it_index] = path[it_index]; }
    p[p.count-1] = #char "/";
    return p;
}

//////////////////////
// Color

rgba_to_vec4 :: (r: u8, g: u8, b: u8, a: float = 1.0) -> Vector4 {
    return .{
        r / 255.0,
        g / 255.0,
        b / 255.0,
        a
    };
}

hex_to_vec4 :: (hex: u32) -> Vector4 {
    r := (hex>>24) & 0xFF;
    g := (hex>>16) & 0xFF;
    b := (hex>>8)  & 0xFF;
    a := (hex>>0)  & 0xFF;

    return .{
        r / 255.0,
        g / 255.0,
        b / 255.0,
        a / 255.0
    };
}

///////////////////
// Range

is_overlap :: (r1: Range, r2: Range) -> bool {
    if r1.a > r2.b || r2.a > r1.a return false;
    return true;
}

get_overlap_range :: (r1: Range, r2: Range) -> bool, Range {
    if !is_overlap(r1, r2) return false, .{0,0};

    return true, .{max(r1.a, r2.a), min(r1.b, r2.b)};
}

get_range_as_string :: (s: string, range: Range) -> string {
    return slice(s, range.start, range.end - range.start);
}

Range :: struct {
    start: s64;
    end:   s64;

    #place start; 
    a: s64; b: s64;
}

////////////////////////////////
// Misc

Code_get_identifier_name :: (name: Code) -> string {
    #import "Compiler";

    // This is just to help with the Add macro above.

    node := compiler_get_nodes(name);
    if node.kind != .IDENT {
        compiler_report("Not an identifier.", make_location(node));
        return "";
    }

    ident := cast(*Code_Ident) node;
    return ident.name;
}

get_enum_by_name :: ($t: Type, name: string) -> (_enum: t, success: bool) {
    #insert -> string {
        b: String_Builder;
        print_to_builder(*b, "if name == {\n");

        enums := enum_names(t);
        assert(enums.count > 0, "Please add some enum member to '%'\n", t);
        
        for name: enums {
            key_name := copy_string(name);
            to_lower_in_place(key_name);
            print_to_builder(*b, "case \"%\"; return .%, true;\n", key_name, name);
        }

        print_to_builder(*b, "}\n");

        print_to_builder(*b, "return .%, false;\n", enums[0]);

        return builder_to_string(*b);
    }
}

////////////////////////////////
// Imports

#import "String";
#import "Math";
#import "Unicode";