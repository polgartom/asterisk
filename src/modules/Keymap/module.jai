// To do: Document!

#load "save.jai";

Keymap_Set :: struct {
    // We want to return pointers to Keymaps to the user, and these should remain valid,
    // so we use Bucket_Array to allocate the keymaps.

    keymaps: Bucket_Array(Keymap, 16, true);

    default_keymap: *Keymap;  // If you set this to something non-null, this will be the Keymap we use by default, when loading a file and we encounter a binding before the user has put a section header.
}

add_keymap :: (set: *Keymap_Set, section_name: string) -> *Keymap {
    //
    // We expect that section_name persists in memory; we don't copy it.
    //
    // If you want to add a keymap that doesn't get loaded from a file, and you
    // just want to populate it procedurally, you can pass the empty string
    // for section_name.
    //
    keymap := find_and_occupy_empty_slot(*set.keymaps);
    keymap.section_name = section_name;
    return keymap;
}

reset_keymaps :: (set: *Keymap_Set) {
    // Reset the state of all Keymaps, perhaps prior to reload.
    // Does not remove any Keymaps from the Keymap_Set;
    // it just clears all bindings from the Keymaps.

    for set.keymaps reset_keymap(it);
}

enable :: (set: *Keymap_Set, keymap: *Keymap, value: bool) {
    keymap.enabled = value;
}

handle_event :: (set: *Keymap_Set, event: Event) -> bool {
    for keymap: set.keymaps {
        if !keymap.enabled continue;
        handled := keymap_handle_event(keymap, event);
        if handled return true;  // Don't propagate to any later keymaps.
    }

    return false;
}

load_from_memory :: (set: *Keymap_Set, memory: string, short_name := "unnamed", full_path := "(no path)") -> bool {
    handler: Text_File_Handler;
    defer deinit(*handler);
    
    start_from_memory(*handler, short_name, full_path, memory);
    if handler.failed return false;

    return load_from_handler(set, null, *handler);
}

load_from_file :: (set: *Keymap_Set, short_name: string, filename: string, optional := false) -> bool {
    handler: Text_File_Handler;
    defer deinit(*handler);
    
    start_file(*handler, short_name, filename, optional=optional);
    if handler.failed return false;

    return load_from_handler(set, null, *handler);
}


Key_Press_Proc :: #type ();
Key_Hold_Proc  :: #type (bool);

Keymap :: struct {
    procs:    [..] Proc_Info;
    mappings: [..] Single_Key_Mapping;
    command_string_proc: (command: string);
    ignore_modifier_keys := false;

    Proc_Info :: struct {
        name:  string;
        press_\proc:   Key_Press_Proc;
        toggle_proc:   Key_Hold_Proc;
    }

    //
    // Members that may be assigned and used if this Keymap is in a Keymap_Set:
    //

    section_name: string;
    enabled := true;
}

Single_Key_Mapping :: struct {
    utf32: u32;
    respect_ignore_modifier_keys := true;  // controls whether the mapping respects the keymap's ignore_modifier_keys option or ignores it and does the opposite
    toggled_on := false;  // state variable to prevent redundant notifications for "toggle" callbacks
    
    modifier_flags:  Modifier_Flags;
    
    // Any mapping entry can either be a proc
    // or a command string (but not both!)
    
    command_string: string;
    proc_index: s32 = -1;  // To make copying mappings easy.
}

reset_keymap :: (keymap: *Keymap) {
    for keymap.mappings free(it.command_string);
    array_reset(*keymap.mappings);
}

reload_keymap :: (using keymap: *Keymap, short_name: string, filename: string, optional := false) -> bool #deprecated "Use load_from_file or load_from_memory instead." {
    return load_from_file(keymap, short_name, filename, optional);
}

load_from_file :: (using keymap: *Keymap, short_name: string, full_path: string, optional := false) -> bool {
    handler: Text_File_Handler;
    defer deinit(*handler);
    
    start_file(*handler, short_name, full_path, optional=optional);
    if handler.failed return false;

    return load_from_handler(null, keymap, *handler);
}

