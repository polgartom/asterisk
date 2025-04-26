//
// Is_Set is a compile-time-generated type, that conveniently
// tells you which of your options were set by the user (as opposed
// to which still hold default values. You could test against a default
// value, but what if the user explicitly set the value to the same
// as your default, and you need to know that??)
//
// If you don't care whether a user explicitly set any value, you
// can ignore this. If you do care, just use the correspondingly-named
// fields of Is_Set.
//
// For example, if your arguments struct is:
//
// Arguments :: struct {
//     hello:  int;
//     my:     [3] string;
//     friend: float64;
// }
//
// Then the generated Is_Set will look like this:
//
// Is_Set (Arguments) :: struct {
//     hello  := false;
//     my     := false;
//     friend := false;
// }

//
// and these fields will be set to true if the corresponding values in
// Arguments were set by the user.
//
//
// So your usage code might look like this:
//
// success, args, is_set := parse_arguments(Arguments);
//
// if success {
//     if is_set.friend  do_something_with(args.friend);
// }
//

//
// You can, on your arguments struct, put notes that will get printed
// out to the user as help strings if the user passes -help (or
// whatever you designate as help_triggers to parse_arguments()).
// If a note starts with ? it is output as a comment string.
// You can mark up your struct members as follows:
//
// Arguments :: struct {
//     hello:  int;        @"?Set this to be polite."
//     my:     [3] string; @"?It's a mystery what these are."
//     friend: float64;    @"?Set this higher to enable better friendship."
// }
//

// @Incomplete: Report polymorph stack from compiler_report, so that we don't need dummy_*.
// @Incomplete: Robustly handle quoted arguments on Windows, Linux, which are terrible for not giving you arguments the right way.
// @Incomplete: Vet to_integer, make it better.
// @Incomplete: Handle enum arguments.

// @Incomplete: Is_Set doesn't know anything about #place and will generate
// multiple entries for #place'd members and the things they are placed upon.
Is_Set :: struct (T: Type) {
    #insert -> string {
        info := type_info(T);

        builder: String_Builder;

        for * member: info.members {
            if should_skip(member) continue;
            name := copy_string(member.name);
            print_to_builder(*builder, "    % := false;\n", name);
        }

        return builder_to_string(*builder);
    };
}

Argument_Flags :: enum_flags u64 {
    FREE_ARGUMENTS_ALLOWED :: 0x1;
    DOUBLE_DASH_REQUIRED   :: 0x2;
    SHOW_HELP_ON_ERROR     :: 0x4;
    SORT_HELP              :: 0x8;  // If set, sort the possible arguments lexicographically before printing them in help. If you want to grouping common things together manually, clear this flag.
    ALIGN_HELP             :: 0x10; // If set, indent the descriptions to the length of the longest variable.
}

Default_Argument_Flags :: Argument_Flags.FREE_ARGUMENTS_ALLOWED|.SORT_HELP|.ALIGN_HELP;

