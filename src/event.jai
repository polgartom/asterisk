handle_user_events :: () {
    for < user_events {
        if it.type == {
            case .CLOSE_WIDGET;
                switch_editor_mode(.EDITOR);
        };
    }

    array_reset_keeping_memory(*user_events);
}

user_events: [..] User_Event;

User_Event :: struct {
    type: User_Event_Type;
}

User_Event_Type :: enum {
    UNKNOWN :: 0;
    CLOSE_WIDGET :: 1;
}