load_from_memory :: (using keymap: *Keymap, memory: string, short_name: string, full_path: string, optional := false) -> bool {
    handler: Text_File_Handler;
    defer deinit(*handler);
    
    start_from_memory(*handler, short_name, full_path, memory);
    if handler.failed return false;

    return load_from_handler(null, keymap, *handler);
}

load_from_handler :: (set: *Keymap_Set, keymap: *Keymap, handler: *Text_File_Handler) -> bool {
    {
        // The caller should pass either 'keymap', if we are loading just one keymap,
        // or 'set', if we are loading a set.

        assert(keymap || set);
        assert(!(keymap && set));
    }

    if set  keymap = set.default_keymap;  // Which may be null.
    
    while true {
        line, found_next_line := consume_next_line(handler);
        if !found_next_line break;

        if (line.count >= 2) && (line[0] == #char "[") && (line[1] != #char " ") {
            //
            // Is this a section header?
            // If so, respond appropriately.
            //

            // This string is trimmed, so the last character should be
            // a closing bracket.

            if line[line.count-1] != #char "]" {
                error(handler, "Trying to parse a section name, but the last character on the line is not ']'.\n");
                continue;
            }

            section_name := advance(line, 1);
            section_name.count -= 1;

            if !section_name {
                error(handler, "An empty section name is not valid!\n");
                continue;
            }

            if !set {
                error(handler, "A section name was provided here, but we are not loading a Keymap_Set, so we don't know what to do with section names.\n");
                continue;
            }
            
            // Does this section name refer to an existing keymap?
            found: *Keymap;
            for set.keymaps {
                if it.section_name == section_name {
                    found = it;
                    break;
                }
            }

            if !found {
                error(handler, "Section '%' does not exist.\n", section_name);
                continue;
            }

            keymap = found;

            continue;  // Handled!
        }
        
        key_name, rhs := break_by_spaces(line);
        if !rhs {
            error(handler, "Expected a space after the key specifier.\n");
            handler.failed = true;
            continue;
        }

        //
        // Parse modifier flags
        //

        modifier_flags: Event.Modifier_Flags;
        modifier_flags.packed = 0;

        respect_ignore_modifier_keys := true;
        
        modifier_string := key_name;
        while true {
            if modifier_string.count < 2        break;
            if modifier_string[1] != #char "-"  break;

            c := modifier_string[0];
            advance(*modifier_string, 2);

            if c == {
                case #char "S"; modifier_flags.shift_pressed = true;
                case #char "C"; modifier_flags.ctrl_pressed  = true;
                case #char "A"; modifier_flags.alt_pressed   = true;
                case #char "N"; respect_ignore_modifier_keys  = false;
                case; {
                    cstr: string;
                    cstr.data  = *c;
                    cstr.count = 1;
                    error(handler, "Unknown modifier character '%'.\n", cstr);
                    handler.failed = true;
                    continue;
                }
            }
        }

        //
        // Parse base thing.
        //

        key_string := modifier_string;

        if key_string.count == 0 {
            error(handler, "Missing key code after modifier_flags.\n");
            handler.failed = true;
            continue;
        }

        found_key, key := map_string_to_key(key_string);

        if !found_key {
            error(handler, "Unknown key name %.\n", key_string);
            handler.failed = true;
            continue;
        }

        // 
        // Parse command name
        //
        
        command: string;
        is_proc: bool;

        mapping: Single_Key_Mapping;
        if rhs[0] == #char ":" {
            advance(*rhs, 1);
            rhs = eat_spaces(rhs);
            
            command = rhs;
            is_proc = false;
        } else {
            command = rhs;
            is_proc = true;
        }

        if !keymap {
            // We asserted on entry that we have a keymap or a set.
            // Since we have no keymap, the caller is calling us with a set.
            error(handler, "We encountered a key binding here without any declaration of what section it goes in. Ignored.\n");
            continue;
        }
        
        success, reason := add_mapping(keymap, key, modifier_flags, respect_ignore_modifier_keys, command, is_proc=is_proc);
        if !success {
            if reason == {
                case .NONSENSICAL_MODIFIERS;
                error(handler, "This mapping is invalid: the key modifiers are redundant or don't make sense.");
                case .UNKNOWN_COMMAND; 
                error(handler, "This mapping is invalid: The command '%' is unknown.", command);

                case;
                error(handler, "This mapping is invalid, but add_mapping() did not return a good reason why, so we are sorry, but we can't give you better information here. The code should be fixed.\n");
            }
            
            handler.failed = true;
        }
    }

    return !handler.failed;
}

