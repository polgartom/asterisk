#scope_export

tokenize :: (buffer: *Buffer, $language: Language) {
    time := seconds_since_init();
    defer { 
        buffer.tokenization_time = (seconds_since_init() - time) * 1000;        
    }
    // defer ll("%ms\n", buffer.tokenization_time);
    
    if (!buffer.count) return;

    colorize(buffer, Color.TEXT_DEFAULT, .{0,  buffer.count});

    at := buffer.data;
    end := buffer_end(buffer);
    if at == end return;

    while at < end {
        if is_alpha(at[0]) || at[0] == #char "_" {
            if at > buffer.data {
                prev_char := (at-1).*;
                if is_alphanum(prev_char) { // It can't be an identifier if the previous char is not a separator
                    eat();
                    continue;
                }
            }
            
            inline parse_ident(buffer, *at);
            
        } else if is_digit(at[0]) {
            if at > buffer.data {
                prev_char := (at-1).*;
                if is_alpha(prev_char) { // It can't be an identifier if the previous char is not a separator
                    eat();
                    continue;
                }
            }
            
            inline parse_numeric_value(buffer, *at);
            
        } else if at[0] == #char "/" {
            if !(at+1<end) break;
            if at[1] == #char "/" {
                start := at - buffer.data;
                steps := find_index_from_left(.{count=end-at,data=at}, #char "\n");
                if steps == -1 then steps = end - at;
                colorize(buffer, Color.LANG_TOKEN_COMMENT, .{start, start+steps});
                at += steps;
                if at < end eat();
            } else if at[1] == #char "*" {
                c0 := at;
                c1 := at;
                while at < end {
                    defer eat();

                    steps := find_index_from_left(.{count=end-at,data=at}, #char "*");
                    if steps == -1 {
                        at = end;
                        break;
                    }

                    at += steps;
                    if at<end && (at+1).* == #char "/" {
                        eat();
                        break;                                
                    }
                }

                colorize(buffer, Color.LANG_TOKEN_COMMENT, c0, at);

            } else {
                eat();
            }
        } else if at[0] == #char "\"" {
            inline parse_string_literal(buffer, *at, #char "\"");

        } else if at[0] == #char "'" {
            inline parse_string_literal(buffer, *at, #char "'");
        } else {
            eat();
        }

    }
}

#scope_file

parse_string_literal :: (buffer: *Buffer, _at: **u8, $token: u8 = #char "\"") {
    at := _at.*;
    defer _at.* = at;

    buffer.colors[at-buffer.data] = .LANG_TOKEN_STRING_LITERAL;
    eat();

    buf_end := buffer_end(buffer);
    while at < buf_end {
        defer eat();

        if at.* == #char "\\" && at+1 < buf_end {
            buffer.colors[at-buffer.data] = .LANG_TOKEN_ESCAPED;
            eat();
            buffer.colors[at-buffer.data] = .LANG_TOKEN_ESCAPED;
            continue;
        }

        buffer.colors[at-buffer.data] = .LANG_TOKEN_STRING_LITERAL;

        if at.* == token {
            break;
        }
    }
}

parse_numeric_value :: (buffer: *Buffer, _at: **u8) {
    at := _at.*;
    defer _at.* = at;
    buf_end := buffer_end(buffer);

    c0 := at;
    c1 := at;

    if at[0] == #char "0" && peak() == #char "x" {
        // Parse hex
        
        eat(); // step from 0
        eat(); // step from x
        while at < buf_end {
            defer eat();
            // @Tempoary Jai allows the underscore character like "0x3f_7a_3fff", but not many language supports that; so
            // we should make separate tokenizers for every language.
            if !is_hex_digit(at[0]) && at[0] != #char "_" {
                c1 = at;
                break;
            }
        }
        
    } else {
        parse_float := false;
        while at < buf_end {
            defer eat();
    
            if !is_digit(at[0]) {
                if !parse_float && at[0] == #char "." {
                    parse_float = true;
                    continue;
                }
    
                c1 = at;
                break;
            }
        }
        
    }

    colorize(buffer, .LANG_TOKEN_NUMERIC_VALUE, c0, c1);
}

