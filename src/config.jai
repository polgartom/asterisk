CURRENT_CONFIG_VERSION :: 1;

load_global_config :: () {
    config_path := get_editor_config_path();
    if !file_exists(config_path) {
        File.write_entire_file(config_path, DEFAULT_CONFIG_FILE_DATA);
    }

    data, ok := File.read_entire_file(config_path);
    defer free_string(*data);
    if !ok {
        data = copy_string(DEFAULT_CONFIG_FILE_DATA);
    }

    parse_config("Global Config", config_path, data);
}

load_project_config :: () {
    config_path := get_project_config_path();
    if !file_exists(config_path) return;

    file_data, ok := File.read_entire_file(config_path);
    defer free_string(*file_data);
    if !ok {
        return;
    }

    // [project]

    lines, valid := get_subsection_lines("project", file_data,, temp);
    if !valid return;

    array_reset_keeping_memory(*config.ignore);
    array_reset_keeping_memory(*config.allow);

    for line: lines {
        key, rhs := break_by_colon(line);

        if key == {
            case "ignore";
                slices := split(rhs, ",",, temp);
                for slices {
                    s := trim(it, "\" ");
                    slot := array_add(*config.ignore);
                    modify_string(slot, s);
                }
            case "allow";
                slices := split(rhs, ",",, temp);
                for slices {
                    s := trim(it, "\" ");
                    slot := array_add(*config.allow);
                    modify_string(slot, s);
                }
        };
    }

    // [command]

    // lines, valid := get_subsection_lines("command", file_data,, temp);
    // if !valid return;

    // for line: lines {
    //     key, rhs := break_by_colon(line);

    //     if key == {
    //         case "find_global_text";
    //             s := trim(rhs, "` ");
    //             if !s continue;
    //     };
    // }

}

get_editor_config_path :: () -> string {
    return tprint("%/asterisk-config.cfg", config_dir);
}

get_project_config_path :: () -> string {
    return tprint("%/.asterisk-project.cfg", working_dir);
}

parse_config :: (name: string, filename: string, file_data: string) -> bool {
    parse_style_section(file_data);

    if !#compile_time parse_keymap_section(file_data);

    return true;
}

parse_keymap_section :: (file_data: string) {
    keymap_data, found := get_section_as_string("keymap", file_data);
    if !found {
        keymap_data, found = get_section_as_string("keymap", DEFAULT_CONFIG_FILE_DATA);
        assert(found, "The [[keymap]] section is missing!\n");
    }

    load_from_memory :: (set: *Keymap_Set, memory: string) -> bool {
        handler: Text_File_Handler;
        handler.do_version_number = false;
        defer deinit(*handler);
        
        start_from_memory(*handler, "default", "(no path)", memory);
        if handler.failed return false;

        return load_from_handler(set, null, *handler);
    }

    success := load_from_memory(*keymap_set, keymap_data);
    assert(success);
}

parse_style_section :: (file_data: string) -> bool {
    push_allocator(temp);

    data, found := get_section_as_string("style", file_data);
    if !found return false;
        
    {
        lines, valid := get_subsection_lines("colors", data);
        if !valid return false;

        for line: lines {
            key, rhs := break_by_colon(line);

            rhs = join(..split(rhs, "_")); // The jai's numeric separation thing is supported, like '0c_10_21_ff' -> '0c1021ff' 
            if rhs.count != 8 {
                log_error("Invalid hex value ('%') given after the '%' key specifier!\n", rhs, key);
                continue;
            }

            result, success, rem := string_to_int(rhs, base=16, u32);
            if !success || rem {
                log_error("Unable to parse the hex value ('%') given after the '%' key specifier!\n", rhs, key);
                continue;
            }

            color_enum := map_name_to_color(key);
            // if color_enum == .NONE {
            //     log_error("Unable to find the color '%'!\n", key);
            //     continue;
            // }

            COLOR_MAP[color_enum] = hex_to_vec4(result);
        }
    }

    {
        lines, valid := get_subsection_lines("ui", data);
        if !valid return false;

        for line: lines {
            key, rhs := break_by_colon(line);

            if key == {
                // @Todo
                case "font_name";
                    val := trim(rhs);
                    if !val {
                        log_error("Invalid font name ('%') given after the '%' key specifier!\n", rhs, key);
                        continue;
                    }
                case "font_size";
                    val, success, rem := string_to_int(rhs, base=10, u8);
                    if !success || rem {
                        log_error("Unable to parse the numeric value ('%') given after the '%' key specifier!\n", rhs, key);
                        continue;
                    }

                    ui.font_size = val;
                case "font_xs_size";
                    val, success, rem := string_to_int(rhs, base=10, u8);
                    if !success || rem {
                        log_error("Unable to parse the numeric value ('%') given after the '%' key specifier!\n", rhs, key);
                        continue;
                    }

                    ui.font_xs_size = val;

                case "cursor_shape";
                    val, ok := map_name_to_ui_enum(UI.Cursor_Shape, rhs);
                    if !ok {
                        log_error("'%' is an invalid cursor shape!\n", rhs);
                        break;
                    }

                    ui.cursor_shape = val;

                case "cursor_line_indicator";
                    val, ok := map_name_to_ui_enum(UI.Cursor_Line_Indicator, rhs);
                    if !ok {
                        log_error("'%' is an invalid cursor line indicator!\n", rhs);
                        break;
                    }

                    ui.cursor_line_indicator = val;

                case;
                    log_error("Unknown UI parameter '%'!\n", key);
            };
        }
    }

    return true;
}