add_proc :: (keymap: *Keymap, name: string, proc: Key_Press_Proc) {
    info := array_add(*keymap.procs);
    info.name        = name;  // We don't copy this string...
    info.press_proc  = proc;
}

add_proc :: (keymap: *Keymap, name: string, proc: Key_Hold_Proc) {
    info := array_add(*keymap.procs);
    info.name         = name;  // We don't copy this string...
    info.toggle_proc  = proc;
}

Add_Mapping_Error_Type :: enum u8 {
    NO_INFORMATION_ABOUT_THE_ERROR :: 0;
    NONSENSICAL_MODIFIERS :: 1;
    UNKNOWN_COMMAND :: 2;
    NO_ERROR :: 3;
}

add_mapping :: (keymap: *Keymap, key: Key_Code, modifier_flags: Event.Modifier_Flags,
                respect_ignore_modifier_keys: bool, command: string, // Either the name of the proc or the argument to the command function.
                is_proc: bool  // Is the thing we're adding a procedure or a command?
               ) -> (success: bool, error_type: Add_Mapping_Error_Type) {
    
    if key == .SHIFT && modifier_flags.shift_pressed return false, .NONSENSICAL_MODIFIERS;
    if key == .CTRL  && modifier_flags.ctrl\_pressed return false, .NONSENSICAL_MODIFIERS;
    if key == .ALT   && modifier_flags.alt\ _pressed return false, .NONSENSICAL_MODIFIERS;

    mapping: Single_Key_Mapping;
    mapping.utf32 = xx key;
    mapping.modifier_flags = modifier_flags;
    mapping.respect_ignore_modifier_keys = respect_ignore_modifier_keys;
    
    if is_proc {
        for * keymap.procs {
            if it.name == command {
                mapping.proc_index = cast(s32)it_index;
                break;
            }
        }

        if mapping.proc_index == -1 return false, .UNKNOWN_COMMAND;
    } else {
       mapping.command_string = copy_string(command);
    }

    stomped := false;

    for * keymap.mappings {
        if (it.utf32 == mapping.utf32) && (it.modifier_flags.packed == modifier_flags.packed) {
            // assert(!stomped); // There should only ever be one of each input.
            stomped = true;
            free(it.command_string);
            it.* = mapping;
        }
    }

    if !stomped array_add(*keymap.mappings, mapping);

    return true, .NO_ERROR;
}


