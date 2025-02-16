
map_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return COLOR_MAP[cast(s64) color];
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

COLOR_MAP: [COLOR_MAP_SIZE] Vector4;
COLOR_MAP_SIZE :: #run enum_highest_value(Color) + 1;

Color :: enum u16 {
    NONE :: 0;

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
    FOOTER_TEXT;
}