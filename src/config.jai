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

    // @Cleanup: Set values dynamically?
    for line: lines {
        key, rhs := break_by_colon(line);

        if key == {
            case "font_size";
                val, success, rem := string_to_int(rhs, base=10, u8);
                if !success || rem {
                    error(handler, "Unable to parse the numeric value ('%') given after the '%' key specifier!\n", rhs, key);
                    continue;
                }

                ui.font_size = val;
            case "font_xs_size";
                val, success, rem := string_to_int(rhs, base=10, u8);
                if !success || rem {
                    error(handler, "Unable to parse the numeric value ('%') given after the '%' key specifier!\n", rhs, key);
                    continue;
                }

                ui.font_xs_size = val;

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

parse_project_config :: (data: string) {
    using handler: Text_File_Handler;

    start_from_memory(*handler, "Project", "(no path)", data);
    if failed return;

    defer deinit(*handler);

    lines: [..] string;
    lines.allocator = temporary_allocator;

    get_section_lines(*handler, "Project", *lines);
    if failed return;

    for line: lines {
        key, rhs := break_by_colon(line);

        key = trim(key);
        rhs = trim(rhs);

        if key == {
            case "files";
                slices := split(rhs, ",",, temp);
                for slices {
                    pattern := trim(it, " \"");
                    if !pattern continue;
                    table_add(*workspace.files, copy_string(pattern), true);
                }
            case "paths";
                slices := split(rhs, ",",, temp);
                for slices {
                    pattern := trim(it, " \"");
                    if !pattern continue;
                    table_add(*workspace.paths, copy_string(pattern), true);
                }
            case "exclude";
                slices := split(rhs, ",",, temp);
                for slices {
                    pattern := trim(it, " \"");
                    if !pattern continue;
                    table_add(*workspace.exclude, copy_string(pattern), true);
                }
        }

    }

}

#scope_export

load_global_config :: () {
    if !file_exists(config_filepath) {
        log_error("Unable to locate the global config file! '%'\n", config_filepath);
        return;
    }

    data, ok := File.read_entire_file(config_filepath);
    defer free_string(*data);
    if !ok {
        log_error("Unable to read the global config file! '%'\n", config_filepath);
        return;
    }

    if !check_config(data) {
        log_error("Failed to parse the global config file! '%'\n", config_filepath);
        return;
    }

    parse_color_config(data);
    parse_ui_config(data);
}

load_project_config :: () {
    path :: ".asterisk-project.cfg";

    if !file_exists(path) return;

    data := File.read_entire_file(path);
    if !check_config(data) {
        log_error("[%] failed to load the config '%'\n", #procedure_name(), path);
        return;
    }

    log("[%] config loaded!\n", #procedure_name(), path);

    parse_project_config(data);
}

#scope_file

CONFIG_VERSION :: 1;

_DEFAULT_PROJECT_CONFIG :: #string CONFIG
[1]

[Project]
# files: "*.jai", "*.txt", "*.bat", "*.sh"
# paths: "src", "modules"
# exclude: ".git", ".build", ".vs", ".vscode", ".idea"

CONFIG;

DEFAULT_CONFIG_STRING :: #run tprint(
    _DEFAULT_CONFIG_STRING, 
    CONFIG_VERSION
);

_DEFAULT_CONFIG_STRING :: #string CONFIG
[%] # Version number; do not delete!

[UI]
font_size: 14
font_xs_size: 13
cursor_shape: block             # block, line, underscore
cursor_line_indicator: filled   # none, filled, bordered

# Default theme
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

# JBLOW THEME
# [Color]
# background:                 122521ff
# layout_separator:           dddddd1b
# text_default:               BDB395ff
# text_dimmed:                bbbbbbff
# text_selection:             0000ffff
# text_highlight:             e3_31_9f_6a
# text_under_cursor:          0c1021ff
# text_under_inactive_cursor: fbde2da0
# cursor:                     86e08fff
# cursor_inactive:            3a3a3aff
# cursor_line_background:     cccccc0a
# footer_background:          b0a070ff
# footer_background_darken:   8b7c4dff
# footer_text:                000000ff
# lang_token_keyword: CCCCCCff
# lang_token_directive: CCCCCCff
# lang_token_numeric_value: B7CADDff
# lang_token_comment: 31B72Cff
# lang_token_string_literal: 2CA198ff
# lang_token_procedure_call: BDB395ff
# lang_token_escaped: CCCCCCff

# MODERN THEME (DARK)
# [Color]
# background:                 1A1A1AFF
# layout_separator:           0C1021FF
# text_default:               C0B9B9FF
# text_dimmed:                7C7C7CFF
# text_selection:             263238FF
# text_highlight:             FFEB3B_ff
# text_under_cursor:          455A64FF
# text_under_inactive_cursor: 455A64FF
# cursor:                     00bbecFF
# cursor_inactive:            9E9E9EFF
# cursor_line_background:     6a6a6a20
# footer_background:          263238FF
# footer_background_darken:   1C262BFF
# footer_text:                FFFFFFFF
# lang_token_keyword:         FF5252FF
# lang_token_directive:       F48FB1FF
# lang_token_numeric_value:   FF9800FF
# lang_token_comment:         9E9E9EFF
# lang_token_string_literal:  8BC34AFF
# lang_token_procedure_call:  00BCD4FF
# lang_token_escaped:         FF5722FF

CONFIG;

#import,file "file_handler.jai";