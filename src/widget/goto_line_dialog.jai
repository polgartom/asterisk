
open_goto_line_dialog :: () {
    using goto_line_dialog;

    if !input {
        input = create_text_input(xx #location());
    }

    if input.text then select_all(input);

    switch_editor_mode(.WIDGET);
    active_widget = Goto_Line_Dialog;
}

update_goto_line_dialog :: () {
    using goto_line_dialog;

    for event: events_to_handle_this_frame_for_widgets {
        if event.type == .KEYBOARD {
            key := event.key_code;
            using Key_Code;
            if event.key_pressed {
                if key == {
                    case ENTER; goto_line();
                }
            }
        }
    }

}

get_goto_line_dialog_value :: () -> int, bool {
    using goto_line_dialog;
    
    if !input.text return 0, false;

    line, success, remainder := string_to_int(input.text);
    success &= !remainder;

    return line, success;
}

#scope_file

goto_line :: () {
    using goto_line_dialog;

    if !input.text return;

    editor, buffer := get_active_editor_and_buffer();
    if !editor || !buffer return;

    line, ok := get_goto_line_dialog_value();
    if ok && is_valid_line(buffer, line) {
        row := buffer.row_table[line-1];
        set_cursor_pos(buffer, *editor.cursor, row.start);
    }
}

#scope_export

goto_line_dialog: Goto_Line_Dialog;

Goto_Line_Dialog :: struct {
    input: *Text_Input;
}