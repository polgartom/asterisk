close_current_widget :: () {
    switch_editor_mode(.EDITOR);
}

register_widget_event :: (event: Event) {
    array_add(*events_to_handle_this_frame_for_widgets, event);
}

clear_widget_events :: () {
    array_reset_keeping_memory(*events_to_handle_this_frame_for_widgets);
}

active_widget: Type;
events_to_handle_this_frame_for_widgets: [..] Event;

#load "widget/label.jai";
#load "widget/text_input.jai";
#load "widget/list_input.jai";

#load "widget/find_text_dialog.jai";
#load "widget/file_browser.jai";