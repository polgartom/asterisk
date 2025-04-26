//
// Save a keymap back to a file.
//
// Code contributed by D Bechard.
//
// When saving back to a file, we are stripping comments and possibly
// reordering the sections. So you don't want to use this code to overwrite
// source keymaps that are nice and commented. But if you have a program
// that lets the user rebind keys, and you have a default keymap that is
// then overlaid by the rebinds, you can save out the rebinds this way
// and load them on top of your textually-nice base keymap.
//

save_to_file :: (set: *Keymap_Set, filename: string) {
    builder: String_Builder;
    print_to_builder(*builder, set);
    write_entire_file(filename, *builder);
}

print_to_builder :: (builder: *String_Builder, set: *Keymap_Set) {
    print_to_builder(builder, "[1]  # Version number; do not delete!\n");
    for set.keymaps {
        print_to_builder(builder, "\n[%]\n", it.section_name);
        print_keymap_mappings_to_builder(builder, it);
    }
}

save_to_file :: (keymap: *Keymap, filename: string) {
    builder: String_Builder;
    print_to_builder(*builder, keymap);
    write_entire_file(filename, *builder);
}

print_to_builder :: (builder: *String_Builder, keymap: *Keymap) {
    print_to_builder(builder, "[1]  # Version number; do not delete!\n\n");
    print_keymap_mappings_to_builder(builder, keymap);
}

print_keymap_mappings_to_builder :: (builder: *String_Builder, keymap: *Keymap) {
    for keymap.mappings {
        key_chord_start := builder_string_length(builder);

        if it.modifier_flags.shift_pressed   print_to_builder(builder, "S-");
        if it.modifier_flags.ctrl_pressed    print_to_builder(builder, "C-");
        if it.modifier_flags.alt_pressed     print_to_builder(builder, "A-");
        // @ToDo: Keymap module doesn't currently handle cmd_meta_pressed, but probably should.
        if !it.respect_ignore_modifier_keys  print_to_builder(builder, "N-");

        key := map_key_to_string(xx it.utf32,, temp);
        print_to_builder(builder, "%", key);

        key_chord_length := builder_string_length(builder) - key_chord_start;

        // Vertical alignment
        LONGEST_MAPPING :: "S-C-A-N-Gamepad_LStickRight";
        for 0..(LONGEST_MAPPING.count - key_chord_length) {
            print_to_builder(builder, " ");
        }

        // To account for longer mappings than expected, we always print at least one space
        if it.command_string {
            print_to_builder(builder, " :%", it.command_string);
        } else {
            print_to_builder(builder, " %", keymap.procs[it.proc_index].name);
        }
        print_to_builder(builder, "\n");
    }
}

