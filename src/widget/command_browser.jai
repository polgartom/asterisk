open_command_browser :: () {
    using command_browser;

    if self_text_input {
        select_all(self_text_input);
    } else {
        self_text_input = create_text_input(cast(u64)#location());
    }

    switch_editor_mode(.WIDGET);
    active_widget = Command_Browser;

} @EditorCommandUnlisted(editor_keymap)

command_browser: Command_Browser;

Command_Browser :: struct {
    search_text: string;

    self_text_input: *Text_Input;
}