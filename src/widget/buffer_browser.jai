open_buffer_browser :: () {
    using buffer_browser;

    switch_editor_mode(.WIDGET);
    active_widget = Buffer_Browser;
}

buffer_browser: Buffer_Browser;

Buffer_Browser :: struct {
    search_text: string;
}