keymap_handle_event :: (keymap: Keymap, e: Event) -> bool {
    event := e;
    if event.type != .KEYBOARD return false;

    key_code := cast(u32) event.key_code;  // @Cleanup: Comparing event.key_code versus it.utf32 ... inconsistent since event has utf32 also, but it's 0 for keyboard events.
    
    handled := false;
    
    // If the key press itself is a modifier, then the modifier flags will be set but we should ignore them. This is so we can map things to just modifier keys and nothing else.
    if event.key_pressed {
        if      event.key_code == .SHIFT event.modifier_flags.shift_pressed = false;
        else if event.key_code == .CTRL  event.modifier_flags.ctrl\_pressed = false;
        else if event.key_code == .ALT   event.modifier_flags.alt\ _pressed = false;
    }
    

    //
    // ignore_modifier_keys is for games where, say, you want to press WASD to move
    // around, but you also want to be able to press shift, ctrl, alt, whatever, and
    // have those modifiers not change the meaning of the WASD.
    //
    // However, sometimes in those mappings you want some keys that definitely only
    // work with no modifiers. For example, we wanted to map the ENTER key to
    // open a playtest-comment window; but when the player presses alt-enter,
    // that should toggle fullscreen, not open the comment window. So we added the
    // respect_ignore_modifier_keys flag on the individual entry which can be turned
    // off in the keymap file with N.
    //

    for * keymap.mappings {
        if event.key_pressed {
            // If this event matches, then process it.
            if it.utf32 == key_code && (keymap.ignore_modifier_keys == it.respect_ignore_modifier_keys || it.modifier_flags.packed == event.modifier_flags.packed) {
                if it.proc_index >= 0 {
                    info := *keymap.procs[it.proc_index];
                    if info.toggle_proc {
                        if !it.toggled_on  info.toggle_proc(true);
                        it.toggled_on = true;
                    }

                    if info.press_proc then info.press_proc();
                } else if it.command_string {
                    if keymap.command_string_proc {
                        keymap.command_string_proc(it.command_string);
                    } else {
                        log_error("Keymap has no command_string_proc, but we are trying to run a command string!\n");  // There is no name slot on Keymap, so we can't say which one!
                    }
                }

                return true; // We only handle the first thing that matches for presses.
            }
        } else {
            // If this is a key_up event for a modifier key, we want to notify mappings that require those
            // modifier keys that the key combo has been released.  For example, if you have a mapping for
            // CTRL-X and you press CTRL-X and then release the CTRL key.
            if it.toggled_on && (it.utf32 == key_code || (keymap.ignore_modifier_keys != it.respect_ignore_modifier_keys && event.modifier_flags.packed != it.modifier_flags.packed)) {
                it.toggled_on = false;

                if it.proc_index >= 0 {
                    info := *keymap.procs[it.proc_index];
                    if info.toggle_proc then info.toggle_proc(false);
                }
                
                handled = true;
            }
        }
    }

    return handled;
}


map_string_to_key :: (s: string) -> bool, Key_Code {
    for key_with_names {
        if s == it.name return true, it.key; 
    }

    utf32, success := utf8_next_character(*s);
    if success != .CONVERSION_OK return false, 0;
    if s.count > 0 return false, 0;
    
    // We always use uppercase for key codes
    if #char "a" <= utf32 && utf32 <= #char "z" {
       utf32 -= (#char "a" - #char "A");
    }

    return true, xx utf32;
}

map_key_to_string :: (k: Key_Code) -> string {
    for key_with_names {
        if it.key == k return copy_string(it.name);
    }

    return character_utf32_to_utf8(xx k);
}

//
// You might use keymap_copy if, for example, you are
// loading keystrokes from a default keymap into another one
// that you let players rebind, or something like that.
//
keymap_copy :: (source: *Keymap, dest: *Keymap) {
    reset_keymap(dest);

    dest.procs.count = 0;
    
    array_add(*dest.procs,    ..source.procs);
    array_add(*dest.mappings, ..source.mappings);
}

//
// Copy only the procs, which you might want to do if you have
// multiple Keymaps that do the same set of things, but one of them
// has bindings that shadow the other one, or maybe you have some
// default bindings in a Keymap, and you want to create a new
// Keymap only for new bindings that have the same functionality.
//
keymap_copy_procs :: (source: *Keymap, dest: *Keymap) {
    dest.procs.count = 0;
    array_add(*dest.procs,    ..source.procs);
}

#scope_file

Modifier_Flags :: Event.Modifier_Flags;

GB :: Key_Code.GAMEPAD_0_BEGIN;  // Used in key_with_names[] below.

