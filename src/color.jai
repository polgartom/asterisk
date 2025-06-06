map_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return COLOR_MAP[cast(s64) color];
}

map_default_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return DEFAULT_COLOR[cast(s64) color];
}

map_name_to_color :: (name: string) -> Color {
    #insert -> string {
        b: String_Builder;
        print_to_builder(*b, "if name == {\n");

        for name: enum_names(Color) {
            key_name := copy_string(name);
            to_lower_in_place(key_name);
            print_to_builder(*b, "case \"%\"; return .%;\n", key_name, name);
        }

        print_to_builder(*b, "}\n");

        return builder_to_string(*b);
    }

    return .NONE;
}

darken :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.x = lerp(color.x, 0, amount);
    result.y = lerp(color.y, 0, amount);
    result.z = lerp(color.z, 0, amount);
    result.w = color.w;

    return result;
}

whiten :: (color: Vector3, amount: float) -> Vector3 {
    result: Vector3;

    result.x = lerp(color.x, 1, amount);
    result.y = lerp(color.y, 1, amount);
    result.z = lerp(color.z, 1, amount);

    return result;
}

whiten :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.xyz = whiten(color.xyz, .5);
    result.w = color.w;

    return result;
}

COLOR_MAP_SIZE :: #run enum_highest_value(Color) + 1;
COLOR_MAP: [COLOR_MAP_SIZE] Vector4 = #run -> [] Vector4 {
    colors: [..]Vector4;
    for c: DEFAULT_COLOR array_add(*colors, c);
    return colors;
};

DEFAULT_COLOR :: #run -> [] Vector4 {
    colors: [..] Vector4;
    Add :: ($c: u32) #expand {
        array_add(*colors, #run hex_to_vec4(c));
    }

    for c: enum_values_as_enum(Color) {
        if #complete c == {
            case .NONE;                        Add(0x00000000);

            case .LANG_TOKEN_KEYWORD;          Add(0x9c9d29ff);
            case .LANG_TOKEN_DIRECTIVE;        Add(0xa8_6D_5A_ff);
            case .LANG_TOKEN_COMMENT;          Add(0x3f_7a_3fff);
            case .LANG_TOKEN_STRING_LITERAL;   Add(0x7a7a5a_ff);
            case .LANG_TOKEN_NUMERIC_VALUE;    Add(0x9A7E6Fff);
            case .LANG_TOKEN_PROCEDURE_CALL;   Add(0xacad89ff);
            case .LANG_TOKEN_ESCAPED;          Add(0x9c5d29ff);

            case .BACKGROUND;                  Add(0x0c1a21ff);
            case .BACKGROUND2;                 Add(0x212121ff);
            case .LAYOUT_SEPARATOR;            Add(0xdddddd1B);
            case .TEXT_DEFAULT;                Add(0xd0d0d0ff);
            case .TEXT_DIMMED;                 Add(0xbbbbbbff);
            case .TEXT_SELECTION;              Add(0x00_e1_fa_35);
            case .TEXT_SELECTION_MATCH;        Add(0xffffff20);
            case .TEXT_HIGHLIGHT;              Add(0xe3_71_ff_5a);
            case .TEXT_UNDER_CURSOR;           Add(0x0c1021ff);
            case .TEXT_UNDER_INACTIVE_CURSOR;  Add(0xFBDE2Da0);
            case .CURSOR;                      Add(0xFBDE2Dc0);
            case .CURSOR_INACTIVE;             Add(0x3a3a3aff);
            case .CURSOR_LINE_BACKGROUND;      Add(0xcccccc0A);
            case .FOOTER_BACKGROUND;           Add(0xb0a070ff);
            case .FOOTER_BACKGROUND_DARKEN;    Add(0x8b7c4dff);
            case .FOOTER_TEXT;                 Add(0x000000ff);
        }
    }

    return colors;
}

Color :: enum u8 {
    NONE :: 0;

    LANG_TOKEN_KEYWORD;
    LANG_TOKEN_DIRECTIVE;
    LANG_TOKEN_COMMENT;
    LANG_TOKEN_STRING_LITERAL;
    LANG_TOKEN_NUMERIC_VALUE;
    LANG_TOKEN_PROCEDURE_CALL;
    LANG_TOKEN_ESCAPED;

    BACKGROUND;
    BACKGROUND2;
    LAYOUT_SEPARATOR;
    TEXT_DEFAULT;
    TEXT_DIMMED;
    TEXT_SELECTION;
    TEXT_SELECTION_MATCH;
    TEXT_HIGHLIGHT;
    TEXT_UNDER_CURSOR;
    TEXT_UNDER_INACTIVE_CURSOR;
    CURSOR;
    CURSOR_INACTIVE;
    CURSOR_LINE_BACKGROUND;
    FOOTER_BACKGROUND;
    FOOTER_BACKGROUND_DARKEN;
    FOOTER_TEXT;
}

/*** NICE COLORS ***/
/* 
    0xc2c2_ff_ff - purple-ish
*/