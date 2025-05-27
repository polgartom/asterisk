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

is_alphanum :: inline (c: u32) -> bool {
    return is_alpha(c) || is_digit(c) || c == #char "_";
}

is_whitespace :: inline (c: u32) -> bool {
    assert(c != #char "\t", "We should convert all of the tabs to spaces");
    return c == #char " " || c == #char "\n";
}

is_line_end :: inline (c: u32) -> bool {
    assert(c != #char "\r", "We should convert all of the \\r (CRs) to \\n (LRs)");
    return c == #char "\n";
}

is_hex_digit :: (c: u32) -> bool {
    return (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F") || (c >= #char "0" && c <= #char "9");
}

is_upper :: inline (char: u8) -> bool {
    return char >= #char "A" && char <= #char "Z";
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