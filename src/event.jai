
user_events: [..] User_Event;

User_Event :: struct {
    type: User_Event_Type;
}

User_Event_Type :: enum {
    UNKNOWN :: 0;
}