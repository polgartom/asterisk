//////////////////////////
// EDITOR



Editor :: struct {
    buffer: Buffer;
}

editor: Editor;

//////////////////////////
// BUFFER

to_string :: inline (buffer: Buffer) -> string {
    s: string = ---;
    s.count = buffer.count;
    s.data = buffer.data;
    return s;
}


Buffer :: struct {
    count: s64;
    allocated: s64;
    data: *u8;
}
