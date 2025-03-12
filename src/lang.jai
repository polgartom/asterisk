#scope_export

get_token_type_color :: inline (type: Token_Type) -> Vector4 {
    if type == {
        case .KEYWORD;        return Vector4.{180/255.0, 90/255.0, 45/255.0, 1.0};
        case .DIRECTIVE;      return Vector4.{180/255.0, 90/255.0, 45/255.0, 1.0};
        case .PROCEDURE_CALL; return Vector4.{150/255.0, 100/255.0, 150/255.0, 1.0};

        case .COMMENT_INLINE; return Vector4.{10/255.0, 100/255.0, 10/255.0, 1.0};
        case .COMMENT_MULTILINE; return Vector4.{50/255.0, 50/255.0, 50/255.0, 1.0};
    };

    return Vector4.{221/255.0, 221/255.0, 221/255.0, 1.0};
}

tokenize :: (buffer: *Buffer, $language: Language) {
    time := seconds_since_init();
    defer { buffer.tokenization_time = (seconds_since_init() - time) * 1000; }
    // defer ll("%ms\n", buffer.tokenization_time);
    
    if (!buffer.count) return;

    colorize(buffer, Color.TEXT_DEFAULT, .{0,  buffer.count});

    at := buffer.data;
    end := buffer_end(buffer);
    if at == end return;

    while at < end {
        if is_alpha(at[0]) {
            if at > buffer.data {
                prev_char := (at-1).*;
                if is_alphanum(prev_char) { // It can't be an identifier if the previous char is not a separator
                    eat(*at);
                    continue;
                }
            }
            
            inline parse_ident(buffer, *at);
            
        } else if is_digit(at[0]) {
            if at > buffer.data {
                prev_char := (at-1).*;
                if is_alpha(prev_char) { // It can't be an identifier if the previous char is not a separator
                    eat(*at);
                    continue;
                }
            }
            
            inline parse_numeric_value(buffer, *at);
        } else if at[0] == #char "/" {
            // if !(at+1<end) break;
            if at[1] == #char "/" {
                start := at - buffer.data;
                steps := find_index_from_left(.{count=end-at,data=at}, #char "\n");
                if steps == -1 then steps = end - at;
                colorize(buffer, Color.LANG_COMMENT, .{start, start+steps});
                at += steps;
                if at < end eat(*at);
            } else if at[1] == #char "*" {
                c0 := at;
                c1 := at;
                while at < end {
                    defer eat(*at);

                    steps := find_index_from_left(.{count=end-at,data=at}, #char "*");
                    if steps == -1 {
                        at = end;
                        break;
                    }

                    at += steps;
                    if at<end && (at+1).* == #char "/" {
                        eat(*at);
                        break;                                
                    }
                }

                colorize(buffer, Color.LANG_COMMENT, c0, at);

            } else {
                eat(*at);
            }
        } else if at[0] == #char "\"" {
            inline parse_string_literal(buffer, *at, #char "\"");

        } else if at[0] == #char "'" {
            inline parse_string_literal(buffer, *at, #char "'");
        } else {
            eat(*at);
        }

    }
}

#scope_file

parse_string_literal :: (buffer: *Buffer, _at: **u8, $token: u8 = #char "\"") {
    at := _at.*;
    defer _at.* = at;

    buffer.colors[at-buffer.data] = .LANG_STRING_LITERAL;
    eat(*at);

    buf_end := buffer_end(buffer);
    while at < buf_end {
        defer eat(*at);

        if at.* == #char "\\" && at+1 < buf_end {
            buffer.colors[at-buffer.data] = .LANG_ESCAPED;
            eat(*at);
            buffer.colors[at-buffer.data] = .LANG_ESCAPED;
            continue;
        }

        buffer.colors[at-buffer.data] = .LANG_STRING_LITERAL;

        if at.* == token {
            break;
        }
    }
}

