
utf8_extract_identifier :: (s: string) -> (success: bool, identifier_or_remainder: string) {
    if !s return false, "";

    AdvanceUntilSeparator :: () #expand {
        while `t {
            defer {
                bytes := 1 + trailingBytesForUTF8[t[0]];
                advance(*t, bytes);
            };

            if !is_starting_identifier_character(t[0], .C_STYLE) break;
        }
    }

    GetTokenSlice :: (s: string, s_advanced: string, loc := #caller_location) -> string #expand {
        token := slice(s, 0, s_advanced.data - s.data);
        return token;
    }

    t := s;

    if is_starting_identifier_character(t[0], .C_STYLE) {
        advance(*t, 1);
    } else {
        if is_separator_char(t[0], include_underscore=true) {
            advance(*t, 1);
            return false, GetTokenSlice(s, t);
        }

        // Probably a not ascii character like á,ó,ű...
        AdvanceUntilSeparator();

        return false, GetTokenSlice(s, t);
    }

    while t {
        if !IsAlnum(t[0]) {
            if !is_separator_char(t[0], include_underscore=true) {
                // Probably a not ascii character like á,ó,ű...
                AdvanceUntilSeparator();
                return false, GetTokenSlice(s, t);
            }

            break;
        }

        bytes := 1 + trailingBytesForUTF8[t[0]];
        advance(*t, bytes);
    }

    identifier := GetTokenSlice(s, t);

    return true, identifier;
}

is_starting_identifier_character :: inline (c: u32, lang: Language.Type = .C_STYLE) -> bool {
    if lang == {
        case .C_STYLE;
            return IsAlpha(c) || c == #char "#";
    };

    return false;
}

IsAlpha :: (c: u32) -> bool #expand {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

IsDigit :: (c: u32) -> bool #expand {
    return (c >= #char "0" && c <= #char "9");
}

IsAlnum :: (c: u32) -> bool #expand {
    return IsAlpha(c) || IsDigit(c) || c == #char "_";
}

get_token_color :: inline (token: string, $lang: Language.Type) -> (found: bool, color: Vector4) {
    #if lang == {
        case .C_STYLE; {
            RESERVED_IDENTIFIERS :: string.[
                "if", "else", "elseif", "return", "for", "while", "true", "false", "null", "string",
                "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "float", "size_t", "char", "short", "unsigned", "long", "int", "bool", "double",
                "struct", "enum", "const", "continue", "break", "exit", "default", "then", "assert",
                "#if", "#ifdef", "#ifndef", "#endif", "#define", "#undef", "#include", "class", "union"
            ];

            for ident: RESERVED_IDENTIFIERS {
                if equal_nocase(token, ident) then return true, TOKEN_COLOR_IDENTIFIER;
            }
        }
    };

    fallback_color :: text_color;
    return false, fallback_color;
}

Language :: struct {
    identifiers: [] string;

    type: Language.Type;
    Type :: enum {
        NONE    :: 0;
        C_STYLE :: 1;        
    }
}

Token_Kind :: enum {
    UNKNOWN :: 0;
    IDENTIFIER :: 1;
    RESERVED_IDENTIFIER :: 2;
    NUMBER_LITERAL :: 3;
    STRING_LITERAL :: 4;
};