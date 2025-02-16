hex_to_vec4 :: (hex: u32) -> Vector4 {
    r := (hex>>24) & 0xFF;
    g := (hex>>16) & 0xFF;
    b := (hex>>8)  & 0xFF;
    a := (hex>>0)  & 0xFF;

    return .{
        r / 255.0, 
        g / 255.0, 
        b / 255.0, 
        a / 255.0
    };
}

map_color_to_vec4 :: inline (color: Color) -> Vector4 {
    return COLOR_MAP[cast(s64) color];
}

COLOR_MAP: [COLOR_MAP_SIZE] Vector4;
COLOR_MAP_SIZE :: #run enum_highest_value(Color) + 1;

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

Color :: enum u16 {
    NONE :: 0;

    BACKGROUND;
    TEXT_DEFAULT;
    TEXT_SELECTION;
    TEXT_HIGHLIGHT;
    TEXT_UNDER_CURSOR;
    CURSOR;
    CURSOR_INACTIVE;
    CURSOR_LINE_BACKGROUND;
    FOOTER_BACKGROUND;
    FOOTER_TEXT;
}