parse_ident :: (buffer: *Buffer, _at: **u8) -> bool {
    at := _at.*;
    defer _at.* = at;
    
    c0 := at;
    c1 := at;

    buf_end := buffer_end(buffer);
    while at < buf_end {
        defer eat();

        // We check this below is_alphanum()
        // if is_multibyte_char(at) { // Identifiers cannot be multibyte
            // while at < buf_end {
                // if !is_multibyte_char(at) && is_separator(at.*, false) break;
                // eat();
            // }
//             
            // return false;
        // }
        
        if !is_alphanum(at[0]) {
            c1 = at;
            break;
        }
    }

    if c0 == c1 return false;

    ident := slice(buffer, c0, c1);

    prev_char := peak_prev_char(c0);
    if prev_char == { // @Cleanup: These are language specific things
        case #char "#"; colorize(buffer, .LANG_TOKEN_DIRECTIVE, c0-1, c1); return true;
        case #char "@"; colorize(buffer, .LANG_TOKEN_DIRECTIVE, c0-1, c1); return true;
    }
    
    if match_with_any_keyword(ident) {
        colorize(buffer, .LANG_TOKEN_KEYWORD, c0, c1);
        return true;
    }

    c1 = skip_whitespaces(c1);
    if c1 < buf_end && c1.* == #char "(" {
        colorize(buffer, .LANG_TOKEN_PROCEDURE_CALL, c0, c1);
        return true;
    }

    return true;
}

colorize :: inline (using b: *Buffer, color: Color, range: Range) {
    memset(colors.data + range.start, cast(u8, color), range.end - range.start);
}

colorize :: inline (b: *Buffer, color: Color, start_ptr: *u8, end_ptr: *u8) {
    start := start_ptr - b.data;
    size  := end_ptr - start_ptr;

    memset(b.colors.data + start, cast(u8, color), size);
}

eat :: () #expand {
    `at += 1 + trailingBytesForUTF8[`at[0]];
}

peak :: () -> u8 #expand {
    if `at < `buffer.data + `buffer.count return `at[1];
    return `at[0];
}

skip_whitespaces :: () #expand {
    while is_whitespace(`at[0]) {
        `at += 1;
    }
}

skip_whitespaces :: inline (point: *u8) -> *u8 {
    while is_whitespace(point[0]) point += 1;
    return point;
}

peak_next_char :: (point: *u8) -> u8 #expand {
    end := (`buffer.data + `buffer.count);
    assert(point <= end);
    if point == end return 0;
    if point+1 < end return (point+1).*;
    return point[0];
}

peak_prev_char :: (point: *u8) -> u8 #expand {
    if point-1 >= `buffer.data return (point-1).*;
    return point[0];
}

is_multibyte_char :: inline (c: *u8) -> bool {
    return !!trailingBytesForUTF8[c[0]];
}

#scope_export

language_from_file_extension :: (ext: string) -> Language {
    if ext == {
        case "jai"; return .JAI;
        case "c"; #through; case "h"; #through;
        case "cpp"; #through; case "hpp"; #through;
        case "cxx"; 
            return .C_STYLE;
        case "py";
            return .PYTHON;
    };
    
    return .PLAIN_TEXT;
}

language_kind_to_string :: (lang: Language) -> string {
    if lang == {
        case .C_STYLE; return "C";
        case .JAI;     return "Jai";
        case .PYTHON;  return "Python";
    };
    
    return "Text";
}

language_inline_comment_token :: (lang: Language) -> string {
    if lang == {
        case .C_STYLE; return "//";
        case .JAI;     return "//";
        case .PYTHON;  return "#";
    };
    return "";
}

Token_Type :: enum {
    UNKNOWN             :: 0;
    IDENTIFIER          :: 1;
    KEYWORD             :: 2;
    NUMBER_LITERAL      :: 3;
    STRING_LITERAL      :: 4;
    DIRECTIVE           :: 5;
    PROCEDURE_CALL      :: 6;

    COMMENT_INLINE      :: 7;
    COMMENT_MULTILINE   :: 8;
}

Language :: enum_flags u64 {
    PLAIN_TEXT;
    C_STYLE;
    JAI;
    PYTHON;
}

////////////////////////

#scope_file

match_with_any_keyword :: inline (token_str: string) -> bool {
    found, _ := table_find(*KEYWORDS_TABLE, token_str);
    return found;
}

KEYWORDS_TABLE :: #run -> Table(string, bool) {
    table: Table(string, bool);
    size := (KEYWORDS.count);
    init(*table, KEYWORDS.count);

    for keyword: KEYWORDS {
        table_set(*table, keyword, true);
    }

    return table;
}

KEYWORDS :: string.[
    "if", "else", "elseif", "return", "for", "while", "true", "false", "null", "string", "struct", "class", "enum", "union", "const", "yield", "static", "inline",
    "continue", "break", "default", "exit", "assert", "use", "namespace",
    "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "float", "float32", "float64", "size_t", "char", "short", "unsigned", "long", "int", "bool", "boolean", "double",
    "public", "private", "protected", "defer", "cast", "case", "void", "new",
    
    "using", "then", "xx", "ifx", "context" // Jai
];

#import "Basic";
#import "Math";
#import "String";
#import "Unicode";