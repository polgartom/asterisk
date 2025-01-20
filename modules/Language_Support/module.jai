#scope_export

get_token_type_color :: inline (type: Token_Type) -> Vector4 {
    if type == {
        case KEYWORD;   return #run RgbaToVec4(180, 90, 45);
        case DIRECTIVE; return #run RgbaToVec4(180, 90, 45);
    };

    return text_color;
}

tokenize :: (s: string, $language: Language) -> [] Token {
    #if language & .C_STYLE return tokenize_c(s);

    return Token.[];
}

is_separator :: inline (c: s64, $include_underscore := true) -> bool {
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

is_alphanum :: inline (c: u32) -> bool{
    return is_alpha(c) || is_digit(c) || c == #char "_";
}

is_whitespace :: inline (c: s64) -> bool {
    assert(c != #char "\t", "We should convert all of the tabs to spaces");
    return c == #char " " || c == #char "\n";
}

////////////////////////

eat_char :: inline (using lexer: *Lexer) -> bool {
    success, character := peak_next_char(lexer);
    if !success return false;
    
    bytes := 1 + trailingBytesForUTF8[character];
    char_pos += 1;
    cr += bytes;

    return true;
}

eat_spaces :: inline (using lexer: *Lexer, $move_both_cursor := true) {
    t := advance(text, cr);
    while t {
        defer advance(*t, 1);
        if is_whitespace(t[0]) break;
    }

    cr = t.data - text.data;
    #if move_both_cursor then keep_up_left_cursor(lexer);
}

eat_multibyte_alphanum_chars :: inline (using lexer: *Lexer, $move_both_cursor := true) {
    t := advance(text, cr);
    while t {
        bytes := utf8_char_in_bytes(t);
        if bytes == 1 && !is_alphanum(t[0]) {
            break;
        }
        advance(*t, bytes);
    }

    cr = t.data - text.data;
    #if move_both_cursor then keep_up_left_cursor(lexer);
}

peak_next_char :: inline (using lexer: *Lexer) -> bool, u32 {
    t := advance(text, cr);
    bytes := utf8_char_in_bytes(t);
    advance(*t, bytes);
    
    if !t return false, 0;
    return true, t[0];
}

get_char :: inline (using lexer: *Lexer) -> u32 {
    if !text return 0;
    return text[cr];
}

add_token :: (using lexer: *Lexer) -> *Token { // Return null on unsuccessful
    if cr == cl return null;

    token := array_add(*tokens);
    token.* = .{byte_pos = cl, char_pos = char_pos, count = cr - cl, type = .UNKNOWN};
    
    return token;
}

keep_up_left_cursor :: inline (using lexer: *Lexer) {
    cl = cr;
}

slice :: inline (using lexer: *Lexer) -> string {
    return slice(text, cl, cr - cl);
}

utf8_char_in_bytes :: inline (s: string) -> s64 {
    assert(s.count > 0);
    return 1 + trailingBytesForUTF8[s[0]];
}

to_string :: inline (lexer: *Lexer, token: *Token) -> string {
    return slice(lexer.text, token.byte_pos, token.count);
}

Lexer :: struct {
    cl: s64;
    cr: s64;

    char_pos: s64;

    text: string;
    initial_text: string;

    tokens: [..] Token;
};

Token :: struct {    
    byte_pos: s64;
    char_pos: s64;

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
    PROCEDURE_CALL      :: 1;
}

Language :: enum_flags u64 {
    PLAIN_TEXT :: (1<<0);
    C_STYLE    :: (1<<1);
    JAI        :: (1<<3);
}

////////////////////////

#scope_file

#load "c.jai";

#import "Basic";
#import "Math";
#import "String";
#import "Unicode";