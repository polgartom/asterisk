
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

IsAlpha :: (c: u32) -> bool #expand {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

IsDigit :: (c: u32) -> bool #expand {
    return (c >= #char "0" && c <= #char "9");
}

IsAlnum :: (c: u32) -> bool #expand {
    return IsAlpha(c) || IsDigit(c) || c == #char "_";
}