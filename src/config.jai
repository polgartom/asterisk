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

parse_project_config :: () {
    if !file_exists("./.asterisk/config") {
        return;    
    }
}

#scope_export

load_global_config :: () {
    parse_color_config();
    parse_project_config();
}

#scope_file

DEFAULT_CONFIG_STRING :: #string CONFIG
[1] # Version number; do not delete!

[Color]
#background:                 0c_1a_11_ff
#background:                 0c1a1aff

background:                 0f1a15ff
layout_separator:           dddddd1b
text_default:               c2c2c2ff
text_dimmed:                bbbbbbff
text_selection:             ffffff20
text_highlight:             e3_31_9f_6a
text_under_cursor:          0c1021ff
text_under_inactive_cursor: fbde2da0
cursor:                     fbde2dc0
cursor_inactive:            3a3a3aff
cursor_line_background:     cccccc0a
footer_background:          b0a070ff
footer_background_darken:   8b7c4dff
footer_text:                000000ff

#background:    0c1021ff
#text_default:  ddddddff
#widget_cursor: 47253aff
#cursor:        abde2dc0

#white:  ffffffff
#black:  000000ff
#chreme: a397a3ff

# Nice colors
#a397a3ff
#8b708bff
#b0a070ff
#7b904dff
#bb704dff   #red-ish

CONFIG;

#import,file "file_handler.jai";