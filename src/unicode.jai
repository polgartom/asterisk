utf8_count_chars :: inline (s: string) -> s64 {
    count := 0;
    while s {
        advance(*s, 1 + trailingBytesForUTF8[s[0]]);
        count += 1;
    }

    return count;
}