parse_arguments :: ($T: Type, flags := Default_Argument_Flags, help_triggers : [] string = .["help", "HELP", "?"]) -> (success: bool, result: T, is_set: Is_Set(T), free_arguments: [..] string) {
    result: T;

    args := get_command_line_arguments();
    defer array_free(args);

    free_arguments: [..] string;

    is_set: Is_Set(T);

    #run pre_check_members(T);

    //
    // Right now there is not much point in making this separate copy of 'members',
    // but later we probably want further processing, in the case of aliases to the
    // same command-line argument. So it may make sense to operate on a processed
    // array instead.
    //

    members: [..] *Type_Info_Struct_Member;
    members.allocator = __temporary_allocator;

    info := type_info(T);  // Known to be Type_Info_Struct if we passed pre_check_members.

    for * member: info.members {
        if should_skip(member) continue;
        array_add(*members, member);
    }

    state: Parsing_State;
    state.args   = args;
    state.cursor = 1;

    bool_base := cast(*bool) *is_set;

    success := true;
    only_free_arguments := false;
    while state.cursor < args.count {
        arg := args[state.cursor];

        is_dashed := arg && (arg[0] == #char "-");
        if is_dashed && !only_free_arguments {
            if (arg == "--") && (flags & .FREE_ARGUMENTS_ALLOWED) {
                only_free_arguments = true;
                state.cursor += 1;
                continue;
            } else if flags & .DOUBLE_DASH_REQUIRED {
                // require_double_dash is here for people who want to make programs compatible
                // with all the new-style Linux stuff that uses arguments --like --this.
                // But it's not recommended. Since we don't support single-character options
                // here, -- in this way doesn't make sense, really, for new things.
                is_dashed = (arg.count > 1) && (arg[1] == #char "-");
            }
        }

        if !is_dashed || only_free_arguments {
            if flags & .FREE_ARGUMENTS_ALLOWED {
                array_add(*free_arguments, arg);
                state.cursor += 1;
                continue;
            } else {
                dashes := ifx flags & .DOUBLE_DASH_REQUIRED  then "--" else "-";

                log_error("Command-line argument % does not start with '%'.", state.cursor, dashes);
                return false, result, is_set, free_arguments;
            }
        }

        advance(*arg, 1);
        if flags & .DOUBLE_DASH_REQUIRED advance(*arg, 1);
        state.name = arg;

        found := false;
        for member: info.members {
            if member.name != arg continue;
            found = true;

            slot := (cast(*u8) *result) + member.offset_in_bytes;

            member_success := handle_one_argument(slot, *state, member.type);
            if member_success {
                bool_pointer := bool_base + it_index;  // Warning: Unbounded memory write potential.
                if << bool_pointer {
                    log_error("Argument '%' was given multiple times.", state.name);
                    success = false;
                }

                << bool_pointer = true;
            } else {
                success = false;
            }

            break;  // Once we have found the proper struct member, stop!

            // @CompilerBug: We used to have 'handle_one_argument' here, but it tripped a bug in the scope tracking stuff.
        }

        if !found {
            for help_triggers {
                if arg == it {
                    show_help(T, flags, help_triggers);
                    found = true;
                    success = false;
                    break;
                }
            }
        }

        if !found {
            log_error("Command-line argument % ('%') is not valid.", state.cursor, arg);
            success = false;

            if flags & .SHOW_HELP_ON_ERROR {
                show_help(T, flags, help_triggers);
            } else if help_triggers {
                log_error("Use -% to list the valid arguments.\n", help_triggers[0]);
            }
        }

        if !success break;
        state.cursor += 1;
    }


    return success, result, is_set, free_arguments;
}

show_help :: ($T: Type, flags: Argument_Flags, help_triggers: [] string) {
    ti := type_info(T);

    helps: [..] *Type_Info_Struct_Member;
    helps.allocator = temp;

    lines: [..] string;
    lines.allocator = temp;

    widest_help := 0;
    for * member: ti.members {
        array_add(*helps, member);
        widest_help = max(widest_help, member.name.count);
    }

    if flags & .SORT_HELP {
        quick_sort(helps, (a, b) => compare_strings(a.name, b.name));
    }

    for helps {
        description: string;
        for note: it.notes {
            if note && note[0] == #char "?" {
                description = advance(note, 1);
            }
        }

        if description {
            // @Simplicity: We could make this just be a 1-liner if we had a spaces() function.
            builder: String_Builder;
            print_to_builder(*builder, "-%: ", it.name);
            if flags & .ALIGN_HELP {
                spaces := widest_help - it.name.count;
                for 1..spaces append(*builder, " ");
            }

            append(*builder, description);

            array_add(*lines, builder_to_string(*builder,, allocator=temp));
        } else {
            array_add(*lines, tprint("-%", it.name));
        }
    }

    if help_triggers {
        array_add(*lines, "");  // An intentionally blank line.
        line := join(..help_triggers, ", -");
        defer free(line);  // @Lazy: Should set allocator here.
        array_add(*lines, tprint("-%: Show the list of commands.", line));
    }

    if lines.count == 0 {
        if flags & .FREE_ARGUMENTS_ALLOWED {
            print("----- There are no valid command-line options, just free arguments. -----\n");
        } else {
            print("----- There are no valid command-line options. -----\n");
        }
    } else if lines.count == 1 {
        print("----- Here is the only valid argument: -----\n");
    } else {
        print("----- Here is the list of valid arguments: -----\n");
    }

    for lines print("    %\n", it);
}

#scope_file

#import "Basic";
Math :: #import "Math";
#import "Compiler";
#import "String";
#import "Sort";

Parsing_State :: struct {
    args: [] string;
    name: string;
    cursor: int;

    inside_array := false;
    current_array_index  := 0;
    array_indices_needed := 0;
}

handle_one_argument :: (slot: *u8, state: *Parsing_State, info: *Type_Info) -> bool {
    using Type_Info_Tag;
    success := true;

    if info.type == {
      case STRING;
        // @Improvement: Have an option that says that if we see a string that starts with -, it is a mistake?
        string_success, value := get_next_argument(state, *success);
        if string_success {
            (<< cast(*string) slot) = copy_string(value);
        }

      case INTEGER;
        string_success, string_value := get_next_argument(state, *success);
        if !string_success return false;

        tii := cast(*Type_Info_Integer) info;

        write_success: bool;
        if tii.signed {
            write_success = parse_and_write_integer(state, tii, slot, string_value, signed = true);
        } else {
            write_success = parse_and_write_integer(state, tii, slot, string_value, signed = false);
        }
        if !write_success success = false;

      case BOOL;
        (<< cast(*bool) slot) = true;

      case FLOAT;
        string_success, string_value := get_next_argument(state, *success);
        if !string_success return false;

        value, float_success, remainder := string_to_float64(string_value);
        if !float_success {
            log_error("Value of argument %, '%' was not a float. (It was '%').", state.cursor, state.name, string_value);
            success = false;
        } else {
            if info.runtime_size == 4 {
                (<< cast(*float) slot) = cast(float) value;
            } else {
                assert(info.runtime_size == 8);
                (<< cast(*float64) slot) = value;
            }
        }

      case ARRAY;
        tia := cast(*Type_Info_Array) info;

        count := tia.array_count;
        assert(count >= 0);  // Because we checked for this when making the 'members' array.

        element_type := tia.element_type;

        old_state := << state;
        state.inside_array = true;
        state.array_indices_needed = count;

        for i: 0..count-1 {
            state.current_array_index = i;
            new_slot := slot + element_type.runtime_size * i;
            arg_success := handle_one_argument(new_slot, state, element_type);
            if !arg_success {
                success = false;
                break;
            }
        }

        // Restore the state's array variables ... note that we might have already
        // been inside an array (it's multidimensional!!), so don't just set it to false.

        state.inside_array         = old_state.inside_array;
        state.current_array_index  = old_state.current_array_index;
        state.array_indices_needed = old_state.array_indices_needed;

      case ENUM;
        string_success, string_value := get_next_argument(state, *success);
        if !string_success return false;

        success = false;

        tie := cast(*Type_Info_Enum) info;
        if tie.enum_type_flags & .FLAGS {
            // Maybe flags would be fine to support, but I am being cautious. Maybe you'd want FLAG_1|FLAG_2 etc.
            log_error("Argument % ('%') is declared enum_flags, which is not supported.", state.cursor, state.name);

        } else {
            for tie.names {
                // Q: Should this be case insensitive? Enum names are case sensitive so I have erred on the side of
                // caution. Maybe it should be an option in Argument_Flags?
                if it == string_value {
                    success = true;
                    enum_value := tie.values[it_index];
                    Reflection.set_enum_value(slot, tie, enum_value);
                    break;
                }
            }

            if !success  log_error("Error with argument % ('%'), provided value '%' is not a member of %", state.cursor, state.name, string_value, tie.name);
        }
        case;
        log_error("Argument % ('%') is of unsupported type %.", state.cursor, state.name, info.type);
        success = false;
    }

    return success;
}

get_next_argument :: (using state: *Parsing_State, success: *bool) -> (success: bool, value: string) {
    if cursor >= args.count - 1 {
        if state.inside_array && (state.current_array_index > 0) {
            log_error("Not enough values for argument '%' (only got %, but we need %).", name, state.current_array_index, state.array_indices_needed);
        } else {
            log_error("Missing the value for argument '%'.", name);
        }

        << success = false;
        return false, "";
    } else {
        cursor += 1;
        return true, args[cursor];
    }
}

parse_and_write_integer :: (state: *Parsing_State, info: *Type_Info_Integer, pointer: *void, string_value: string, $signed: bool) -> bool {
    #if signed {
        Int_Type :: s64;
    } else {
        Int_Type :: u64;
    }

    int_value, int_success, remainder := string_to_int(string_value, T = Int_Type);
    if !int_success || remainder {
        #if signed {
            log_error("The value of argument %, '%' was not an integer. (It was '%').", state.cursor, state.name, string_value);
        } else {
            log_error("The value of argument %, '%' was not an unsigned integer. (It was '%').", state.cursor, state.name, string_value);
        }
        return false;
    }

    valid, low, high := Reflection.range_check_and_store(int_value, info, pointer);

    if !valid {
        log_error("The value of argument %, '%' is out of range. (It was % but must be between % and %.)", state.cursor, state.name, int_value, low, high);
        return false;
    }

    return true;
}

should_skip :: (member: *Type_Info_Struct_Member) -> bool {
    if member.flags & (member.flags.CONSTANT | .IMPORTED) return true;
    return false;
}

dummy_filename :: "(@Incomplete: We don't provide the filename and line number yet. My sincerest apologies.)";
dummy_l0 :: 0;
dummy_c0 :: 0;

pre_check_members :: ($T: Type)
#modify {
    info := cast(*Type_Info) T;
    return info.type == .STRUCT, "Type passed to parse_arguments is not a struct!";
}
{
    info := type_info(T);

    for * member: info.members {
        if should_skip(member) continue;
        // :ConstantSourceCodeLocation

        if member.type.type == .ARRAY {
            tia := cast(*Type_Info_Array) member.type;
            if tia.array_count == -1 {
                compiler_report(dummy_filename, dummy_l0, dummy_c0, tprint("Member '%' is an array of undetermined size; this is not yet handled in argument parsing (if it will ever be).", member.name));
            }
        }
    }
}

Reflection :: #import "Reflection";
