get_section_lines :: (using handler: *Text_File_Handler, wanted_section: string, lines: *[..] string) {
    section_found := false;

    str := file_data; // We want the whole str for this!
    while str {
        line, found := consume_next_line(*str);
        line_number += 1;

        if !found {
            failed = true;
            break;
        }

        line = trim(line);
        comment_index := find_index_from_left(line, #char "#");
        if comment_index != -1 line.count = comment_index;

        if line.count == 0 continue;
        if line[0] == #char "[" {
            advance(*line, 1);

            index := find_index_from_left(line, #char "]");
            if index == -1 {
                error(handler, "Invalid section name. '%' (line: %)!\n", line, line_number);
                failed = true;
                break;
            }

            if section_found break;

            section := line;
            section.count = index;

            if section != wanted_section continue;

            section_found = true;
            
        } else if section_found {
            array_add(lines, line);
        }
    }
}

parse_color_config :: (config_data: string) {
    using handler: Text_File_Handler;
    
    data := config_data;
    start_from_memory(*handler, "Colors", "(no path)", data);
    if failed return;

    defer deinit(*handler);

    //index := find_index_from_left(data, "[Color]");
    //assert(index != -1, "Unable to locate the [Color] section!");
    //advance(*data, index);

    current_section: string;

    while data {
        line, found := consume_next_line(*data);
        line_number += 1;

        if !found {
            failed = true;
            break;
        }

        line = trim(line);
        comment_index := find_index_from_left(line, #char "#");
        if comment_index != -1 line.count = comment_index;

        if line.count == 0 continue;
        if line[0] == #char "[" {
            advance(*line, 1);

            index := find_index_from_left(line, #char "]");
            if index == -1 {
                log_error("Invalid section name. '%' (line: %)!\n", line, line_number);
                failed = true;
                return;
            }

            section := line;
            section.count = index;
            
            if current_section == "Color" && !equal(section, "Color") {
                return;
            }

            current_section = section;

        } else if current_section == "Color" {
            key, rhs := break_by_colon(line);

            rhs = join(..split(rhs, "_")); // The jai's numeric separation thing is supported, like '0c_10_21_ff' -> '0c1021ff' 
            if rhs.count != 8 {
                error(handler, "Invalid hex value ('%') given after the '%' key specifier!\n", rhs, key);
                continue;
            }

            result, success, rem := string_to_int(rhs, base=16, u32);
            if !success || rem {
                error(handler, "Unable to parse the hex value ('%') given after the '%' key specifier!\n", rhs, key);
                continue;
            }

            color_enum := map_name_to_color(key);
            if color_enum == .NONE {
                error(handler, "Unable to find the color '%'!\n", key);
                continue;
            }

            COLOR_MAP[color_enum] = hex_to_vec4(result); 
        }
    }
}

parse_ui_config :: (config_data: string) {
    using handler: Text_File_Handler;
    
    data := config_data;
    start_from_memory(*handler, "UI", "(no path)", data);
    if failed return;
    
    lines: [..] string;
    defer {
        deinit(*handler);
        array_free(lines);
    }

    get_section_lines(*handler, "UI", *lines);
    if failed return;

    // @Cleanup: Set values dynamically!
    for line: lines {
        key, rhs := break_by_colon(line);

        if key == {
            case "cursor_shape";
                val, ok := map_name_to_ui_enum(UI.Cursor_Shape, rhs);
                if !ok {
                    warn(handler, "'%' is an invalid cursor shape!\n", rhs);
                    break;
                }

                ui.cursor_shape = val;

            case "cursor_line_indicator";
                val, ok := map_name_to_ui_enum(UI.Cursor_Line_Indicator, rhs);
                if !ok {
                    warn(handler, "'%' is an invalid cursor line indicator!\n", rhs);
                    break;
                }

                ui.cursor_line_indicator = val;

            case;
                warn(handler, "Unknown UI parameter '%'!\n", key);
        };
    }
}

// parse_project_config :: () {
//     if !file_exists("./.asterisk/config") {
//         return;    
//     }
// }

check_config :: (data: string) -> bool {
    str := data;
    
    if !str {
        log_error("Empty config given.\n");
        return false;
    }

    index := find_index_from_left(str, #char "\n");
    if index != -1 {
        str.count = index;
    }

    str = trim(str);
    if !str || str[0] != #char "[" {
        log_error("The config should start with the version number but this line given: |%|\n", str);
        return false;
    }

    advance(*str, 1);

    index = find_index_from_left(str, #char "]");
    if index == -1 {
        log_error("Invalid version section at the first line: |%|\n", str);
        return false;
    }

    str.count = index;

    version := string_to_int(str, base=10, u32);
    if version != CONFIG_VERSION {
        log_error("Outdated config file. Current version: %, given: %\n", CONFIG_VERSION, version);
        return false;
    }

    return true;
}

#scope_export

load_global_config :: () {
    config_data := DEFAULT_CONFIG_STRING;
    
    if file_exists(config_filepath) {
        data := File.read_entire_file(config_filepath);
        ok := check_config(data);
        if ok {
            config_data = data;
            ll("Config loaded from the '%' file\n", config_filepath);
        } else {
            ll("Using fallback config.\n");
        }

    } else {
        File.write_entire_file(config_filepath, DEFAULT_CONFIG_STRING);
        ll("Config file created as '%'\n", config_filepath);
    }

    parse_color_config(config_data);
    parse_ui_config(config_data);

    // parse_project_config();
}

#scope_file

CONFIG_VERSION :: 1;

DEFAULT_CONFIG_STRING :: #run tprint(
    _DEFAULT_CONFIG_STRING, 
    CONFIG_VERSION
);

_DEFAULT_CONFIG_STRING :: #string CONFIG
[%] # Version number; do not delete!

[UI]
cursor_shape: block             # block, line, underscore
cursor_line_indicator: filled   # none, filled, bordered

[Color]
background:                 0c1a21ff
layout_separator:           dddddd1b
text_default:               c2c2c2ff
text_dimmed:                bbbbbbff
text_highlight:             e3_31_9f_6a
text_under_cursor:          0c1021ff
text_under_inactive_cursor: fbde2da0
cursor:                     fbde2dc0
cursor_inactive:            3a3a3aff
cursor_line_background:     cccccc0a
footer_background:          b0a070ff
footer_background_darken:   8b7c4dff
footer_text:                000000ff

CONFIG;

#import,file "file_handler.jai";