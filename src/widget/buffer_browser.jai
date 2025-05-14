open_buffer_browser :: () {
    using buffer_browser;

    if bb_text_input {
        select_all(bb_text_input);
    } else {
        bb_text_input = create_text_input(cast(u64)#location());
    }

    switch_editor_mode(.WIDGET);
    active_widget = Buffer_Browser;

} @EditorCommandUnlisted(editor_keymap)

buffer_browser: Buffer_Browser;

Buffer_Browser :: struct {
    search_text: string;

    bb_text_input: *Text_Input;
}