parse_numeric_value :: (buffer: *Buffer, _at: **u8) {
    at := _at.*;
    defer _at.* = at;

    c0 := at;
    c1 := at;

    maybe_float := false;
    maybe_hex   := false;

    buf_end := buffer_end(buffer);
    while at < buf_end {
        defer eat(*at);

        if !is_digit(at[0]) {
            if !maybe_float && !maybe_hex && at[0] == #char "." {
                maybe_float = true;
                continue;
            }
            if !maybe_float && !maybe_hex && at[0] == #char "x" {
                maybe_hex = true;
                continue;
            }

            c1 = at;
            break;
        }
    }

    colorize(buffer, .LANG_NUMERIC_VALUE, c0, c1);
}

parse_ident :: (buffer: *Buffer, _at: **u8) -> bool {
    at := _at.*;
    defer _at.* = at;
    
    c0 := at;
    c1 := at;

    buf_end := buffer_end(buffer);
    while at < buf_end {
        defer eat(*at);

        if is_multibyte_char(at) { // Identifiers cannot be multibyte
            while at < buf_end {
                if is_multibyte_char(at) {
                    at += 1 + trailingBytesForUTF8[at[0]];
                } else if is_alphanum(at[0]) {
                    break;
                }
            }
            
            return false;
        }
        
        if !is_alphanum(at[0]) {
            c1 = at;
            break;
        }
    }

    if c0 == c1 return false;

    ident := slice(buffer, c0, c1);
    if c0-1 >= buffer.data && (c0-1).* == #char "#" {
        colorize(buffer, .LANG_DIRECTIVE, c0-1, c1);
    } else if match_with_any_keyword(ident) {
        colorize(buffer, .LANG_KEYWORD, c0, c1);
    } else if c1 < buf_end && c1.* == #char "(" {
        colorize(buffer, .LANG_PROCEDURE_CALL, c0, c1);
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

eat :: inline (at: **u8) {
    at.* += 1 + trailingBytesForUTF8[at.*[0]];
}

is_multibyte_char :: inline (c: *u8) -> bool {
    return !!trailingBytesForUTF8[c[0]];
} 
#scope_export

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

is_alphanum :: (c: u32) -> bool {
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

////////////////////////

eat_characters :: inline (using lexer: *Lexer, bytes: s64 = 1) {
    defer c = ifx cursor then cursor[0] else 0;
    if cursor then advance(*cursor, bytes);
}

eat_character :: inline (using lexer: *Lexer) {
    eat_characters(lexer, bytes=1);
}

eat_whitespaces :: inline (using lexer: *Lexer) {
    while cursor && is_whitespace(c) {
        eat_character(lexer);
    }
}

eat_multibyte_alphanum_characters :: (using lexer: *Lexer) {
    while cursor {
        bytes := 1 + trailingBytesForUTF8[c];
        if bytes == 1 && !is_alphanum(c) break;
        eat_characters(lexer, bytes);
    }
}

peak_next_character :: inline (using lexer: *Lexer) -> u32 {
    if cursor.count < 2 return 0;
    return cursor[1];
}

add_token :: (using lexer: *Lexer) -> *Token {
    count    := cursor.data - left_cursor.data;
    byte_pos := (cursor.data - text.data) - count;
    
    if count == 0 return null;

    token := array_add(*tokens);
    token.* = .{byte_pos=byte_pos, count=count, type=.UNKNOWN};
    return token;
}

Lexer :: struct {
    c: u32;

    cursor: string;
    left_cursor: string;

    text: string;

    tokens: [..] Token;
};

Token :: struct {    
    byte_pos: s64;
    count: s64;

    type: Token_Type;
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
    PLAIN_TEXT :: (1<<0);
    C_STYLE    :: (1<<1);
    JAI        :: (1<<3);
}

////////////////////////

#scope_file

match_with_any_keyword :: inline (token_str: string) -> bool {
    _, found := table_find(*KEYWORDS_TABLE, token_str);
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
    "if", "else", "elseif", "return", "for", "while", "true", "false", "null", "string", "struct", "class", "enum", "union", "const", "yield", "static",
    "continue", "break", "default", "exit", "assert", "use", "namespace",
    "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "float", "float32", "float64", "size_t", "char", "short", "unsigned", "long", "int", "bool", "boolean", "double",
];

#import "Basic";
#import "Math";
#import "String";
#import "Unicode";