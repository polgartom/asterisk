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
            
            rhs = join(..split(rhs, "_")); // The jai's numeric separation thing is supported, like '0c_10_21_ff' -> '0c1021ff' 
            if rhs.count != 8 {
                error(handler, "Invalid hex value ('%') given after the '%' key specifier!\n", rhs, key);
                return;
            }

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
background: 0c1021ff

layout_separator: dddddd1B

text_default:               ddddddff
text_dimmed:                bbbbbbff
text_selection:             ffffff20
text_highlight:             73ffff73
text_under_cursor:          0c1021ff
text_under_inactive_cursor: ffffffff

cursor:                 FBDE2Dc0
cursor_inactive:        4a4a4ac0
cursor_line_background: cccccc0A

footer_background:      d1b58eff
footer_text:            000000ff

CONFIG;

#scope_file

#import,file "file_handler.jai";