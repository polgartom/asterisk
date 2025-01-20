#scope_export

tokenize_c :: (text: string) -> [..] Token {
    lexer := Lexer.{text=text, initial_text=text};

    while lexer.cr < text.count {
        c := get_char(*lexer);

        if is_whitespace(c) {
            eat_spaces(*lexer);
            continue;

        } else if is_alpha(c) {
            token := parse_identifier(*lexer);
            if token then token.type = guess_token_type(*lexer, token);

        } else if c == #char "#" {
            token := parse_identifier(*lexer);
            if token then token.type = .DIRECTIVE;
        }

        if !eat_char(*lexer) break;
    }
    
    return lexer.tokens;
}

parse_identifier :: (using lexer: *Lexer) -> *Token {
    keep_up_left_cursor(lexer);

    while true {
        success, c := peak_next_char(lexer);
        if !success break;

        if 1 + trailingBytesForUTF8[c] > 1 {
            eat_multibyte_alphanum_chars(lexer);
            return null;
        }

        if !is_alphanum(c) {
            break;
        }

        eat_char(lexer);
    }

    token := add_token(lexer);
    return token;
}

guess_token_type :: (lexer: *Lexer, token: *Token) -> Token_Type {
    s := to_string(lexer, token);
    assert(s.count > 0);

    if s[0] == #char "#"                    return .DIRECTIVE;
    
    ok, next_char := peak_next_char(lexer);
    if ok && next_char == #char "("         return .PROCEDURE_CALL;
    
    if match_with_any_keyword(s)            return .KEYWORD;

    return .UNKNOWN;
}

match_with_any_keyword :: inline (token_str: string) -> bool {
    if !token_str return false;
    
    for keyword: KEYWORDS {
        if equal_nocase(token_str, keyword) return true;
    }

    return false;
}

// parse_identifier_like :: (using lexer: *Lexer) -> (valid: bool) {
//     while cr < text.count {
//         next_char := peak_next_char(lexer);
        
//         if 1 + trailingBytesForUTF8[next_char] > 1 {
//             // Invalid identifier character detected which is not a separator, like "ifá" or "őreturn"...
//             eat_multibyte_alphanum_chars(lexer);
//             return false;
//         }

//         if !is_alphanum(next_char) {
//             break;
//         }

//         eat_char(lexer);
//     }

//     return true;
// }


// parse_identifier :: (using lexer: *Lexer) -> bool, *Token {
//     parse_identifier_like(lexer);

//     valid, token := add_token(lexer, .IDENTIFIER);
//     return valid, token;
// }

// parse_directive :: (lexer: *Lexer) -> bool, *Token {
//     valid, token := parse_identifier(lexer);
//     if !valid return false, token;

//     token.type = .DIRECTIVE;
//     return true, token;
// }

#scope_file

KEYWORDS :: string.[
    "if", "else", "elseif", "return", "for", "while", "true", "false", "null", "string", "struct", "enum", "union", "const",

    "continue", "break", "default", "exit", "assert",
    
    "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "float", "size_t", "char", "short", "unsigned", "long", "int", "bool", "double",
    
    // "#if", "#ifdef", "#ifndef", "#endif", "#define", "#undef", "#include"
];

// #run {
//     lang := array_add(*LANGUAGES);
//     lang.type = .C_STYLE;
// }