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
    // time := seconds_since_init();
    // defer print("tokenization: %ms\n", (seconds_since_init() - time) * 1000);
    
    if (!buffer.count) return;

    colorize(buffer, Color.TEXT_DEFAULT, .{0,  buffer.count});

    at := buffer.data;
    end := buffer_end(buffer);
    if at == end return;

    // print("--next--\n");
    while at < end {
        if is_alpha(at[0]) {
            ok := true;
            if at > buffer.data {
                prev := at-1;
                ok = is_separator(prev[0], false);
            }
            if ok then parse_ident(buffer, *at);
        } 
        if at[0] == #char "/" && at+1<end && at[1] == #char "/" {
            start := at - buffer.data;
            steps := find_index_from_left(.{count=end-at,data=at}, #char "\n");
            if steps == -1 then steps = end - at;
            colorize(buffer, Color.LANG_COMMENT, .{start, start+steps});
            at += steps;
        }
        if at[0] == #char "\"" {            
            index := at - buffer.data;
            buffer.colors[index] = .LANG_STRING_LITERAL;

            eat(*at);
            while at < end {
                if at[0] == #char "\"" {
                    index := at - buffer.data;
                    buffer.colors[index] = .LANG_STRING_LITERAL;
                    break;
                }
                index := at - buffer.data;
                buffer.colors[index] = .LANG_STRING_LITERAL;

                eat(*at);
            }
        }

        if at < end then eat(*at);
    }

}

#scope_file

parse_ident :: (buffer: *Buffer, _at: **u8) -> bool {
    at := _at.*;
    defer _at.* = at;
    start := at;

    buf_end := buffer_end(buffer);

    while at < buf_end {
        if is_multibyte_char(at) { // Identifiers cannot be multibyte
            while at < buf_end {
                if is_multibyte_char(at) {
                    at += 1 + trailingBytesForUTF8[at[0]];
                } else if is_alphanum(at[0]) {
                    break;
                }

                eat(*at);
            }
            
            return false;
        }
        
        if !is_alphanum(at[0]) {
            break;
        }

        eat(*at);
    }

    start_index := start - buffer.data;
    end_index := at - buffer.data;
    if start_index == end_index return false;

    ident := slice(buffer, start_index, end_index - start_index);

    if ident.data-1 >= buffer.data && (ident.data-1).* == #char "#" {
        colorize(buffer, .LANG_DIRECTIVE, .{start_index-1, end_index});
    } else if inline match_with_any_keyword(ident) {
        colorize(buffer, .LANG_KEYWORD, .{start_index, end_index});
    } else if end_index < buffer.count && buffer.data[end_index] == #char "(" {
        colorize(buffer, .LANG_PROCEDURE_CALL, .{start_index, end_index});
    }

    return true;
}

colorize :: inline (b: *Buffer, color: Color, range: Range) {
    memset(b.colors.data + range.start, cast(u8, color), range.end - range.start);
}

eat :: inline (at: **u8) {
    at.* += 1 + trailingBytesForUTF8[at.*[0]];
}

is_multibyte_char :: inline (c: *u8) -> bool {
    return !!trailingBytesForUTF8[c[0]];
} 
#scope_export

// tokenize :: (s: string, $language: Language) -> [] Token {
//     #if language & .C_STYLE return tokenize_c(s);

//     return Token.[];
// }

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

#load "lang/c.jai";

#import "Basic";
#import "Math";
#import "String";
#import "Unicode";