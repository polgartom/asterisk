
utf8_extract_identifier :: (s: string) -> (success: bool, identifier: string) {
    if !s return false, "";
    if !IsAlpha(s[0]) return false, "";

    t := s;
    while t {
        c := t[0];
        if !IsAlnum(c) break;

        bytes := 1 + trailingBytesForUTF8[c];
        advance(*t, bytes);
    }

    identifier := slice(s, 0, t.data-s.data);

    return true, identifier;
}