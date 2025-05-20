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

move_toward :: (a: float, b: float, amount_increasing: float, amount_decreasing := -1.0) -> float {
    if a > b {
        if amount_decreasing == -1  amount_decreasing = amount_increasing;

        a -= amount_decreasing;

        if a < b  a = b;
    } else {
        a += amount_increasing;
        if a > b  a = b;
    }

    return a;
}

// @Todo: Linux
// @Temporary
dialog_yes_no_cancel :: (text: string) -> Dialog_Answer {
    #if OS == .WINDOWS {
        Win :: #import "Windows";
        U :: #import "Windows_Utf8";
        
        modal_text := U.utf8_to_wide(text);
        result := Win.MessageBoxW(window, modal_text, modal_text, Win.MB_YESNOCANCEL | Win.MB_ICONWARNING);
        if result == {
            case Win.IDYES;
                return .YES;
            case Win.IDNO;
                return .NO;
            case Win.IDCANCEL; 
                return .CANCEL;
        };
    }

    return .UNKNOWN;
}

// @Temporary
Dialog_Answer :: enum u8 {
    UNKNOWN :: 0;
    YES     :: 1;
    NO      :: 2;
    CANCEL  :: 3;
}

#load "widget/label.jai";
#load "widget/text_input.jai";
#load "widget/list_input.jai";

#load "widget/find_text_dialog.jai";
#load "widget/goto_line_dialog.jai";

#load "widget/file_browser.jai";
#load "widget/buffer_browser.jai";
#load "widget/command_browser.jai";