open_command_browser :: () {
    using command_browser;

    if self_text_input {
        clear_text(self_text_input);
    } else {
        self_text_input = create_text_input(cast(u64)#location());

        array_reserve(*options, editor_commands.count);
        for * cmd: editor_commands {
            label_for_search := replace(cmd.name, " ", "");
            array_add(*options, .{label=cmd.name, ref=cmd, label_for_search=label_for_search});
        }
        
    }

    switch_editor_mode(.WIDGET);
    active_widget = Command_Browser;
}

command_browser: Command_Browser;

Command_Browser :: struct {
    search_text: string;

    self_text_input: *Text_Input;

    options: [..] List_Input.Option(*Editor_Command);
}