Config :: struct {
    ui_bg_color: Color;
    ui_fg_color: Color;
}

parse_config :: (data: string) {
    handler: Text_File_Handler;
    defer deinit(*handler);

    start_from_memory(*handler, "config", "(no path)", data);
    assert(!handler.failed, "Failed to parse the config!\n");

    while true {
        line, found := consume_next_line(*handler);
        if !found break;   // consume_next_line returns false for 'found' when we are done.

        key_name, rhs := break_by_colon(line);
        if !rhs {
            error(handler, "Expected a colon (:) after the key specifier.\n");
            continue;
        }

        param, found= := table_find(*config_params, key_name);
        if !found {
            error(handler, "'%' is an invalid config parameter.\n", key_name);
            continue;
        }
        
        if param.type == {
            case type_info(Color);
                if !begins_with(rhs, "0x") {
                    error(handler, "'%' is an invalid color value given after the '%' key specifier.\n", rhs, key_name);
                    continue;
                }

                advance(*rhs, 2);

                result, success, rem := string_to_int(rhs, base=16, u32);
                if !success || rem {
                    error(handler, "'%' is an invalid color value given after the '%' key specifier.\n", rhs, key_name);
                    continue;
                }

                val := hex32_to_vector4(result);
                set(key_name, *val);

            case type_info(bool);
                val, success := parse_bool(*rhs);
                if !success {
                    error(handler, "'%' is an invalid boolean given after the '%' key specifier.\n", rhs, key_name);
                    continue;
                }

                set(key_name, *val);
            case;
                error(handler, "Unhandled type! param: %\n", param);
                continue;
        }

    }
    
}

set :: (key_name: string, value: *$T) {
    param, found := table_find(*config_params, key_name);
    assert(found != false, "key: %\n", key_name);

    ptr := cast(*u8)*config;

    dest := ptr + param.offset_in_bytes;
    memcpy(dest, value, size_of(T));

    print("[set]: % -> %\n", key_name, (cast(*T)dest).*);
}

#scope_export

config_params: Table(string, Type_Info_Struct_Member);
using config: Config;

init_config :: () {
    // #run pre_check_members(Config);

    for type_info(Config).members {
        table_add(*config_params, copy_string(it.name), it);
    }

    parse_config(DEFAULT_CONFIG_STRING);
}

hex32_to_rgba :: (hex: u32) -> r: float, g: float, b: float, a: float {
    r := (hex>>24) & 0xFF;
    g := (hex>>16) & 0xFF;
    b := (hex>>8)  & 0xFF;
    a := (hex>>0)  & 0xFF;

    return r/255.0, g/255.0, b/255.0, a/255.0;
}

hex32_to_vector4 :: (hex32: u32) -> Vector4 {
    r,g,b,a := hex32_to_rgba(hex32);
    return .{r, g, b, a};
}

Color :: #type,isa Vector4;

#scope_module

DEFAULT_CONFIG_STRING :: #string DONE
[1]

ui_bg_color: 0x0c1021ff
ui_fg_color: 0xddddddff

DONE;

#load "file_handler.jai";

#import "Math";
#import "Hash_Table";