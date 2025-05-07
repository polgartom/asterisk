map_name_to_ui_enum :: ($t: Type, name: string) -> (_enum: t, success: bool) {
    #insert -> string {
        b: String_Builder;
        print_to_builder(*b, "if name == {\n");

        enums := enum_names(t);
        assert(enums.count > 0, "Please add some enum member to '%'\n", t);
        
        for name: enums {
            key_name := copy_string(name);
            to_lower_in_place(key_name);
            print_to_builder(*b, "case \"%\"; return .%, true;\n", key_name, name);
        }

        print_to_builder(*b, "}\n");

        print_to_builder(*b, "return .%, false;\n", enums[0]);

        return builder_to_string(*b);
    }
}

ui: UI;

UI :: struct {
    font_size:    u8 = 14; // default 14
    font_xs_size: u8 = 13; // default 13

    cursor_shape := Cursor_Shape.BLOCK;
    cursor_line_indicator := Cursor_Line_Indicator.FILLED;

    Cursor_Shape :: enum u8 {BLOCK; LINE; UNDERSCORE;};
    Cursor_Line_Indicator :: enum u8 {NONE; FILLED; BORDERED;};
}
