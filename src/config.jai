parse_color_config :: () {
    using handler: Text_File_Handler;
    
    data := DEFAULT_CONFIG_STRING;

    start_from_memory(*handler, "Colors", "(no path)", data);
    if failed return;

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
            if rhs.count != 10 || !begins_with(rhs, "0x") {
                error(handler, "Invalid hex value ('%') given after the '%' key specifier!\n", rhs, key);
                return;
            }

            advance(*rhs, "0x".count);

            result, success, rem := string_to_int(rhs, base=16, u32);
            if !success || rem {
                error(handler, "Unable to parse the hex value ('%') given after the '%' key specifier!\n", rhs, key);
                return;
            }

            color_enum := map_name_to_color(key);
            if color_enum == .NONE {
                error(handler, "Unable to find the color '%'!\n", key);
                return;
            }

            COLOR_MAP[color_enum] = hex_to_vec4(result); 
        }
    }

}

load_global_config :: () {
    parse_color_config();
}

DEFAULT_CONFIG_STRING :: #string CONFIG
[1] # Version number; do not delete!

[Color]
background:             0x0c1021ff
text_default:           0xddddddff
text_selection:         0xffffff20
text_highlight:         0x73ffff73
text_under_cursor:      0x0c1021ff
cursor:                 0xFBDE2Dc0
cursor_inactive:        0x01010166
cursor_line_background: 0xcccccc0A
footer_background:      0xd1b58eff
footer_text:            0x000000ff

CONFIG;

#scope_file

#import,file "file_handler.jai";