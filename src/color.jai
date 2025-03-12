
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

            case .LANG_KEYWORD;                Add(0x9c9d29ff);
            case .LANG_DIRECTIVE;              Add(0x569CD6ff);
            case .LANG_COMMENT;                Add(0x3f_7a_3fff);
            case .LANG_STRING_LITERAL;         Add(0x7a7a5a_ff);
            case .LANG_NUMERIC_VALUE;          Add(0xff4a2eff);
            case .LANG_PROCEDURE_CALL;         Add(0xacad89ff);
            case .LANG_ESCAPED;                Add(0x9c5d29ff);

            case .BACKGROUND;                  Add(0x0c1a21ff);
            case .LAYOUT_SEPARATOR;            Add(0xdddddd1B);
            case .TEXT_DEFAULT;                Add(0xd0d0d0ff);
            case .TEXT_DIMMED;                 Add(0xbbbbbbff);
            case .TEXT_SELECTION;              Add(0xffffff20);
            case .TEXT_HIGHLIGHT;              Add(0x73ffff73);
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

    LANG_KEYWORD;
    LANG_DIRECTIVE;
    LANG_COMMENT;
    LANG_STRING_LITERAL;
    LANG_NUMERIC_VALUE;
    LANG_PROCEDURE_CALL;
    LANG_ESCAPED;

    BACKGROUND;
    LAYOUT_SEPARATOR;
    TEXT_DEFAULT;
    TEXT_DIMMED;
    TEXT_SELECTION;
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