key_with_names: [] struct { name: string; key: Key_Code; } = .[
    .{ "ESC", .ESCAPE },
    .{ "ENTER", .ENTER },  // Kept this for backward compatibility.
    .{ "TAB", .TAB },    // Kept this for backward compatibility.
    
    .{ "F1", .F1 },
    .{ "F2", .F2 },
    .{ "F3", .F3 },
    .{ "F4", .F4 },
    .{ "F5", .F5 },
    .{ "F6", .F6 },
    .{ "F7", .F7 },
    .{ "F8", .F8 },
    .{ "F9", .F9 },
    .{ "F10", .F10 },
    .{ "F11", .F11 },
    .{ "F12", .F12 },
    
    .{ "ArrowUp", .ARROW_UP },
    .{ "ArrowDown", .ARROW_DOWN },
    .{ "ArrowLeft", .ARROW_LEFT },
    .{ "ArrowRight", .ARROW_RIGHT },

    .{ "MouseLeft", .MOUSE_BUTTON_LEFT },
    .{ "MouseRight", .MOUSE_BUTTON_RIGHT },
    .{ "MouseMiddle", .MOUSE_BUTTON_MIDDLE },
    .{ "MouseWheelUp", .MOUSE_WHEEL_UP },
    .{ "MouseWheelDown", .MOUSE_WHEEL_DOWN },
    
    .{ "Gamepad_ArrowUp", GB + xx Gamepad_Code.DPAD_UP },
    .{ "Gamepad_ArrowDown", GB + xx Gamepad_Code.DPAD_DOWN },
    .{ "Gamepad_ArrowLeft", GB + xx Gamepad_Code.DPAD_LEFT },
    .{ "Gamepad_ArrowRight", GB + xx Gamepad_Code.DPAD_RIGHT },

    .{ "Gamepad_LStickUp", GB + xx Gamepad_Code.LEFT_STICK_UP },
    .{ "Gamepad_LStickDown", GB + xx Gamepad_Code.LEFT_STICK_DOWN },
    .{ "Gamepad_LStickLeft", GB + xx Gamepad_Code.LEFT_STICK_LEFT },
    .{ "Gamepad_LStickRight", GB + xx Gamepad_Code.LEFT_STICK_RIGHT },

    .{ "Gamepad_RStickUp", GB + xx Gamepad_Code.RIGHT_STICK_UP },
    .{ "Gamepad_RStickDown", GB + xx Gamepad_Code.RIGHT_STICK_DOWN },
    .{ "Gamepad_RStickLeft", GB + xx Gamepad_Code.RIGHT_STICK_LEFT },
    .{ "Gamepad_RStickRight", GB + xx Gamepad_Code.RIGHT_STICK_RIGHT },

    .{ "Gamepad_LStickClick", GB + xx Gamepad_Code.LEFT_STICK_CLICK },
    .{ "Gamepad_RStickClick", GB + xx Gamepad_Code.RIGHT_STICK_CLICK },

    .{ "Gamepad_Start", GB + xx Gamepad_Code.START },
    .{ "Gamepad_Back", GB + xx Gamepad_Code.BACK },
    
    .{ "Gamepad_LShoulder", GB + xx Gamepad_Code.LEFT_SHOULDER },
    .{ "Gamepad_RShoulder", GB + xx Gamepad_Code.RIGHT_SHOULDER },
    .{ "Gamepad_LTrigger", GB + xx Gamepad_Code.LEFT_TRIGGER },
    .{ "Gamepad_RTrigger", GB + xx Gamepad_Code.RIGHT_TRIGGER },

    .{ "Gamepad_A", GB + xx Gamepad_Code.A },
    .{ "Gamepad_B", GB + xx Gamepad_Code.B },
    .{ "Gamepad_X", GB + xx Gamepad_Code.X },
    .{ "Gamepad_Y", GB + xx Gamepad_Code.Y },

    .{ "Delete", .DELETE },
    .{ "Insert", .INSERT },
    .{ "End", .END },
    .{ "Home", .HOME },
    .{ "Backspace", .BACKSPACE },
    .{ "PrintScreen", .PRINT_SCREEN },
    .{ "Pause", .PAUSE },
    .{ "PageUp", .PAGE_UP },
    .{ "PageDown", .PAGE_DOWN },
    .{ "ScrollLock", .SCROLL_LOCK },
    .{ "Enter", .ENTER },
    .{ "Return", .ENTER },
    .{ "Tab", .TAB },
    .{ "Shift", .SHIFT },
    .{ "Alt", .ALT },
    .{ "Control", .CTRL },
    .{ "Space", xx(#char " ")},
];

#scope_module
#import "Text_File_Handler";
#import "Basic";
#import "Input";
#import "Gamepad";
#import "Unicode";  // For utf8_next_character, sigh!
#import "Bucket_Array";
#import "File";