get_section_as_string :: (name: string, data: string) -> string, bool {
    section := tprint("[[%]]", name);

    i := find_index_from_left(data, section);
    if i == -1 return "", false;

    start := advance(data, i);
    section_line, found := consume_next_line(*start);
    if !found return "", false;

    i = find_index_from_left(start, "[[");
    if i == -1 {
        r := trim(start);
        return r, !!r.count;
    }

    r := slice(start, 0, i);
    r = trim(r);
    return r, !!r.count;
}

get_subsection_lines :: (name: string, data: string) -> [..] string, bool {
    lines: [..] string;
    lines.allocator = temp;

    subsection := tprint("[%]", name);
    add_lines := false;
    s := data;
    while true {
        line, found := consume_next_line(*s);
        if !found break;

        line = trim(line);
        comment_index := find_index_from_left(line, #char "#");
        if comment_index != -1 line.count = comment_index;
        if line.count == 0 continue;

        if begins_with(line, "[") {
            if !ends_with(line, "]") return lines, false;
            add_lines = line == subsection;

        } else if add_lines {
            array_add(*lines, line);
        }

    }

    return lines, true;
}

config: Config;

Config :: struct {
    ignore: [..] string;
    allow: [..] string;
}

Config_Section :: struct {
    name: string;
    subsections: [] string;
};

#scope_file

read_default_config_data :: (name: string) -> string {
    data := File.read_entire_file(tprint("config/%", name));
    data_with_replaced_version, occurrences := replace(data, "[0]  # Version", tprint("[%]  # Version", CURRENT_CONFIG_VERSION));
    assert(occurrences == 1, "Error when trying to replace the default config version in '%'", name);
    return data_with_replaced_version;
}

DEFAULT_CONFIG_FILENAME :: "default.asterisk-config.cfg";

#scope_export

DEFAULT_CONFIG_FILE_DATA :: #run read_default_config_data(DEFAULT_CONFIG_FILENAME);

// #run,stallable {
//     success := parse_config("Default Config", DEFAULT_CONFIG_FILENAME, DEFAULT_CONFIG_FILE_DATA);
//     assert(success, "Couldn't parse the default config file '%'!", DEFAULT_CONFIG_FILENAME);

//     DEFAULT_COLOR_MAP = COLOR_MAP;
// };

// DEFAULT_CONFIG :: #run,stallable -> Config {
//     config: Config;
    
//     success, default_config := parse_config("Default Config", DEFAULT_CONFIG_FILENAME, DEFAULT_CONFIG_FILE_DATA);
//     assert(success, "Couldn't parse the default config file '%'!", DEFAULT_CONFIG_FILENAME);
//     assert(!!default_config.keymap_section_data, "keymap_section_data is empty '%'!\n", DEFAULT_CONFIG_FILENAME);

//     DEFAULT_COLOR_MAP = COLOR_MAP;
    
//     return default_config;
// };

#scope_file

// # JBLOW THEME
// # [Color]
// # background:                 122521ff
// # layout_separator:           dddddd1b
// # text_default:               BDB395ff
// # text_dimmed:                bbbbbbff
// # text_selection:             0000ffff
// # text_highlight:             e3_31_9f_6a
// # text_under_cursor:          0c1021ff
// # text_under_inactive_cursor: fbde2da0
// # cursor:                     86e08fff
// # cursor_inactive:            3a3a3aff
// # cursor_line_background:     cccccc0a
// # footer_background:          b0a070ff
// # footer_background_darken:   8b7c4dff
// # footer_text:                000000ff
// # lang_token_keyword: CCCCCCff
// # lang_token_directive: CCCCCCff
// # lang_token_numeric_value: B7CADDff
// # lang_token_comment: 31B72Cff
// # lang_token_string_literal: 2CA198ff
// # lang_token_procedure_call: BDB395ff
// # lang_token_escaped: CCCCCCff

// # MODERN THEME (DARK)
// # [Color]
// # background:                 1A1A1AFF
// # layout_separator:           0C1021FF
// # text_default:               C0B9B9FF
// # text_dimmed:                7C7C7CFF
// # text_selection:             263238FF
// # text_highlight:             FFEB3B_ff
// # text_under_cursor:          455A64FF
// # text_under_inactive_cursor: 455A64FF
// # cursor:                     00bbecFF
// # cursor_inactive:            9E9E9EFF
// # cursor_line_background:     6a6a6a20
// # footer_background:          263238FF
// # footer_background_darken:   1C262BFF
// # footer_text:                FFFFFFFF
// # lang_token_keyword:         FF5252FF
// # lang_token_directive:       F48FB1FF
// # lang_token_numeric_value:   FF9800FF
// # lang_token_comment:         9E9E9EFF
// # lang_token_string_literal:  8BC34AFF
// # lang_token_procedure_call:  00BCD4FF
// # lang_token_escaped:         FF5722FF

#import "Text_File_Handler";