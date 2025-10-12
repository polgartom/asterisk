// @Cleanup: Shorter name
seek_left_one_utf8_character_byte_pos :: (s: string, _point: int) -> int {
    point := _point - 1;
    while point > 0 {
        c := s[point];
        if (192 & c) != 128  return point;
        point -= 1;
    }

    return 0;
}

// @Cleanup: Shorter name
seek_right_one_utf8_character_byte_pos :: (s: string, point: int) -> int {
    if point == s.count {
        return point;
    }
    return point + 1 + trailingBytesForUTF8[s[point]];
}

// @Cleanup: Naming
seek_left_utf8_until_alphanum :: (s: string, point: int, $include_last_non_alphanum_char := true) -> int {
    while point {
        point = seek_left_one_utf8_character_byte_pos(s, point);
        if !is_alphanum(s[point]) {
            #if !include_last_non_alphanum_char {
                point += 1;
            }
            break;
        }
    }

    return point;
}


#import "Unicode";