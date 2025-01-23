#scope_export

tokenize_c :: (input_text: string) -> [] Token {
    if !input_text return .[];

    lexer := Lexer.{c=input_text[0], cursor=input_text, text=input_text};
    using lexer;

    while cursor {
        if is_alpha(c) || c == #char "#" {
            parse_identifier(*lexer);
            continue;
        } else if c == #char "/" {
            nc := peak_next_character(*lexer);
            if nc == #char "*" {
                parse_multiline_comment(*lexer);
                continue;
            } else if nc == #char "/" {
                parse_inline_comment(*lexer);
                continue;
            }
        }
        
        eat_character(*lexer);
    }
    
    return lexer.tokens;
}

parse_identifier :: (using lexer: *Lexer) {
    left_cursor = cursor;
    eat_character(lexer);

    while cursor {
        is_multibyte_char := trailingBytesForUTF8[c];
        if is_multibyte_char {
            eat_multibyte_alphanum_characters(lexer);
            return;
        }

        defer eat_character(lexer);

        if !is_alphanum(c) {
            token := add_token(lexer);
            if token != null then token.type = guess_token_type(lexer, token);
            return;
        }
    }
}

parse_inline_comment :: (using lexer: *Lexer) {
    left_cursor = cursor;
    eat_character(lexer);

    while cursor {
        if is_line_end(c) break;
        eat_character(lexer);
    }

    token := add_token(lexer);
    token.type = .COMMENT_INLINE;
}

parse_multiline_comment :: (using lexer: *Lexer) {
    left_cursor = cursor;
    eat_character(lexer);

    end_found := false;
    while cursor {
        if inline begins_with(cursor, "*/") {
            eat_characters(lexer, 2);
            end_found = true;
            break;
        }

        eat_character(lexer);
    }

    token := add_token(lexer);
    token.type = .COMMENT_MULTILINE;
    
    // @Cleanup: It's silly because at this point we probably got an EOF
    if !end_found {
        eat_character(lexer);
    }
}

guess_token_type :: (lexer: *Lexer, token: *Token) -> Token_Type {
    s := slice(lexer.text, token.byte_pos, token.count);
    assert(s.count > 0);

    if s[0] == #char "#" return .DIRECTIVE;

    if match_with_any_keyword(s) return .KEYWORD;
    
    if token.byte_pos + token.count < lexer.text.count {
        next_character := lexer.text[token.byte_pos + token.count];
        if next_character == #char "(" {
            return .PROCEDURE_CALL;
        }
    }
    
    return .UNKNOWN;
}

match_with_any_keyword :: inline (token_str: string) -> bool {
    if !token_str return false;
    
    for keyword: KEYWORDS {
        if equal_nocase(token_str, keyword) return true;
    }

    return false;
}

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