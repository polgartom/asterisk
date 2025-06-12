close_current_widget :: () {
    if active_widget == {
        case Find_Global_Text_Dialog; close_find_global_text_dialog();
    };
    
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

// @Todo: Linux
// @Temporary
dialog_confirm :: (text: string, title: string = "", options: Dialog_Option = .YESNOCANCEL | .ICONWARNING) -> Dialog_Answer {
    #if OS == .WINDOWS {
        Win :: #import "Windows";
        Utf8 :: #import "Windows_Utf8";
        
        lpText := Utf8.utf8_to_wide(text,, temp); // If the string consists of more than one line, you can separate the lines using a carriage return and/or linefeed character between each line.
        lpCaption := lpText;
        if title then lpCaption = Utf8.utf8_to_wide(title,, temp);

        answer := Win.MessageBoxW(window, lpText, lpCaption, xx options);
        return xx answer;
    }

    return .UNKNOWN;
}

// @Todo: Linux
// @Temporary
dialog_get_save_file_name :: () -> string, bool {
    #if OS == .WINDOWS {
        Win :: #import "Windows";
        U :: #import "Windows_Utf8";

        OFN_FILEMUSTEXIST   :: 0x00001000;
        OFN_PATHMUSTEXIST   :: 0x00000800;
        OFN_OVERWRITEPROMPT :: 0x00000002;

        ofn: Win.OPENFILENAMEW;
        szFile: [Win.MAX_PATH] u16;

        zero_memory(*ofn, size_of(Win.OPENFILENAMEW));
        
        wd := get_working_directory();
        wd_wide, ok := U.utf8_to_wide(wd,, temp);
        if !ok {
            log_error("Failed to convert the get_working_directory() proc result from utf8 to wide!\n");
            return "", false;
        }

        ofn.lpstrInitialDir = wd_wide;
        ofn.lStructSize = size_of(Win.OPENFILENAMEW);
        ofn.hwndOwner = window;
        ofn.lpstrFile = *szFile[0];
        ofn.nMaxFile = size_of(type_of(szFile));
        
        // A buffer containing pairs of null-terminated filter strings. The last string in the buffer must be terminated by two NULL characters.
        filter_str :: "All Files\0*.*\0\0";
        wide, ok= := U.utf8_to_wide(filter_str,, temp);
        if !ok {
            log_error("Failed to convert the filter list string ('%') from utf8 to wide!\n", filter_str);
            return "", false;
        }

        ofn.lpstrFilter = wide;
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT;

        if (!Win.GetSaveFileNameW(*ofn)) {
            log("GetSaveFileNameW() returns FALSE. Maybe the user closed the dialog. OPENFILENAMEW: %\n", ofn);
            return "", false;
        }

        result, ok= := U.wide_to_utf8(ofn.lpstrFile,, temp);
        if !ok {
            log_error("Failed to convert the selected filepath (wide) to utf8!\n");
            return "", false;
        }

        return result, true;

    } else {
        // @Todo: Linux
        log_error("[TODO]: File save modal is not implemented yet!\n");
        return "", false;
    }
}

// @Temporary
Dialog_Answer :: enum s32 {
    UNKNOWN ::    0;
    OK ::         1;
    CANCEL ::     2;
    ABORT ::      3;
    RETRY ::      4;
    IGNORE ::     5;
    YES ::        6;
    NO ::         7;
    CLOSE ::      8;
    HELP ::       9;
    TRYAGAIN ::   10;
    CONTINUE ::   11;
}

// @Temporary
Dialog_Option :: enum_flags u32 {
    OK ::                       0x00000000;
    OKCANCEL ::                 0x00000001;
    ABORTRETRYIGNORE ::         0x00000002;
    YESNOCANCEL ::              0x00000003;
    YESNO ::                    0x00000004;
    RETRYCANCEL ::              0x00000005;
    CANCELTRYCONTINUE ::        0x00000006;

    ICONHAND ::                 0x00000010;
    ICONQUESTION ::             0x00000020;
    ICONEXCLAMATION ::          0x00000030;
    ICONASTERISK ::             0x00000040;
    USERICON ::                 0x00000080;
    ICONWARNING ::              ICONEXCLAMATION;
    ICONERROR ::                ICONHAND;
    ICONINFORMATION ::          ICONASTERISK;
    ICONSTOP ::                 ICONHAND;
}

#load "widget/label.jai";
#load "widget/text_input.jai";
#load "widget/list_input.jai";

#load "widget/find_text_dialog.jai";
#load "widget/find_global_text_dialog.jai";
#load "widget/goto_line_dialog.jai";

#load "widget/file_browser.jai";
#load "widget/buffer_browser.jai";
#load "widget/command_browser.jai";